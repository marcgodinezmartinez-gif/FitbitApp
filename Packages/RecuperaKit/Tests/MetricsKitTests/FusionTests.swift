import Foundation
import Testing
@testable import MetricsKit

@Suite struct FusionTests {
    let p = AlgorithmParams.default

    /// Ejemplo del doc. 16 §5: carrera con los dos y paseo de vuelta detectado por la Fitbit.
    @Test func runAndWalkExample() {
        let acts = [
            session("W1", "2026-09-01T18:00", "2026-09-01T18:45", source: .appleHealth, distance: 8200, hasRoute: true),
            session("F1", "2026-09-01T18:02", "2026-09-01T18:44", source: .googleHealth),
            session("F2", "2026-09-01T18:44", "2026-09-01T19:05", source: .googleHealth, kind: .walking),
        ]
        let fused = Fusion.fuseActivities(acts, params: p)
        #expect(fused.count == 2)
        #expect(fused[0].id == "apple_health:W1")
        #expect(fused[0].sources == [.appleHealth, .googleHealth])
        #expect(fused[0].start == utc("2026-09-01T18:00") && fused[0].end == utc("2026-09-01T18:45"))
        #expect(fused[1].kind == .walking && fused[1].sources == [.googleHealth])
    }

    @Test func leftoverPiecesOverTenMinutesStay() {
        let acts = [
            session("W1", "2026-09-01T18:00", "2026-09-01T18:45", source: .appleHealth),
            session("F1", "2026-09-01T17:50", "2026-09-01T18:50", source: .googleHealth),
        ]
        let fused = Fusion.fuseActivities(acts, params: p)
        #expect(fused.count == 2)
        #expect(fused.contains { $0.isLeftover && $0.durationMinutes == 10 })
    }

    @Test func splitFitbitRunMergesIntoOne() {
        let acts = [
            session("W1", "2026-09-01T07:00", "2026-09-01T08:00", source: .appleHealth),
            session("F1", "2026-09-01T07:01", "2026-09-01T07:28", source: .googleHealth),
            session("F2", "2026-09-01T07:31", "2026-09-01T07:59", source: .googleHealth),
        ]
        let fused = Fusion.fuseActivities(acts, params: p)
        #expect(fused.count == 1)
        #expect(fused[0].members.count == 3)
    }

    @Test func heartRatePriorities() {
        let run = TimeRange(start: utc("2026-09-01T18:00"), end: utc("2026-09-01T18:10"))
        let fitbit = minutes(from: utc("2026-09-01T17:55"), count: 20, bpm: 140, source: .googleHealth)
        let watch = minutes(from: utc("2026-09-01T18:00"), count: 10, bpm: 150, source: .appleHealth, samples: 12)
            + [HRMinute(minute: utc("2026-09-01T19:00").minuteEpoch, bpmAvg: 90, samples: 1, source: .appleHealth)]
        let fused = Dictionary(Fusion.fuseHeartRate(fitbit: fitbit, watch: watch, watchWorkouts: [run], params: p).map { ($0.minute, $0) },
                               uniquingKeysWith: { a, _ in a })
        #expect(fused[utc("2026-09-01T18:05").minuteEpoch]?.source == .appleHealth)
        #expect(fused[utc("2026-09-01T17:58").minuteEpoch]?.source == .googleHealth)
        #expect(fused[utc("2026-09-01T18:12").minuteEpoch]?.source == .googleHealth)
        // Hueco de la pulsera: lo rellena el Watch.
        #expect(fused[utc("2026-09-01T19:00").minuteEpoch]?.source == .appleHealth)
        // Nunca dos fuentes en el mismo minuto.
        #expect(Set(fused.keys).count == fused.count)
    }

    @Test func fewWatchSamplesFallBackToFitbit() {
        let run = TimeRange(start: utc("2026-09-01T18:00"), end: utc("2026-09-01T18:10"))
        let fitbit = minutes(from: utc("2026-09-01T18:00"), count: 10, bpm: 140, source: .googleHealth)
        let watch = minutes(from: utc("2026-09-01T18:00"), count: 10, bpm: 150, source: .appleHealth, samples: 1)
        let fused = Fusion.fuseHeartRate(fitbit: fitbit, watch: watch, watchWorkouts: [run], params: p)
        #expect(fused.allSatisfy { $0.source == .googleHealth })
    }

