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

    /// Parciales, vueltas, pausas, dinámica de carrera, zonas y VO₂ máx. de una carrera de la Fitbit (doc. 18).
    @Test func fitbitRunDetails() throws {
        let json = """
        {"dataPoints":[{"name":"users/me/dataTypes/exercise/dataPoints/r1","dataSource":{"platform":"FITBIT"},
         "exercise":{"exerciseType":"RUNNING","displayName":"Carrera","activeDuration":"1500s",
          "interval":{"startTime":"2026-09-28T07:00:00Z","endTime":"2026-09-28T07:26:00Z","startUtcOffset":"7200s"},
          "metricsSummary":{"distanceMillimeters":5000000,"runVo2Max":51.2,"activeZoneMinutes":"31",
           "heartRateZoneDurations":{"moderateTime":"600s","vigorousTime":"840s","peakTime":"60s"},
           "mobilityMetrics":{"avgCadenceStepsPerMinute":172.5,"avgVerticalOscillationMillimeters":"84",
            "avgGroundContactTimeDuration":"0.245s","avgStrideLengthMillimeters":"1160","avgVerticalRatio":7.2}},
          "splits":[{"startTime":"2026-09-28T07:00:00Z","endTime":"2026-09-28T07:05:10Z","activeDuration":"310s","splitType":"DISTANCE",
                     "metricsSummary":{"distanceMillimeters":1000000,"averageHeartRateBeatsPerMinute":"148",
                                       "mobilityMetrics":{"avgCadenceStepsPerMinute":170}}}],
          "splitSummaries":[{"startTime":"2026-09-28T07:00:00Z","endTime":"2026-09-28T07:13:00Z","splitType":"MANUAL",
                             "metricsSummary":{"distanceMillimeters":2500000}}],
          "exerciseEvents":[{"eventTime":"2026-09-28T07:00:00Z","exerciseEventType":"START"},
                            {"eventTime":"2026-09-28T07:10:00Z","exerciseEventType":"AUTO_PAUSE"},
                            {"eventTime":"2026-09-28T07:11:40Z","exerciseEventType":"AUTO_RESUME"},
                            {"eventTime":"2026-09-28T07:26:00Z","exerciseEventType":"STOP"}]}}]}
        """
        let r = try JSONDecoder().decode(ListDataPointsResponse.self, from: Data(json.utf8))
        let d = try #require(GoogleMapping.activityDetails(r.dataPoints!).first)
        #expect(d.activityID == "google_health:users/me/dataTypes/exercise/dataPoints/r1")
        #expect(d.splits.count == 1 && d.splits[0].distanceM == 1000 && d.splits[0].avgHR == 148 && d.splits[0].avgCadence == 170)
        #expect(d.laps.count == 1 && d.laps[0].kind == "manual" && d.laps[0].distanceM == 2500)
        #expect(d.events.count == 1 && d.events[0].automatic && d.events[0].end.timeIntervalSince(d.events[0].start) == 100)
        #expect(d.activeSeconds == 1500 && d.activeZoneMinutes == 31 && d.vo2max == 51.2)
        #expect(d.zoneSeconds?["vigorous"] == 840 && d.zoneSeconds?["light"] == nil)
        #expect(d.mobility?.avgCadenceSpm == 172.5 && d.mobility?.avgStrideM == 1.16 && d.mobility?.avgVerticalOscillationCm == 8.4)
        #expect(d.mobility?.avgGroundContactMs == 245 && d.verticalRatioPct == 7.2)
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
        let today = LocalDate(friday, utcOffsetSeconds: 7200)
        // Un plan creado el mismo viernes no tiene revisión esa semana.
        try db.saveWeeklyPlan(WeeklyPlan(goals: WeeklyPlan.goals(for: .fitness), template: .fitness, createdAt: friday))
        #expect(try db.weeklyPlanProgress(output: out, today: today, utcOffsetSeconds: 7200) == nil)
        try db.saveWeeklyPlan(WeeklyPlan(goals: WeeklyPlan.goals(for: .fitness), template: .fitness,
                                         createdAt: friday.addingTimeInterval(-10 * 86_400)))
        let progress = try #require(try db.weeklyPlanProgress(output: out, today: today, utcOffsetSeconds: 7200))
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
        #expect(try db.weeklyPlanProgress(output: out, today: LocalDate(friday, utcOffsetSeconds: 7200), utcOffsetSeconds: 7200) == nil)
    }
}

/// Recoge los avisos de progreso de la importación.
actor ProgressLog {
    var items: [ImportProgress] = []
    func add(_ p: ImportProgress) { items.append(p) }
}

