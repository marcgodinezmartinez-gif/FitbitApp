import Foundation
import Testing
@testable import RunKit
@testable import MetricsKit

@Suite struct PlanTests {
    let today = LocalDate(year: 2026, month: 9, day: 30)   // miércoles

    func history(weeklyKm: Double, longestKm: Double) -> RunHistory {
        var runs: [RunSummary] = []
        for w in 0..<6 {
            for (k, km) in [weeklyKm - longestKm - 8, 8.0, longestKm].enumerated() where km > 0 {
                let date = today.adding(days: -7 * w - 2 * k - 1)
                runs.append(RunSummary(id: "r\(w)-\(k)", start: date.startDate(utcOffsetSeconds: 0).addingTimeInterval(8 * 3600),
                                       utcOffsetSeconds: 0, kind: .running, name: "Carrera", distanceM: km * 1000, movingS: km * 330,
                                       elapsedS: km * 330, bestEfforts: [:], paceCurve: [], powerCurve: [], sources: [.appleHealth],
                                       signature: ""))
            }
        }
        return RunHistory(summaries: runs)
    }

    @Test func workoutsUseTheVDOTPacesAndEstimateTimeAndDistance() {
        let p = PaceSet(vdot: 50)
        #expect(p.repetition < p.interval && p.interval < p.threshold && p.threshold < p.marathon && p.marathon < p.easyFast)
        #expect(abs(p.threshold - 255) < 3 && abs(p.interval - 235) < 3)
        let w = WorkoutLibrary.intervals(reps: 5, meters: 1000, p)
        #expect(w.title == "5 × 1 km a ritmo I" && w.blocks.first?.iterations == 5)
        #expect(w.blocks[0].steps[0].target.paceFast == p.interval - 5 && w.warmup != nil && w.cooldown != nil)
        // 2 km + 5 × (1 km + trote de lo que dura la serie) + 1,5 km.
        let expected = 2000 + 5 * (1000 + (p.interval.rounded() / p.jog * 1000)) + 1500
        #expect(abs(w.estimatedMeters - expected) < 1)
        #expect(abs(WorkoutLibrary.easy(meters: 8000, p).estimatedSeconds - 8 * p.easy) < 0.001)
        #expect(WorkoutLibrary.templates(vdot: 50).count >= 12)
    }

    @Test func tenKPlanRampsUpSafelyAndEndsWithTheRace() throws {
        let race = GoalRace(name: "10K de Valencia", date: ISO8601DateFormatter().date(from: "2026-12-20T08:00:00Z")!, distanceM: 10_000)
        let plan = PlanBuilder.build(goal: race, vdot: 45, history: history(weeklyKm: 28, longestKm: 10), today: today,
                                     utcOffsetSeconds: 0, daysPerWeek: 4, longRunWeekday: 7)
        #expect(plan.weeks.count == 12)
        #expect(plan.weeks.first?.start == LocalDate(year: 2026, month: 9, day: 28))
        // Arranca de tus 28 km de las semanas completas (no de la de hoy, que va a medias) y sube un 5 %.
        #expect(abs((plan.weeks.first?.targetKm ?? 0) - 28 * 1.05) < 0.5)
        #expect(plan.weeks.map(\.phase).first == .base && plan.weeks.last?.phase == .race && plan.weeks[plan.weeks.count - 2].phase == .taper)
        let phases = plan.weeks.map(\.phase)
        let order: [PlanPhase] = [.base, .build, .peak, .taper, .race]
        #expect(phases == phases.sorted { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! })
        // Nada antes de hoy; la carrera, el día de la carrera; como mucho 4 sesiones por semana.
        #expect(plan.sessions.allSatisfy { $0.date >= today })
        #expect(plan.sessions.last?.workout.kind == .race && plan.sessions.last?.date == LocalDate(year: 2026, month: 12, day: 20))
        #expect(plan.weeks.allSatisfy { $0.sessions.count <= 4 })
        // La tirada larga nunca sube más de un 10 % sobre la más larga anterior (10 km al empezar).
        var longest = 10.0
        for s in plan.sessions where s.workout.kind == .long {
            let km = s.workout.estimatedMeters / 1000
            #expect(km <= longest * 1.1 + 0.5)
            longest = max(longest, km)
        }
        #expect(longest <= 18)
        // Los rodajes de cada semana, más cortos que su tirada larga.
        for week in plan.weeks {
            guard let long = week.sessions.first(where: { $0.workout.kind == .long }) else { continue }
            #expect(week.sessions.filter { $0.workout.kind == .easy }.allSatisfy { $0.workout.estimatedMeters < long.workout.estimatedMeters })
        }
        // Semanas de descarga y volumen punta razonable.
        #expect(plan.weeks.contains { $0.isCutback })
        #expect((plan.weeks.map(\.targetKm).max() ?? 0) <= 28 * 1.8 && (plan.weeks.map(\.targetKm).max() ?? 0) >= 32)
        // Calidad con calentamiento y ritmos del VDOT.
        let quality = plan.sessions.filter { $0.workout.kind.isQuality && $0.workout.kind != .race }
        #expect(!quality.isEmpty && quality.allSatisfy { $0.workout.warmup != nil })
        #expect(plan.week(containing: LocalDate(year: 2026, month: 12, day: 17))?.phase == .race)
    }

    @Test func longPlansStartLaterAndSessionsAreTracked() throws {
        let marathon = GoalRace(name: "Maratón", date: ISO8601DateFormatter().date(from: "2027-05-02T07:00:00Z")!, distanceM: 42_195)
        let plan = PlanBuilder.build(goal: marathon, vdot: 45, history: history(weeklyKm: 40, longestKm: 16), today: today,
                                     utcOffsetSeconds: 0, daysPerWeek: 5, longRunWeekday: 7)
        #expect(plan.weeks.count == 24 && plan.weeks.first!.start > today)
        #expect(plan.weeks.suffix(4).map(\.phase) == [.peak, .taper, .taper, .race])
        #expect(plan.sessions.contains { $0.workout.kind == .marathonPace })

        // Seguimiento: hecha, a medias, saltada, hoy y pendiente.
        let easy = PlannedSession(date: today.adding(days: -2), workout: WorkoutLibrary.easy(meters: 8000, PaceSet(vdot: 45)))
        let run = RunSummary(id: "x", start: today.adding(days: -2).startDate(utcOffsetSeconds: 0).addingTimeInterval(3600 * 8),
                             utcOffsetSeconds: 0, kind: .running, name: "Carrera", distanceM: 7500, movingS: 2700, elapsedS: 2700,
                             bestEfforts: [:], paceCurve: [], powerCurve: [], sources: [.appleHealth], signature: "")
        #expect(PlanBuilder.status(of: easy, runs: [run], today: today) == .done(runID: "x"))
        var short = run
        short.distanceM = 3000
        #expect(PlanBuilder.status(of: easy, runs: [short], today: today) == .partial(runID: "x"))
        #expect(PlanBuilder.status(of: easy, runs: [], today: today) == .missed)
        var todays = easy
        todays.date = today
        #expect(PlanBuilder.status(of: todays, runs: [], today: today) == .today)
    }
}