    @Test func agreementAndDisagreement() {
        let range = TimeRange(start: utc("2026-09-01T18:00"), end: utc("2026-09-01T18:30"))
        var f: [Int: Double] = [:], w: [Int: Double] = [:]
        for i in 0..<30 {
            let m = utc("2026-09-01T18:00").minuteEpoch + i * 60
            f[m] = 150
            w[m] = 152 + Double(i % 2)
        }
        let a = Fusion.agreement(fitbit: f, watch: w, range: range)!
        #expect(a.bias == 2.5 && a.minutes == 30)
        #expect(!Fusion.sourcesDisagree(fitbit: f, watch: w, range: range, params: p))
        for i in 10..<16 { w[utc("2026-09-01T18:00").minuteEpoch + i * 60] = 175 }
        #expect(Fusion.sourcesDisagree(fitbit: f, watch: w, range: range, params: p))
    }

    @Test func dailyDistanceUsesWatchGPS() {
        let w = session("W1", "2026-09-01T18:00", "2026-09-01T18:10", source: .appleHealth, distance: 2000, hasRoute: true)
        let f = session("F1", "2026-09-01T18:00", "2026-09-01T18:10", source: .googleHealth)
        let fused = Fusion.fuseActivities([w, f], params: p)
        var mins: [Int: ActivityMinute] = [:]
        var hr: [Int: Double] = [:]
        for i in 0..<10 {
            let m = utc("2026-09-01T18:00").minuteEpoch + i * 60
            mins[m] = ActivityMinute(minute: m, steps: 170, distanceM: 150, source: .googleHealth)
            hr[m] = 150
        }
        let t = Fusion.dailyTotals(date: LocalDate(year: 2026, month: 9, day: 1), fitbitSteps: 9000, fitbitDistanceM: 7000,
                                   fitbitCaloriesKcal: 2400, fitbitMinutes: mins, fitbitHR: hr, activities: fused, params: p)
        #expect(t.distanceM == 7000 - 1500 + 2000)
        #expect(t.steps == 9000)
    }

    @Test func dailyTotalsFillGapsWhenBandNotWorn() {
        var w = session("W1", "2026-09-01T18:00", "2026-09-01T18:30", source: .appleHealth, distance: 5000, hasRoute: true, steps: 5000)
        w.caloriesKcal = 350
        let fused = Fusion.fuseActivities([w], params: p)
        let t = Fusion.dailyTotals(date: LocalDate(year: 2026, month: 9, day: 1), fitbitSteps: 4000, fitbitDistanceM: 3000,
                                   fitbitCaloriesKcal: 2000, fitbitMinutes: [:], fitbitHR: [:], activities: fused, params: p)
        #expect(t.steps == 9000 && t.distanceM == 8000 && t.caloriesKcal == 2350)
    }

    @Test func healthKitOrigin() {
        #expect(Fusion.acceptsHealthKitSample(bundleIdentifier: "com.apple.health.1234", productType: "Watch7,1"))
        #expect(!Fusion.acceptsHealthKitSample(bundleIdentifier: "com.google.fitbit", productType: "iPhone17,1"))
        #expect(!Fusion.acceptsHealthKitSample(bundleIdentifier: "com.apple.Health", productType: "iPhone17,1"))
        #expect(!Fusion.acceptsGooglePlatform("HEALTH_KIT"))
        #expect(Fusion.acceptsGooglePlatform("FITBIT"))
    }

    @Test func vo2Priority() {
        let today = LocalDate(year: 2026, month: 9, day: 29)
        let values = [VO2MaxValue(date: today.adding(days: -10), value: 48, source: .appleHealth),
                      VO2MaxValue(date: today.adding(days: -2), value: 45, source: .googleHealth)]
        #expect(Fusion.primaryVO2(values, today: today, params: p)?.source == .appleHealth)
        let old = [VO2MaxValue(date: today.adding(days: -90), value: 48, source: .appleHealth),
                   VO2MaxValue(date: today.adding(days: -2), value: 45, source: .googleHealth)]
        #expect(Fusion.primaryVO2(old, today: today, params: p)?.source == .googleHealth)
    }
}