@Suite struct BackfillTests {
    @Test func firstImportGoesInPhasesWithMetricsAfterEach() async throws {
        let db = try AppDatabase.inMemory()
        let now = ISO8601DateFormatter().date(from: "2026-09-29T19:00:00Z")!
        let tokens = InMemoryTokenStore(TokenSet(accessToken: "a", refreshToken: "r", expiresAt: .distantFuture, scope: nil))
        let google = GoogleHealthClient(config: OAuthConfig(clientID: "c", reversedClientID: "r"), transport: CannedTransport([:]),
                                        tokens: tokens, sleep: { _ in })
        let engine = SyncEngine(db: db, google: google, apple: nil, now: { now }, utcOffset: { 7200 })
        let log = ProgressLog()
        let report = await engine.sync(.backfill, backfillDays: 45) { p in await log.add(p) }
        #expect(report.google.ok && !report.google.skipped)
        let phases = await log.items
        // Noches y vitales → últimos 14 días → el resto en tramos de 14 días (31 días: 3 tramos).
        #expect(phases.map(\.phase) == ["Tus noches y vitales", "Tus últimos 14 días", "El resto de tu historial",
                                         "El resto de tu historial", "El resto de tu historial"])
        #expect(phases.map(\.fraction) == phases.map(\.fraction).sorted())
        #expect(phases.last?.fraction == 1)
        #expect(phases[0].output != nil && phases[1].output != nil && phases.last?.output != nil)
        #expect(phases[2].output == nil)
        #expect(try db.connection().backfillCompleted)
        // Una sincronización normal no informa de fases.
        let quiet = ProgressLog()
        _ = await engine.sync(.pull) { p in await quiet.add(p) }
        #expect(await quiet.items.isEmpty)
    }

    /// Un "NaN" en la temperatura y un dato secundario que falla (aquí el SpO₂) no impiden guardar la VFC y la FC en
    /// reposo ni cerrar la primera importación; el fallo queda en el registro.
    @Test func secondaryDataCannotBlockTheImport() async throws {
        let db = try AppDatabase.inMemory()
        let now = ISO8601DateFormatter().date(from: "2026-09-29T19:00:00Z")!
        let day = #"{"year":2026,"month":9,"day":28}"#
        func point(_ field: String, _ value: String) -> String {
            #"{"dataPoints":[{"dataSource":{"platform":"FITBIT"},""# + field + #"":{"date":"# + day + "," + value + "}}]}"
        }
        let transport = CannedTransport([
            "daily-heart-rate-variability/dataPoints": point("dailyHeartRateVariability", #""averageHeartRateVariabilityMilliseconds":48.2"#),
            "daily-resting-heart-rate/dataPoints": point("dailyRestingHeartRate", #""beatsPerMinute":"52""#),
            "daily-sleep-temperature-derivations/dataPoints":
                point("dailySleepTemperatureDerivations", #""nightlyTemperatureCelsius":34.2,"baselineTemperatureCelsius":"NaN""#),
            "daily-oxygen-saturation/dataPoints": "[]",
        ])
        let tokens = InMemoryTokenStore(TokenSet(accessToken: "a", refreshToken: "r", expiresAt: .distantFuture, scope: nil))
        let google = GoogleHealthClient(config: OAuthConfig(clientID: "c", reversedClientID: "r"), transport: transport,
                                        tokens: tokens, sleep: { _ in })
        let engine = SyncEngine(db: db, google: google, apple: nil, now: { now }, utcOffset: { 7200 })
        let report = await engine.sync(.backfill, backfillDays: 20)
        #expect(report.google.ok && report.google.error == nil)
        #expect(try db.connection().backfillCompleted)
        let vitals = try db.metricsInput(now: now, utcOffsetSeconds: 7200).vitals
        let v = try #require(vitals.first { $0.date == LocalDate(year: 2026, month: 9, day: 28) })
        #expect(v.hrvRmssdAvg == 48.2 && v.restingHR == 52 && v.skinTempC == 34.2 && v.spo2Avg == nil)
        let log = try #require(try db.recentSyncLog().first { $0.source == "google_health" })
        #expect(log.status == "ok" && log.error?.contains("daily-oxygen-saturation") == true)
    }
}

/// Salud con años de entrenamientos: la importación del historial los pide por tramos hacia atrás.
actor HistoryCalls {
    var ranges: [(Date, Date)] = []
    func add(_ from: Date, _ to: Date) { ranges.append((from, to)) }
}

struct FakeHistoryWatch: AppleHealthProvider {
    let workouts: [ActivitySession]
    let calls: HistoryCalls
    var isAvailable: Bool { true }
    func requestAuthorization() async throws {}
    func importChanges(anchors: AnchorStore, backfillDays: Int) async throws -> AppleHealthImport { AppleHealthImport() }
    func importHistory(from: Date, to: Date) async throws -> AppleHealthImport {
        await calls.add(from, to)
        return AppleHealthImport(workouts: workouts.filter { $0.start >= from && $0.start < to })
    }
    func earliestSampleDate() async -> Date? { workouts.map(\.start).min() }
}

@Suite struct HistoryImportTests {
    let now = ISO8601DateFormatter().date(from: "2026-09-29T19:00:00Z")!

    func run(_ daysAgo: Double) -> ActivitySession {
        let start = now.addingTimeInterval(-daysAgo * 86_400)
        return ActivitySession(source: .appleHealth, sourceRecordID: "old-\(Int(daysAgo))", kind: .running, start: start,
                               end: start.addingTimeInterval(1800), utcOffsetSeconds: 7200, avgHR: 150, distanceM: 6000, hasRoute: false)
    }

    @Test func appleHistoryGoesBackInChunksToTheFirstWorkout() async throws {
        let db = try AppDatabase.inMemory()
        var settings = AppSettings()
        settings.healthKitEnabled = true
        try db.saveSettings(settings)
        try db.updateConnection { $0.healthKitConnectedAt = self.now }
        // Una carrera dentro de lo que ya cubrió la primera importación y tres del historial (hasta hace 3 años).
        let workouts = [run(30), run(200), run(400), run(1100)]
        let calls = HistoryCalls()
        let engine = SyncEngine(db: db, google: nil, apple: FakeHistoryWatch(workouts: workouts, calls: calls),
                                now: { now }, utcOffset: { 7200 })
        let state = await engine.importHistory()
        #expect(state.isComplete && state.appleDone && state.googleDailyDone && state.googleMinutesDone && state.metricsDone)
        #expect(state.workouts == 3 && state.finishedAt != nil)
        // Tramos contiguos de 120 días, del más reciente al más antiguo, sin huecos.
        let ranges = await calls.ranges
        #expect(ranges.first?.1 == now.addingTimeInterval(-175 * 86_400))
        for (a, b) in zip(ranges, ranges.dropFirst()) { #expect(b.1 == a.0) }
        #expect(ranges.last!.0 <= workouts.last!.start)
        #expect(try db.activityIDs(source: .appleHealth).count == 3)
        #expect(state.oldestData == workouts.last!.start)
        // Terminado: otra llamada no hace nada.
        #expect(await engine.importHistory().workouts == 3)
        #expect(await calls.ranges.count == ranges.count)
    }

    @Test func googleHistoryStopsAfterTwoEmptyYearsAndRespectsTheBudget() async throws {
        let db = try AppDatabase.inMemory()
        try db.updateConnection {
            $0.googleStatus = .active
            $0.connectedAt = self.now
            $0.backfillCompleted = true
        }
        let tokens = InMemoryTokenStore(TokenSet(accessToken: "a", refreshToken: "r", expiresAt: .distantFuture, scope: nil))
        let google = GoogleHealthClient(config: OAuthConfig(clientID: "c", reversedClientID: "r"), transport: CannedTransport([:]),
                                        tokens: tokens, sleep: { _ in })
        let engine = SyncEngine(db: db, google: google, apple: nil, now: { now }, utcOffset: { 7200 })
        // Sin tiempo: no avanza.
        let paused = await engine.importHistory(budget: 0)
        #expect(!paused.isComplete && paused.googleDailyUntil == nil)
        let log = HistoryProgress()
        let state = await engine.importHistory { s, _ in await log.add(s) }
        #expect(state.isComplete && state.googleEmptyChunks == SyncEngine.googleEmptyChunksToStop)
        #expect(state.googleDailyUntil == now.addingTimeInterval(-(175 + 8 * 90) * 86_400))
        let items = await log.items
        #expect(items.map(\.phase).first == .googleDaily && items.last?.isComplete == true)
        #expect(items.map(\.fraction) == items.map(\.fraction).sorted())
    }

    @Test func metricsOfThePastAreComputedInChunksWithoutTouchingRecentOnes() async throws {
        let db = try AppDatabase.inMemory()
        // Dos meses de datos de hace casi un año y los 30 últimos días.
        let old = SyntheticData.generate(days: 60, endingAt: now.addingTimeInterval(-300 * 86_400), utcOffsetSeconds: 7200)
        let recent = SyntheticData.generate(days: 30, endingAt: now, utcOffsetSeconds: 7200)
        try db.saveProfile(recent.profile)
        for input in [old, recent] {
            try db.upsertSleepSessions(input.sleepSessions)
            try db.mergeVitals(input.vitals)
            try db.upsertHRMinutes(input.hrFitbit)
            try db.upsertActivityMinutes(input.fitbitMinutes)
            try db.upsertActivities(input.activities)
        }
        let engine = SyncEngine(db: db, google: nil, apple: nil, now: { now }, utcOffset: { 7200 })
        let current = try await engine.recompute()
        let recentCount = try db.cycleHistory(before: now).count
        #expect(recentCount >= 28)
        let state = await engine.importHistory()
        #expect(state.isComplete && state.metricsDone)
        let history = try db.cycleHistory(before: now.addingTimeInterval(-195 * 86_400))
        #expect(history.count >= 55 && history.count <= 62)
        #expect(history.filter { $0.recovery.score != nil }.count >= 40 && history.contains { $0.strain.loadRaw > 0 })
        // Los ciclos recientes siguen ahí, sin cambios.
        #expect(try db.cycleHistory(before: now).count == recentCount + history.count)
        #expect(try db.cycleHistory(before: now, since: current.cycles.first!.cycle.start).count == current.cycles.filter { !$0.isOpen }.count)
        // Las carreras de hace un año están entre las actividades fusionadas guardadas.
        #expect(try db.oldestDataDate()! < now.addingTimeInterval(-350 * 86_400))
    }
}

actor HistoryProgress {
    var items: [HistoryImportState] = []
    func add(_ s: HistoryImportState) { items.append(s) }
}
