import Foundation
import Testing
@testable import MetricsKit
@testable import Store

@Suite struct StoreTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func settingsDefaultsAndMerge() throws {
        let db = try AppDatabase.inMemory()
        var s = try db.settings()
        #expect(s.coachModel["anthropic"] == "claude-opus-5-5")
        s.coachEnabled = true
        try db.saveSettings(s)
        #expect(try db.settings().coachEnabled)
        // Un JSON antiguo sin claves nuevas sigue decodificando con los valores por defecto.
        try db.writer.write { try $0.execute(sql: "UPDATE app_state SET json = '{\"coachEnabled\":true}' WHERE key = 'settings'") }
        let merged = try db.settings()
        #expect(merged.coachEnabled && merged.units == .metric && merged.coachDailyLimit == 20)
    }

    @Test func idempotentIngestion() throws {
        let db = try AppDatabase.inMemory()
        let mins = (0..<10).map { HRMinute(minute: 1_790_000_000 + $0 * 60, bpmAvg: 60, source: .googleHealth) }
        for _ in 0..<3 { try db.upsertHRMinutes(mins) }
        let count = try db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM hr_minute") }
        #expect(count == 10)
    }

    @Test func vitalsMergePartialFields() throws {
        let db = try AppDatabase.inMemory()
        let d = LocalDate(year: 2026, month: 9, day: 28)
        try db.mergeVitals([NightlyVitals(date: d, restingHR: 52)])
        try db.mergeVitals([NightlyVitals(date: d, hrvRmssdAvg: 48)])
        let input = try db.metricsInput(now: d.adding(days: 1).startDate(utcOffsetSeconds: 0), utcOffsetSeconds: 0)
        #expect(input.vitals.first?.restingHR == 52 && input.vitals.first?.hrvRmssdAvg == 48)
    }

    @Test func engineRoundTrip() throws {
        let db = try AppDatabase.inMemory()
        let synthetic = SyntheticData.generate(days: 25, endingAt: now, utcOffsetSeconds: 7200)
        try db.saveProfile(synthetic.profile)
        try db.upsertSleepSessions(synthetic.sleepSessions)
        try db.mergeVitals(synthetic.vitals)
        try db.upsertHRMinutes(synthetic.hrFitbit + synthetic.hrWatch)
        try db.upsertActivityMinutes(synthetic.fitbitMinutes)
        try db.upsertActivities(synthetic.activities)
        try db.upsertDailyTotals(synthetic.dailyFitbitTotals, source: .googleHealth)
        try db.upsertVO2(synthetic.vo2max)
        let input = try db.metricsInput(now: now, utcOffsetSeconds: 7200)
        #expect(input.sleepSessions.count == synthetic.sleepSessions.count)
        #expect(input.activities.count == synthetic.activities.count)
        let out = MetricsEngine.run(input)
        let direct = MetricsEngine.run(synthetic)
        #expect(out.cycles.map(\.recovery.score) == direct.cycles.map(\.recovery.score))
        try db.saveMetrics(out, computedAt: now)
        let cycles = try db.recentCycles(limit: 100)
        #expect(cycles.count == out.cycles.count)
        #expect(cycles.last == out.cycles.last)
        #expect(try db.engineSummary()?.algorithmVersion == "0.1.0")
        #expect(try db.activities().count == out.cycles.flatMap(\.activities).count)
    }

    @Test func annotationsSurviveResync() throws {
        let db = try AppDatabase.inMemory()
        let a = ActivitySession(source: .appleHealth, sourceRecordID: "W1", kind: .running, start: now.addingTimeInterval(-3600),
                                end: now.addingTimeInterval(-600), utcOffsetSeconds: 0)
        try db.upsertActivities([a])
        try db.saveAnnotation(ActivityAnnotation(activityID: a.id, rpe: 7, notes: "Series"))
        try db.upsertActivities([a])
        let input = try db.metricsInput(now: now, utcOffsetSeconds: 0)
        #expect(input.activities.first?.rpe == 7)
        #expect(input.activities.first?.notes == "Series")
    }

    @Test func coachThreadsAndUsage() throws {
        let db = try AppDatabase.inMemory()
        let t = CoachThread(title: "Hola", provider: "anthropic", model: "claude-opus-5-5")
        try db.saveThread(t)
        try db.appendMessage(CoachMessageRecord(threadID: t.id, role: "user", model: nil, contentJSON: "[]", displayText: "¿Qué tal?"))
        try db.appendMessage(CoachMessageRecord(threadID: t.id, role: "assistant", model: "claude-opus-5-5", contentJSON: "[]",
                                                displayText: "Bien", costUSD: 0.09))
        #expect(try db.messages(threadID: t.id).count == 2)
        let usage = try db.coachUsage(since: .distantPast)
        #expect(usage.questions == 1 && abs(usage.costUSD - 0.09) < 1e-9)
        try db.deleteThread(id: t.id)
        #expect(try db.threads().isEmpty)
    }

    @Test func wipeAllRemovesEverything() throws {
        let db = try AppDatabase.inMemory()
        try db.saveSettings(AppSettings())
        try db.upsertHRMinutes([HRMinute(minute: 60, bpmAvg: 60, source: .googleHealth)])
        try db.wipeAll()
        let n = try db.writer.read { try Int.fetchOne($0, sql: "SELECT (SELECT COUNT(*) FROM hr_minute) + (SELECT COUNT(*) FROM app_state)") }
        #expect(n == 0)
    }
}
