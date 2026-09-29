import Foundation
import Testing
@testable import MetricsKit

@Suite struct NonExerciseVO2Tests {
    /// Ecuaciones de Nes et al. (2011) con el índice de actividad = frecuencia × intensidad × duración.
    @Test func huntEquations() throws {
        let q = ActivityQuestionnaire(frequency: .almostDaily, intensity: .breathless, duration: .from30to60)
        #expect(q.index == 7.5)
        // 100,27 − 0,296·40 − 0,369·85 − 0,155·60 + 0,226·7,5 = 49,46
        #expect(NonExerciseVO2.estimate(age: 40, sex: .male, waistCm: 85, restingHR: 60, activityIndex: q.index) == 49.5)
        let w = ActivityQuestionnaire(frequency: .twoToThreeWeekly, intensity: .breathless, duration: .from30to60)
        #expect(w.index == 3.75)
        // 74,74 − 0,247·35 − 0,259·75 − 0,114·65 + 0,198·3,75 = 40,0025
        #expect(NonExerciseVO2.estimate(age: 35, sex: .female, waistCm: 75, restingHR: 65, activityIndex: w.index) == 40.0)
    }

    @Test func indexRangeAndLimits() {
        #expect(ActivityQuestionnaire(frequency: .almostDaily, intensity: .nearExhaustion, duration: .over60).index == 15)
        #expect(ActivityQuestionnaire(frequency: .lessThanWeekly, intensity: .nearExhaustion, duration: .over60).index == 0)
        #expect(NonExerciseVO2.estimate(age: 40, sex: .unspecified, waistCm: 85, restingHR: 60, activityIndex: 5) == nil)
        #expect(NonExerciseVO2.estimate(age: 15, sex: .male, waistCm: 70, restingHR: 60, activityIndex: 5) == nil)
        #expect(NonExerciseVO2.estimate(age: 40, sex: .male, waistCm: 20, restingHR: 60, activityIndex: 5) == nil)
        // Más actividad y menos cintura ⇒ más VO₂ máx.
        let a = NonExerciseVO2.estimate(age: 40, sex: .male, waistCm: 90, restingHR: 60, activityIndex: 2)!
        let b = NonExerciseVO2.estimate(age: 40, sex: .male, waistCm: 80, restingHR: 60, activityIndex: 10)!
        #expect(b > a)
        #expect(NonExerciseVO2.missingInputs(profile: UserProfile()) == ["fecha de nacimiento", "sexo", "perímetro de cintura",
                                                                         "cuestionario de actividad"])
    }

    @Test func engineUsesEstimateOnlyWithoutMeasuredVO2() {
        let now = utc("2026-09-29T21:00")
        var input = SyntheticData.generate(days: 60, endingAt: now)
        input.profile.waistCm = 82
        input.profile.activityQuestionnaire = ActivityQuestionnaire(frequency: .twoToThreeWeekly, intensity: .breathless, duration: .from30to60)

        // Con VO₂ máx. del Apple Watch no se estima.
        let measured = MetricsEngine.run(input)
        #expect(measured.estimatedVO2 == nil)
        #expect(measured.physioAge?.fitnessEstimated == nil)

        input.vo2max = []
        let out = MetricsEngine.run(input)
        let est = try? #require(out.estimatedVO2)
        #expect((est ?? 0) > 35 && (est ?? 0) < 60)
        #expect(out.primaryVO2 == nil)
        #expect(out.physioAge?.fitnessEstimated == true)
        #expect(out.physioAge?.omittedFitness == false)
        #expect(out.physioAge?.factors.contains { $0.key == "vo2max" && $0.label.contains("estimada") } == true)

        // Sin cuestionario se omite el factor y se indica.
        input.profile.activityQuestionnaire = nil
        let none = MetricsEngine.run(input)
        #expect(none.estimatedVO2 == nil)
        #expect(none.physioAge?.omittedFitness == true)
    }
}

@Suite struct SmartAlarmTests {
    let p = AlgorithmParams.default
    let bed = utc("2026-09-29T21:00")          // 23:00 en UTC+2
    let start = utc("2026-09-30T04:30")        // 06:30
    let end = utc("2026-09-30T05:15")          // 07:15

    @Test func ringsWhenNeedIsMetInsideWindow() {
        // 23:00 + 15 min + 420/0,9 min = 07:01:40 ⇒ suena a las 07:01.
        let plan = SleepCalculator.smartAlarm(bedtime: bed, needMin: 420, goal: .peak, usualEfficiency: 90, usualLatency: 15,
                                              windowStart: start, windowEnd: end, params: p)
        #expect(plan.needMet)
        #expect(plan.alarm == utc("2026-09-30T05:01"))
    }

    @Test func clampsToWindow() {
        let early = SleepCalculator.smartAlarm(bedtime: bed, needMin: 360, goal: .peak, usualEfficiency: 90, usualLatency: 15,
                                               windowStart: start, windowEnd: end, params: p)
        #expect(early.alarm == start && early.needMet)
        let late = SleepCalculator.smartAlarm(bedtime: bed, needMin: 480, goal: .peak, usualEfficiency: 90, usualLatency: 15,
                                              windowStart: start, windowEnd: end, params: p)
        #expect(late.alarm == end && !late.needMet)
        // Con el objetivo «Rendir (85 %)» basta con menos.
        let perform = SleepCalculator.smartAlarm(bedtime: bed, needMin: 480, goal: .perform, usualEfficiency: 90, usualLatency: 15,
                                                 windowStart: start, windowEnd: end, params: p)
        #expect(perform.needMet && perform.alarm < end)
    }
}

@Suite struct StrengthSetTests {
    @Test func volumeAndEpley() {
        let s = StrengthSet(exercise: "Sentadilla", reps: 5, weightKg: 100)
        #expect(s.volumeKg == 500)
        #expect(abs((s.estimatedOneRepMax ?? 0) - 116.67) < 0.01)
        #expect(StrengthSet(exercise: "Dominadas", reps: 8).volumeKg == 0)
        #expect(StrengthSet(exercise: "Dominadas", reps: 8).estimatedOneRepMax == nil)
        #expect(StrengthSet(exercise: "Press", reps: 1, weightKg: 80).estimatedOneRepMax == 80)
        #expect(StrengthSet(exercise: "Press", reps: 20, weightKg: 40).estimatedOneRepMax == nil)
    }
}
