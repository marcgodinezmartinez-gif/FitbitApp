import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import HealthAPI
@testable import Insights
@testable import MetricsKit
@testable import Store
@testable import SyncKit

final class CannedTransport: HTTPTransport, @unchecked Sendable {
    let responses: [String: String]
    init(_ r: [String: String]) { responses = r }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url!.path
        let key = responses.keys.sorted { $0.count > $1.count }.first { path.hasSuffix($0) }
        let body = key.map { responses[$0]! } ?? "{}"
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

struct FakeWatch: AppleHealthProvider {
    let imp: AppleHealthImport
    var isAvailable: Bool { true }
    func requestAuthorization() async throws {}
    func importChanges(anchors: AnchorStore, backfillDays: Int) async throws -> AppleHealthImport {
        try anchors.setAnchor(Data([1]), for: "workouts")
        return imp
    }
}

@Suite struct FirstLaunchTests {
    @Test func emptyDatabaseRecomputesAndSyncsWithoutSources() async throws {
        let db = try AppDatabase.inMemory()
        let engine = SyncEngine(db: db, google: nil, apple: nil)
        let out = try await engine.recompute()
        #expect(out.cycles.isEmpty || out.current != nil)
        let report = await engine.sync(.open)
        #expect(report.google.skipped && report.apple.skipped)
        #expect(report.notifications.isEmpty)
    }
}

@Suite struct MappingTests {
    @Test func skipsHealthKitPlatformAndMapsSleep() throws {
        let json = """
        {"dataPoints":[
         {"name":"a","dataSource":{"platform":"HEALTH_KIT"},"exercise":{"exerciseType":"RUNNING","interval":{"startTime":"2026-09-28T16:00:00Z","endTime":"2026-09-28T16:45:00Z"}}},
         {"name":"b","dataSource":{"platform":"FITBIT"},"exercise":{"exerciseType":"RUNNING","displayName":"Correr","interval":{"startTime":"2026-09-28T16:02:00Z","endTime":"2026-09-28T16:44:00Z","startUtcOffset":"7200s"},
           "metricsSummary":{"distanceMillimeters":8100000,"averageHeartRateBeatsPerMinute":"151","steps":"6900"}}},
         {"name":"s","sleep":{"interval":{"startTime":"2026-09-27T21:10:00Z","endTime":"2026-09-28T05:00:00Z","startUtcOffset":"7200s"},"metadata":{"mainSleep":true},
           "stages":[{"type":"LIGHT","startTime":"2026-09-27T21:10:00Z","endTime":"2026-09-27T23:00:00Z"},{"type":"RESTLESS","startTime":"2026-09-27T23:00:00Z","endTime":"2026-09-27T23:05:00Z"}]}}
        ]}
        """
        let r = try JSONDecoder().decode(ListDataPointsResponse.self, from: Data(json.utf8))
        let acts = GoogleMapping.activities(r.dataPoints!)
        #expect(acts.count == 1)
        #expect(acts[0].kind == .running && acts[0].distanceM == 8100 && acts[0].avgHR == 151 && acts[0].utcOffsetSeconds == 7200)
        let sleeps = GoogleMapping.sleepSessions(r.dataPoints!)
        #expect(sleeps.count == 1 && sleeps[0].isMainFromSource == true)
        #expect(sleeps[0].stages.last?.stage == .wake)
    }

