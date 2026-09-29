import Foundation
import Insights
import MetricsKit
import Store

/// Plan semanal guardado en `app_state` (clave `weekly_plan`).
extension AppDatabase {
    public func weeklyPlan() throws -> WeeklyPlan { try readState("weekly_plan", default: WeeklyPlan()) }

    public func saveWeeklyPlan(_ plan: WeeklyPlan) throws { try writeState("weekly_plan", plan) }

    /// Progreso de la semana de `today` con el plan guardado; `nil` si no hay plan.
    public func weeklyPlanProgress(output: MetricsOutput, today: LocalDate) throws -> WeeklyPlanProgress? {
        let plan = try weeklyPlan()
        guard plan.isActive else { return nil }
        let start = WeeklyPlanner.weekStart(of: today)
        let journal = try journalAnswers(from: start, to: today)
        return WeeklyPlanner.progress(plan: plan, cycles: output.cycles, journal: journal, weekStart: start, today: today)
    }
}
