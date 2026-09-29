import Foundation
import Testing
@testable import Insights
@testable import MetricsKit

private func utcDate(_ s: String) -> Date { ISO8601DateFormatter().date(from: s + ":00Z")! }

@Suite struct DashboardTests {
    @Test func dashboardListIsSanitized() {
        #expect(DayMetric.dashboard(["hrv", "iq", "hrv", "steps"]) == [.hrv, .steps])
        #expect(DayMetric.dashboard([]) == [])
    }

    @Test func summaryHasLatestUsualAndLastWeek() {
        let now = utcDate("2026-09-29T21:00")
        let input = SyntheticData.generate(days: 60, endingAt: now)
        let out = MetricsEngine.run(input)
        let today = out.current!.date
        let s = MetricSummary.build(.hrv, cycles: out.cycles, until: today)
        #expect(s.last7.count == 7)
        #expect(s.latest != nil && s.usual != nil)
        #expect(s.delta == s.latest! - s.usual!)
        #expect(MetricSummary.build(.rhr, cycles: out.cycles, until: today).metric.higherIsBetter == false)
        // Los pasos de hoy (día en curso) no se comparan con días completos.
        let steps = MetricSummary.build(.steps, cycles: out.cycles, until: today)
        #expect(steps.inProgress && steps.delta == nil && steps.latest != nil)
        let yesterday = MetricSummary.build(.steps, cycles: out.cycles, until: today.adding(days: -1))
        #expect(!yesterday.inProgress && yesterday.delta != nil)
        for m in DayMetric.allCases {
            let v = MetricSummary.build(m, cycles: out.cycles, until: today).latest
            if let v { #expect(!m.formatted(v).isEmpty) }
        }
    }
}

@Suite struct WeeklyPlanTests {
    let now = utcDate("2026-09-29T21:00")   // martes

    @Test func templatesAndTitles() {
        #expect(WeeklyPlan.goals(for: .custom).isEmpty)
        for t in WeeklyPlan.Template.allCases where t != .custom {
            #expect(!WeeklyPlan.goals(for: t).isEmpty)
        }
        #expect(WeeklyPlan.Goal(kind: .sleepNights, target: 5, threshold: 7).title() == "Dormir 7 h o más · 5 noches")
        #expect(WeeklyPlan.Goal(kind: .sleepNights, target: 5, threshold: 7.5).title() == "Dormir 7,5 h o más · 5 noches")
        #expect(WeeklyPlan.Goal(kind: .habitDays, target: 5, habitKey: "alcohol", habitDesired: false).title() == "Sin alcohol · 5 días")
        #expect(WeeklyPlan.Goal(kind: .stepDays).title() == "8000 pasos · 5 días")
        #expect(WeeklyPlanner.weekStart(of: LocalDate(year: 2026, month: 9, day: 29)) == LocalDate(year: 2026, month: 9, day: 28))
        #expect(WeeklyPlanner.weekStart(of: LocalDate(year: 2026, month: 10, day: 4)) == LocalDate(year: 2026, month: 9, day: 28))
    }

    @Test func progressCountsTheWeekOnly() {
        let input = SyntheticData.generate(days: 40, endingAt: now)
        let out = MetricsEngine.run(input)
        let today = out.current!.date
        let monday = WeeklyPlanner.weekStart(of: today)
        let plan = WeeklyPlan(goals: [
            WeeklyPlan.Goal(id: "sleep", kind: .sleepNights, target: 7, threshold: 0),
            WeeklyPlan.Goal(id: "habit", kind: .habitDays, target: 2, habitKey: "alcohol", habitDesired: false),
            WeeklyPlan.Goal(id: "zones", kind: .moderateZoneMinutes, target: 100_000),
        ], template: .custom)
        let journal = [JournalAnswer(date: monday, questionKey: "alcohol", yes: false),
                       JournalAnswer(date: monday.adding(days: 1), questionKey: "alcohol", yes: true),
                       JournalAnswer(date: monday.adding(days: -1), questionKey: "alcohol", yes: false)]
        let p = WeeklyPlanner.progress(plan: plan, cycles: out.cycles, journal: journal, weekStart: monday, today: today)
        let nights = out.cycles.filter { $0.date >= monday && $0.date <= today && $0.sleep != nil }.count
        #expect(p.items[0].current == Double(nights))
        #expect(p.items[1].current == 1)             // solo el lunes (el domingo es de la semana anterior)
        #expect(p.items[1].fraction == 0.5)
        #expect(p.items[2].fraction < 0.1)
        #expect(abs(p.overall - p.items.map(\.fraction).reduce(0, +) / 3) < 1e-9)
        #expect(p.daysElapsed == today.days(since: monday) + 1)
        #expect(p.mostBehind?.id == "zones")
        #expect(WeeklyPlanner.fridayReview(p).hasPrefix("Vas al \(p.percent) %"))
        #expect(WeeklyPlanner.isAvailable(cycles: out.cycles))
        #expect(!WeeklyPlanner.isAvailable(cycles: Array(out.cycles.prefix(3))))
    }