    @Test func vitalsPreferFitbit() throws {
        let json = """
        {"dataPoints":[
         {"dataSource":{"platform":"FITBIT"},"dailyRestingHeartRate":{"date":{"year":2026,"month":9,"day":28},"beatsPerMinute":"52"}},
         {"dataSource":{"platform":"GOOGLE_WEB_API"},"dailyRestingHeartRate":{"date":{"year":2026,"month":9,"day":28},"beatsPerMinute":"60"}}
        ]}
        """
        let r = try JSONDecoder().decode(ListDataPointsResponse.self, from: Data(json.utf8))
        let v = GoogleMapping.vitals(hrv: [], rhr: r.dataPoints!, spo2: [], rr: [], temp: [])
        #expect(v.first?.restingHR == 52)
    }
}

@Suite struct SyncEngineTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func syncsBothSourcesAndPlansRunNotification() async throws {
        let db = try AppDatabase.inMemory()
        var s = AppSettings()
        s.healthKitEnabled = true
        s.quietHoursStart = 0
        s.quietHoursEnd = 0
        try db.saveSettings(s)
        let synthetic = SyntheticData.generate(days: 20, endingAt: now, utcOffsetSeconds: 7200)
        // La Fitbit ya está en la BD; el Watch llega por Salud con una carrera nueva.
        try db.saveProfile(synthetic.profile)
        try db.upsertSleepSessions(synthetic.sleepSessions)
        try db.mergeVitals(synthetic.vitals)
        try db.upsertHRMinutes(synthetic.hrFitbit)
        try db.upsertActivityMinutes(synthetic.fitbitMinutes)
        try db.upsertActivities(synthetic.activities.filter { $0.source == .googleHealth })
        let watch = synthetic.activities.filter { $0.source == .appleHealth }
        let fake = FakeWatch(imp: AppleHealthImport(workouts: watch, heartRateMinutes: synthetic.hrWatch))
        let tokens = InMemoryTokenStore(TokenSet(accessToken: "a", refreshToken: "r", expiresAt: .distantFuture, scope: nil))
        let google = GoogleHealthClient(config: OAuthConfig(clientID: "c", reversedClientID: "r"),
                                        transport: CannedTransport(["pairedDevices": #"{"pairedDevices":[{"deviceType":"TRACKER","deviceVersion":"Fitbit Air","lastSyncTime":"2026-09-21T13:00:00Z","batteryLevel":80}]}"#]),
                                        tokens: tokens, sleep: { _ in })
        let engine = SyncEngine(db: db, google: google, apple: fake, now: { now }, utcOffset: { 7200 })
        let report = await engine.sync(.open)
        #expect(report.apple.ok && !report.apple.skipped)
        #expect(report.google.ok && !report.google.skipped)
        #expect(report.newWatchWorkoutIDs.count == watch.count)
        #expect(report.output?.fusedActivities.contains { $0.sources == [.appleHealth, .googleHealth] } == true)
        #expect(report.notifications.contains { $0.id == "NOT-12" })
        #expect(report.snapshot != nil)
        #expect(try db.anchor(for: "workouts") == Data([1]))
        #expect(try db.connection().deviceName == "Fitbit Air")
        // Segunda sincronización: nada nuevo que avisar.
        let again = await engine.sync(.pull)
        #expect(!again.notifications.contains { $0.id == "NOT-12" })
    }

    @Test func notificationLimits() {
        var settings = AppSettings()
        settings.quietHoursStart = 22 * 60 + 30
        settings.quietHoursEnd = 7 * 60
        let many = (0..<5).map { PlannedNotification(id: "NOT-12", key: "k\($0)", title: "t", body: "b") }
        let noon = Date(timeIntervalSince1970: TimeInterval(1_790_000_000 - (1_790_000_000 % 86_400) + 12 * 3600))
        #expect(NotificationPlanner.limit(many, sent: [:], now: noon, settings: settings, utcOffsetSeconds: 0).count == 3)
        let night = noon.addingTimeInterval(11 * 3600) // 23:00
        #expect(NotificationPlanner.limit(many, sent: [:], now: night, settings: settings, utcOffsetSeconds: 0).isEmpty)
        let critical = [PlannedNotification(id: "NOT-07", key: "x", title: "t", body: "b", critical: true)]
        #expect(NotificationPlanner.limit(critical, sent: [:], now: night, settings: settings, utcOffsetSeconds: 0).count == 1)
    }
}

@Suite struct PlanNotificationTests {
    /// Viernes 2 de octubre de 2026 a las 12:00 UTC (14:00 en UTC+2).
    let friday = ISO8601DateFormatter().date(from: "2026-10-02T12:00:00Z")!

    @Test func fridayReviewAndMondayReport() throws {
        let db = try AppDatabase.inMemory()
        let input = SyntheticData.generate(days: 30, endingAt: friday, utcOffsetSeconds: 7200)
        let out = MetricsEngine.run(input)
        try db.saveWeeklyPlan(WeeklyPlan(goals: WeeklyPlan.goals(for: .fitness), template: .fitness))
        let today = LocalDate(friday, utcOffsetSeconds: 7200)
        let progress = try #require(try db.weeklyPlanProgress(output: out, today: today))
        #expect(progress.weekStart == LocalDate(year: 2026, month: 9, day: 28))
        #expect(progress.daysElapsed == 5)

        var settings = AppSettings()
        settings.notifications["NOT-01"] = false
        let planned = NotificationPlanner.plan(output: out, newWatchWorkoutIDs: [], connection: ConnectionState(), settings: settings,
                                               sent: [:], now: friday, utcOffsetSeconds: 7200, weeklyPlan: progress)
        let review = try #require(planned.first { $0.id == "NOT-11" })
        #expect(review.body.hasPrefix("Vas al"))
        #expect(review.key == "NOT-11:2026-09-28")
        // Ya enviado: no se repite.
        let again = NotificationPlanner.plan(output: out, newWatchWorkoutIDs: [], connection: ConnectionState(), settings: settings,
                                             sent: [review.key: friday], now: friday, utcOffsetSeconds: 7200, weeklyPlan: progress)
        #expect(!again.contains { $0.id == "NOT-11" })

        // El lunes siguiente avisa del informe semanal (NOT-05).
        let monday = friday.addingTimeInterval(3 * 86_400)
        let mondayInput = SyntheticData.generate(days: 30, endingAt: monday, utcOffsetSeconds: 7200)
        let mondayOut = MetricsEngine.run(mondayInput)
        let weekly = NotificationPlanner.plan(output: mondayOut, newWatchWorkoutIDs: [], connection: ConnectionState(), settings: settings,
                                              sent: [:], now: monday, utcOffsetSeconds: 7200)
        #expect(weekly.contains { $0.id == "NOT-05" && $0.key == "NOT-05:2026-09-28" })
        #expect(!weekly.contains { $0.id == "NOT-11" })
    }

    @Test func noPlanNoReview() throws {
        let db = try AppDatabase.inMemory()
        let out = MetricsEngine.run(SyntheticData.generate(days: 20, endingAt: friday, utcOffsetSeconds: 7200))
        #expect(try db.weeklyPlanProgress(output: out, today: LocalDate(friday, utcOffsetSeconds: 7200)) == nil)
    }
}
