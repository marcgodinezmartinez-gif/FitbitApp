import Foundation
import MetricsKit

// MARK: - Registro de fuerza (RF-ENT-05)

/// Resumen de un ejercicio dentro de una sesión.
public struct ExerciseSummary: Sendable, Hashable, Identifiable {
    public var exercise: String
    public var sets: Int
    public var reps: Int
    public var volumeKg: Double
    public var topWeightKg: Double?
    public var bestOneRepMax: Double?
    public var id: String { exercise }
}

/// Resumen de una sesión de fuerza: series, repeticiones y volumen, por ejercicio y en total.
public struct StrengthSummary: Sendable, Hashable {
    public var exercises: [ExerciseSummary]
    public var totalSets: Int
    public var totalReps: Int
    public var volumeKg: Double

    public static func of(_ sets: [StrengthSet]) -> StrengthSummary {
        var order: [String] = []
        var groups: [String: [StrengthSet]] = [:]
        for s in sets where s.reps > 0 {
            let key = StrengthCatalog.normalized(s.exercise)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(s)
        }
        let exercises = order.map { key -> ExerciseSummary in
            let g = groups[key] ?? []
            return ExerciseSummary(exercise: g.first?.exercise.trimmingCharacters(in: .whitespaces) ?? key, sets: g.count,
                                   reps: g.reduce(0) { $0 + $1.reps }, volumeKg: g.reduce(0) { $0 + $1.volumeKg },
                                   topWeightKg: g.compactMap(\.weightKg).max(), bestOneRepMax: g.compactMap(\.estimatedOneRepMax).max())
        }
        return StrengthSummary(exercises: exercises, totalSets: exercises.reduce(0) { $0 + $1.sets },
                               totalReps: exercises.reduce(0) { $0 + $1.reps }, volumeKg: exercises.reduce(0) { $0 + $1.volumeKg })
    }

    /// Carga muscular por sRPE (ALG-CAR-05): sRPE = RPE × minutos; en la escala de carga 0–21, κ · sRPE.
    public static func muscularLoad(rpe: Double?, minutes: Double, params: AlgorithmParams = .default) -> (srpe: Double, strain: Double)? {
        guard let rpe, rpe > 0, minutes > 0 else { return nil }
        let srpe = rpe * minutes
        return (srpe, StrainCalculator.scale(load: params.strain.kappaSrpe * srpe, params: params))
    }
}

public enum StrengthRecords {
    /// Mejor 1RM estimado de cada ejercicio (clave normalizada) en un historial de sesiones.
    public static func bestOneRepMax(_ sessions: [[StrengthSet]]) -> [String: Double] {
        var best: [String: Double] = [:]
        for sets in sessions {
            for s in sets {
                guard let e = s.estimatedOneRepMax else { continue }
                let key = StrengthCatalog.normalized(s.exercise)
                best[key] = max(best[key] ?? 0, e)
            }
        }
        return best
    }

    /// Ejercicios de la sesión que superan su mejor 1RM estimado anterior (solo si ya había uno).
    public static func newRecords(session: [StrengthSet], previousBest: [String: Double]) -> [String] {
        let summary = StrengthSummary.of(session)
        return summary.exercises.compactMap { e in
            let key = StrengthCatalog.normalized(e.exercise)
            guard let now = e.bestOneRepMax, let before = previousBest[key], now > before + 0.01 else { return nil }
            return e.exercise
        }
    }
}

public enum StrengthCatalog {
    /// Ejercicios habituales para elegir rápido (se puede escribir cualquier otro).
    public static let common: [String] = [
        "Sentadilla", "Press de banca", "Peso muerto", "Press militar", "Dominadas", "Remo con barra", "Hip thrust", "Zancadas",
        "Peso muerto rumano", "Prensa de piernas", "Fondos", "Press inclinado con mancuernas", "Remo con mancuerna", "Jalón al pecho",
        "Curl de bíceps", "Extensión de tríceps", "Elevaciones laterales", "Gemelos", "Plancha", "Kettlebell swing",
    ]

    /// Clave para agrupar el mismo ejercicio escrito de distintas formas (mayúsculas, tildes, espacios).
    public static func normalized(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_ES"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
