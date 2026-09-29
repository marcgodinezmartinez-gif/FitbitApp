import Foundation
import Insights
import MetricsKit
import Store

/// Plan semanal guardado en `app_state` (clave `weekly_plan`).
extension AppDatabase {
    public func weeklyPlan() throws -> WeeklyPlan { try readState("weekly_plan", default: WeeklyPlan()) }

    public func saveWeeklyPlan(_ plan: WeeklyPlan) throws { try writeState("weekly_plan", plan) }

    /// Progreso de la semana de `today` para la revisión del viernes; `nil` si no hay plan o se creó después del miércoles.
    public func weeklyPlanProgress(output: MetricsOutput, today: LocalDate, utcOffsetSeconds: Int) throws -> WeeklyPlanProgress? {
        let plan = try weeklyPlan()
        let start = WeeklyPlanner.weekStart(of: today)
        guard WeeklyPlanner.reviewApplies(plan: plan, weekStart: start, utcOffsetSeconds: utcOffsetSeconds) else { return nil }
        let journal = try journalAnswers(from: start, to: today)
        return WeeklyPlanner.progress(plan: plan, cycles: output.cycles, journal: journal, weekStart: start, today: today)
    }
}
