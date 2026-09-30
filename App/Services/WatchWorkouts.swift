import Foundation
import HealthKit
import WorkoutKit
import MetricsKit
import RunKit

/// Entrenos estructurados en el Apple Watch (WorkoutKit): cada paso con su objetivo (distancia o tiempo) y su aviso de ritmo
/// o de zona de FC. Se programan para un día y aparecen en la app Entreno del reloj, con el nombre de Recupera.
enum WatchWorkouts {
    static var isSupported: Bool { WorkoutScheduler.isSupported }

    static func goal(_ g: StepGoal) -> WorkoutGoal {
        switch g {
        case .distance(let m): return .distance(m, .meters)
        case .time(let s): return .time(s, .seconds)
        case .open: return .open
        }
    }

    /// Aviso de ritmo (rango de velocidad) o de zona de FC, si el reloj lo admite en una carrera al aire libre.
    static func alert(_ t: WorkoutTarget) -> (any WorkoutAlert)? {
        if let fast = t.paceFast, let slow = t.paceSlow, fast > 0, slow > fast {
            let lo = Measurement(value: 1000 / slow, unit: UnitSpeed.metersPerSecond)
            let hi = Measurement(value: 1000 / fast, unit: UnitSpeed.metersPerSecond)
            let a = SpeedRangeAlert(target: lo...hi, metric: .current)
            return CustomWorkout.supportsAlert(a, activity: .running, location: .outdoor) ? a : nil
        }
        if let z = t.heartRateZone {
            let a = HeartRateZoneAlert(zone: z)
            return CustomWorkout.supportsAlert(a, activity: .running, location: .outdoor) ? a : nil
        }
        return nil
    }

    static func step(_ s: WorkoutStepPlan) -> WorkoutStep {
        WorkoutStep(goal: goal(s.goal), alert: alert(s.target), displayName: s.label)
    }

    static func custom(_ w: StructuredWorkout) -> CustomWorkout {
        let blocks = w.blocks.map { b in
            IntervalBlock(steps: b.steps.map { IntervalStep($0.purpose == .recovery ? .recovery : .work, step: step($0)) },
                          iterations: max(1, b.iterations))
        }
        return CustomWorkout(activity: .running, location: .outdoor, displayName: w.title, warmup: w.warmup.map(step),
                             blocks: blocks, cooldown: w.cooldown.map(step))
    }

    static func plan(_ w: StructuredWorkout) -> WorkoutPlan { WorkoutPlan(.custom(custom(w))) }

    enum Failure: LocalizedError {
        case notSupported, denied

        var errorDescription: String? {
            switch self {
            case .notSupported: return "Este iPhone no puede enviar entrenos al Apple Watch (hace falta un Watch emparejado con watchOS 10 o posterior)."
            case .denied: return "Recupera no tiene permiso para programar entrenos en el Watch. Actívalo en Ajustes › Privacidad y seguridad."
            }
        }
    }

    /// Programa el entreno para ese día (a las `hour`): aparece en Entreno › Programados del Watch.
    static func schedule(_ w: StructuredWorkout, on date: LocalDate, hour: Int = 7) async throws {
        guard isSupported else { throw Failure.notSupported }
        let scheduler = WorkoutScheduler.shared
        var state = await scheduler.authorizationState
        if state != .authorized { state = await scheduler.requestAuthorization() }
        guard state == .authorized else { throw Failure.denied }
        var components = DateComponents()
        components.year = date.year
        components.month = date.month
        components.day = date.day
        components.hour = hour
        components.minute = 0
        await scheduler.schedule(plan(w), at: components)
    }

    /// Programa todas las sesiones pendientes del plan (el reloj admite un máximo; se mandan las más cercanas).
    static func schedule(_ sessions: [PlannedSession], hour: Int = 7) async throws -> Int {
        let limit = WorkoutScheduler.maxAllowedScheduledWorkoutCount
        var sent = 0
        for s in sessions.sorted(by: { $0.date < $1.date }).prefix(max(0, limit)) {
            try await schedule(s.workout, on: s.date, hour: hour)
            sent += 1
        }
        return sent
    }
}