    @Test func completedPlanSaysSo() {
        let goal = WeeklyPlan.Goal(id: "g", kind: .habitDays, target: 1, habitKey: "meditation", habitDesired: true)
        let monday = LocalDate(year: 2026, month: 9, day: 28)
        let p = WeeklyPlanner.progress(plan: WeeklyPlan(goals: [goal]), cycles: [],
                                       journal: [JournalAnswer(date: monday, questionKey: "meditation", yes: true)],
                                       weekStart: monday, today: monday.adding(days: 4))
        #expect(p.overall == 1)
        #expect(WeeklyPlanner.fridayReview(p) == "¡Plan semanal cumplido! Vas al 100 %.")
    }
}

@Suite struct StrengthInsightTests {
    @Test func summaryGroupsExercises() {
        let sets = [StrengthSet(exercise: "Sentadilla", reps: 5, weightKg: 100), StrengthSet(exercise: "sentadilla ", reps: 5, weightKg: 105),
                    StrengthSet(exercise: "Dominadas", reps: 8), StrengthSet(exercise: "Press de banca", reps: 0, weightKg: 60)]
        let s = StrengthSummary.of(sets)
        #expect(s.exercises.map(\.exercise) == ["Sentadilla", "Dominadas"])
        #expect(s.totalSets == 3 && s.totalReps == 18)
        #expect(s.volumeKg == 1025)
        #expect(s.exercises[0].topWeightKg == 105)
        let load = StrengthSummary.muscularLoad(rpe: 7, minutes: 60)!
        #expect(load.srpe == 420)
        #expect(load.strain > 0 && load.strain < 21)
        #expect(StrengthSummary.muscularLoad(rpe: nil, minutes: 60) == nil)
    }

    @Test func recordsNeedAPreviousBest() {
        let before = StrengthRecords.bestOneRepMax([[StrengthSet(exercise: "Peso muerto", reps: 5, weightKg: 120)]])
        let today = [StrengthSet(exercise: "peso muerto", reps: 5, weightKg: 125), StrengthSet(exercise: "Hip thrust", reps: 8, weightKg: 100)]
        #expect(StrengthRecords.newRecords(session: today, previousBest: before) == ["peso muerto"])
        #expect(StrengthCatalog.normalized("  Press  Militar ") == "press militar")
    }
}

@Suite struct BreathingTests {
    @Test func slowBreathingIsSixPerMinute() {
        let p = BreathingPattern.slow
        #expect(p.breathsPerMinute == 6)
        #expect(p.state(at: 0).index == 0)
        #expect(p.state(at: 5).index == 1)
        #expect(abs(p.state(at: 5).progress - 1.0 / 6) < 1e-9)
        #expect(p.state(at: 21).cycle == 2)
        #expect(abs(p.scale(at: 4) - 1) < 1e-9)
        #expect(abs(p.scale(at: 0)) < 1e-9)
        #expect(p.cycles(inMinutes: 3) == 18)
    }

    @Test func cyclicSighHasTwoInhales() {
        let p = BreathingPattern.cyclicSigh
        #expect(p.phases.map(\.kind) == [.inhale, .topUp, .exhale])
        #expect(p.breathsPerMinute == 6)
        #expect(p.scale(at: 2.5) > 0.79 && p.scale(at: 2.5) < 0.81)
    }
}
