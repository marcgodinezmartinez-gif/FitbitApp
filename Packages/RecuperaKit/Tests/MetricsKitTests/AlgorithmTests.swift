import Foundation
import Testing
@testable import MetricsKit

@Suite struct StrainTests {
    let p = AlgorithmParams.default

    /// Anclaje del doc. 05: carrera de 45 min a 150 lpm (FCR 55, FCmáx 185, hombre) ⇒ TRIMP ≈ 85, carga ≈ 12,3.
    @Test func runAnchor() {
        let zones = StrainCalculator.zones(hrMax: 185, restingRef: 55)
        let run = minutes(from: utc("2026-09-01T18:00"), count: 45, bpm: 150, source: .googleHealth)
        let r = StrainCalculator.compute(minutes: run, zones: zones, sex: .male, params: p)
        #expect(abs(r.loadRaw - 85.6) < 1)
        #expect(r.strain == 12.3)
    }

    @Test func sedentaryDoesNotAccumulate() {
        let zones = StrainCalculator.zones(hrMax: 185, restingRef: 55)
        // 60 lpm ⇒ x ≈ 0,04 < 0,30 ⇒ sin carga.
        let r = StrainCalculator.compute(minutes: minutes(from: utc("2026-09-01T09:00"), count: 600, bpm: 60, source: .googleHealth),
                                         zones: zones, sex: .male, params: p)
        #expect(r.strain == 0)
    }

    @Test func strainIsBoundedAndMonotonic() {
        let zones = StrainCalculator.zones(hrMax: 185, restingRef: 55)
        var last = 0.0
        for n in stride(from: 0, through: 600, by: 60) {
            let r = StrainCalculator.compute(minutes: minutes(from: utc("2026-09-01T08:00"), count: n, bpm: 170, source: .googleHealth),
                                             zones: zones, sex: .male, params: p)
            #expect(r.strain >= last && r.strain <= 21)
            last = r.strain
        }
    }

    @Test func targetBand() {
        let band = StrainCalculator.target(recovery: 90, recentStrains: Array(repeating: 11, count: 28), mode: .maintain, params: p)!
        #expect(band.low == 11.9 && band.high == 14.9)
        let low = StrainCalculator.target(recovery: 20, recentStrains: Array(repeating: 11, count: 28), mode: .maintain, params: p)!
        #expect(low.low == 7.7 && low.high == 10.7)
    }
}

@Suite struct RecoveryTests {
    let p = AlgorithmParams.default

    func nights(_ n: Int, rmssd: Double = 50, rhr: Double = 55) -> [NightValues] {
        let start = LocalDate(year: 2026, month: 8, day: 1)
        return (0..<n).map { i in
            let wiggle = Double(i % 5) - 2
            return NightValues(date: start.adding(days: i), lnRmssd: log(rmssd + wiggle), restingHR: rhr + wiggle * 0.5,
                               respiratoryRate: 14, skinTemp: 34, spo2: 96, valid: true)
        }
    }

    @Test func calibratingUntilFourNights() {
        let input = RecoveryInput(date: LocalDate(year: 2026, month: 8, day: 4), rmssd: 50, restingHR: 55, sleepSufficiency: 90,
                                  respiratoryRate: 14, skinTemp: 34, spo2: 96, nightCoverage: 0.9, minutesAsleep: 450)
        let r = RecoveryCalculator.compute(input, nights: nights(3), history: [], params: p)
        #expect(r.score == nil)
        #expect(r.status == .calibrating(nights: 3, needed: 4))
    }

    @Test func normalDayIsAroundFiftySeven() {
        let hist = nights(20)
        let med = exp(Stats.median(hist.compactMap(\.lnRmssd))!)
        let rhrMed = Stats.median(hist.compactMap(\.restingHR))!
        let input = RecoveryInput(date: LocalDate(year: 2026, month: 8, day: 21), rmssd: med, restingHR: rhrMed, sleepSufficiency: 85,
                                  respiratoryRate: 14, skinTemp: 34, spo2: 96, nightCoverage: 0.9, minutesAsleep: 450)
        let r = RecoveryCalculator.compute(input, nights: hist, history: [], params: p)
        #expect(r.score == 57)
        #expect(r.zone == .medium)
        #expect(r.confidence == .high)
    }

