import Foundation

// MARK: - Respiración guiada (RF-EST-05)

/// Patrón de respiración: una secuencia de fases que se repite.
public struct BreathingPattern: Sendable, Hashable, Identifiable {
    public enum PhaseKind: String, Sendable, Hashable {
        case inhale, topUp, hold, exhale

        public var instruction: String {
            switch self {
            case .inhale: return "Inhala"
            case .topUp: return "Un poco más"
            case .hold: return "Mantén"
            case .exhale: return "Exhala despacio"
            }
        }
    }

    public struct Phase: Sendable, Hashable {
        public var kind: PhaseKind
        public var seconds: Double
        /// Tamaño del círculo al terminar la fase (0 = vacío, 1 = lleno).
        public var targetScale: Double
    }

    public var id: String
    public var title: String
    public var subtitle: String
    public var phases: [Phase]

    public var cycleSeconds: Double { phases.reduce(0) { $0 + $1.seconds } }
    public var breathsPerMinute: Double { 60 / cycleSeconds }

    /// Respiración lenta a ~6 por minuto (4 s dentro, 6 s fuera).
    public static let slow = BreathingPattern(id: "slow", title: "Respiración lenta",
                                              subtitle: "6 respiraciones por minuto: 4 s dentro, 6 s fuera",
                                              phases: [Phase(kind: .inhale, seconds: 4, targetScale: 1),
                                                       Phase(kind: .exhale, seconds: 6, targetScale: 0)])

    /// Suspiro cíclico: dos inspiraciones por la nariz y una espiración larga por la boca.
    public static let cyclicSigh = BreathingPattern(id: "sigh", title: "Suspiro cíclico",
                                                    subtitle: "Inspira, un poco más, y suelta el aire muy despacio",
                                                    phases: [Phase(kind: .inhale, seconds: 2.5, targetScale: 0.8),
                                                             Phase(kind: .topUp, seconds: 1, targetScale: 1),
                                                             Phase(kind: .exhale, seconds: 6.5, targetScale: 0)])

    public static let all: [BreathingPattern] = [.slow, .cyclicSigh]

    /// Fase en curso a los `elapsed` segundos: índice, progreso dentro de la fase (0–1) y ciclo completado.
    public func state(at elapsed: Double) -> (index: Int, progress: Double, cycle: Int) {
        guard cycleSeconds > 0, !phases.isEmpty else { return (0, 0, 0) }
        let t = max(0, elapsed)
        let cycle = Int(t / cycleSeconds)
        var inCycle = t - Double(cycle) * cycleSeconds
        for (i, p) in phases.enumerated() {
            if inCycle < p.seconds { return (i, inCycle / p.seconds, cycle) }
            inCycle -= p.seconds
        }
        return (phases.count - 1, 1, cycle)
    }

    /// Escala del círculo a los `elapsed` segundos (interpolada desde la fase anterior).
    public func scale(at elapsed: Double) -> Double {
        let s = state(at: elapsed)
        let from = s.index == 0 ? (phases.last?.targetScale ?? 0) : phases[s.index - 1].targetScale
        let to = phases[s.index].targetScale
        // Suavizado seno para que el círculo no se mueva a golpes.
        let eased = 0.5 - 0.5 * cos(Double.pi * s.progress)
        return from + (to - from) * eased
    }

    /// Ciclos completos que caben en una sesión de `minutes` minutos.
    public func cycles(inMinutes minutes: Double) -> Int { Int((minutes * 60 / cycleSeconds).rounded(.down)) }
}