    @Test func monotonicInHRV() {
        let hist = nights(20)
        var last = -1
        for rmssd in stride(from: 30.0, through: 80, by: 5) {
            let input = RecoveryInput(date: LocalDate(year: 2026, month: 8, day: 21), rmssd: rmssd, restingHR: 55, sleepSufficiency: 85,
                                      respiratoryRate: 14, skinTemp: 34, spo2: 96, nightCoverage: 0.9, minutesAsleep: 450)
            let s = RecoveryCalculator.compute(input, nights: hist, history: [], params: p).score!
            #expect(s >= last && (0...100).contains(s))
            last = s
        }
    }

    @Test func noHRVMeansNoScore() {
        let input = RecoveryInput(date: LocalDate(year: 2026, month: 8, day: 21), rmssd: nil, restingHR: 55, sleepSufficiency: 85,
                                  respiratoryRate: 14, skinTemp: 34, spo2: 96, nightCoverage: 0.9, minutesAsleep: 450)
        #expect(RecoveryCalculator.compute(input, nights: nights(20), history: [], params: p).score == nil)
    }
}

@Suite struct SleepTests {
    let p = AlgorithmParams.default

    @Test func sufficiencyAndDebt() {
        #expect(SleepCalculator.sufficiency(asleep: 420, need: 480) == 87.5)
        #expect(SleepCalculator.sufficiency(asleep: 600, need: 480) == 100)
        let d = SleepCalculator.debt(previous: 100, needWithoutDebt: 480, asleep: 420, params: p)
        #expect(abs(d - (0.85 * 100 + 60)) < 1e-9)
        #expect(SleepCalculator.debt(previous: 0, needWithoutDebt: 480, asleep: 600, params: p) == 0)
    }

    @Test func plannerMatchesAcceptanceCriterion() {
        // Necesidad 8 h 20 min, eficiencia 90 %, despertar 07:00, objetivo 100 %, latencia 15 min.
        let bed = SleepCalculator.bedtime(wakeMinutes: 7 * 60, needMin: 500, goal: .peak, usualEfficiency: 90, usualLatency: 15, params: p)
        #expect(bed == Int(((420.0 - 500 / 0.9 - 15) / 5).rounded()) * 5)
    }

    @Test func perfectRegularityGivesSRI100() {
        var asleep = Set<Int>()
        var days: [LocalDate] = []
        for d in 0..<7 {
            let day = LocalDate(year: 2026, month: 9, day: 1 + d)
            days.append(day)
            let midnight = day.startDate(utcOffsetSeconds: 0)
            for m in 0..<(7 * 60) { asleep.insert(Int(midnight.timeIntervalSince1970) + m * 60) }
        }
        let sri = SleepCalculator.sri(asleepMinutes: asleep, coveredDays: days, until: LocalDate(year: 2026, month: 9, day: 7), utcOffset: 0)
        #expect(sri == 100)
    }
}

@Suite struct HabitTests {
    @Test func detectsNegativeEffect() {
        var days: [HabitDay] = []
        for i in 0..<40 {
            let habit = i % 3 == 0
            days.append(HabitDay(date: LocalDate(year: 2026, month: 7, day: 1).adding(days: i), habit: habit,
                                 strain: Double(10 + i % 4), nextDayRecovery: (habit ? 50 : 65) + Double(i % 5)))
        }
        let r = HabitImpactCalculator.impact(questionKey: "alcohol", days: days, resamples: 300)
        #expect(r.status == .effect)
        #expect((r.effect ?? 0) < -10)
    }

    @Test func needsFiveOfEach() {
        let days = (0..<8).map { HabitDay(date: LocalDate(year: 2026, month: 7, day: 1 + $0), habit: $0 < 3, strain: 10, nextDayRecovery: 60) }
        #expect(HabitImpactCalculator.impact(questionKey: "x", days: days).status == .needMoreData)
    }
}
