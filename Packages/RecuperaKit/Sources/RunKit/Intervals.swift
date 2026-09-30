import Foundation
import MetricsKit

/// Una serie: el tramo rápido y la recuperación que le sigue.
public struct DetectedRep: Codable, Sendable, Hashable, Identifiable {
    public var index: Int
    /// Segundos activos al empezar y al acabar.
    public var startS: Double
    public var endS: Double
    public var distanceM: Double
    public var seconds: Double
    public var avgGAPSpeed: Double?
    public var avgHR: Double?
    public var maxHR: Double?
    public var recoverySeconds: Double?
    public var recoveryDistanceM: Double?
    /// FC al final de la recuperación: cuánto baja antes de la siguiente.
    public var recoveryEndHR: Double?

    public var id: Int { index }
    public var pace: Double { distanceM > 0 ? seconds / distanceM * 1000 : 0 }
    public var gapPace: Double? { avgGAPSpeed.flatMap { $0 > 0.3 ? 1000 / $0 : nil } }
}

/// Sesión de series: detectada en la velocidad o marcada por el reloj.
public struct IntervalSession: Codable, Sendable, Hashable {
    public var reps: [DetectedRep]
    /// «6 × 800 m», «5 × 3 min» o «8 cambios de ritmo».
    public var label: String
    public var avgRepPace: Double
    public var avgRecoverySeconds: Double?
    /// Ritmo de la última serie frente al de la primera: positivo si te has ido cayendo.
    public var fadePct: Double?
    /// Variación del ritmo entre series (coeficiente de variación, %): menos es más regular.
    public var paceSpreadPct: Double?
}

/// Detección de series sin vueltas marcadas (doc. 18 §4): la velocidad ajustada por pendiente, suavizada, se parte en
/// dos grupos (rápido y lento) y los tramos rápidos de al menos 30 s son las series.
public enum IntervalDetector {
    /// Tramos más cortos que esto se funden con los vecinos (un semáforo, un giro).
    static let minSegmentS = 12.0
    static let minRepS = 30.0
    static let minRepM = 100.0

    public static func detect(_ s: RunSeries) -> IntervalSession? {
        let n = s.count
        guard n > 0, s.distanceSource != .average, s.distanceSource != .none else { return nil }
        let movingS = Double(s.moving.filter { $0 }.count) * s.step
        guard movingS >= 12 * 60 else { return nil }

        // Velocidad ajustada por pendiente, suavizada ~16 s (fuera de movimiento cuenta como lenta).
        let raw: [Double?] = (0..<n).map { s.moving[$0] ? s.gapSpeed[$0] : nil }
        let smooth = RunSeriesBuilder.smooth(raw, window: max(1, Int((16 / s.step).rounded())))
        let values = smooth.compactMap { $0 }.sorted()
        guard values.count >= 60, let q1 = Stats.percentile(values, 25), let q3 = Stats.percentile(values, 75) else { return nil }

        // Dos grupos (k-medias con k = 2) que tienen que ser claramente distintos.
        var slow = q1, fast = q3
        for _ in 0..<20 {
            let mid = (slow + fast) / 2
            let lo = values.filter { $0 < mid }, hi = values.filter { $0 >= mid }
            guard let a = Stats.mean(lo), let b = Stats.mean(hi) else { return nil }
            if abs(a - slow) < 1e-4 && abs(b - fast) < 1e-4 { break }
            slow = a
            fast = b
        }
        guard slow > 0.5, fast / slow >= 1.18 else { return nil }
        let threshold = (slow + fast) / 2

        // Tramos rápidos y lentos, fundiendo los muy cortos.
        var segments: [(fast: Bool, lo: Int, hi: Int)] = []
        for i in 0..<n {
            let isFast = (smooth[i] ?? 0) >= threshold
            if let last = segments.last, last.fast == isFast { segments[segments.count - 1].hi = i } else { segments.append((isFast, i, i)) }
        }
        func duration(_ seg: (fast: Bool, lo: Int, hi: Int)) -> Double { s.activeT[seg.hi] - s.activeT[seg.lo] + s.step }
        while segments.count > 1, let k = segments.indices.filter({ duration(segments[$0]) < minSegmentS })
                .min(by: { duration(segments[$0]) < duration(segments[$1]) }) {
            segments[k].fast.toggle()
            var merged: [(fast: Bool, lo: Int, hi: Int)] = []
            for seg in segments {
                if let last = merged.last, last.fast == seg.fast { merged[merged.count - 1].hi = seg.hi } else { merged.append(seg) }
            }
            segments = merged
        }

        // Series: tramos rápidos de al menos 30 s y 100 m.
        var reps: [DetectedRep] = []
        for (k, seg) in segments.enumerated() where seg.fast {
            let distance = s.distance[seg.hi] - s.distance[seg.lo]
            let seconds = duration(seg)
            guard seconds >= minRepS, distance >= minRepM else { continue }
            let range = seg.lo...seg.hi
            var rep = DetectedRep(index: reps.count + 1, startS: s.activeT[seg.lo], endS: s.activeT[seg.hi] + s.step,
                                  distanceM: distance, seconds: seconds,
                                  avgGAPSpeed: Stats.mean(range.filter { s.moving[$0] }.map { s.gapSpeed[$0] }),
                                  avgHR: Stats.mean(range.compactMap { s.hr[$0] }), maxHR: range.compactMap { s.hr[$0] }.max())
            // La recuperación: el tramo lento siguiente, si después viene otra serie.
            if k + 2 < segments.count, !segments[k + 1].fast {
                let r = segments[k + 1]
                rep.recoverySeconds = duration(r)
                rep.recoveryDistanceM = s.distance[r.hi] - s.distance[r.lo]
                rep.recoveryEndHR = (max(r.lo, r.hi - Int(10 / s.step))...r.hi).compactMap { s.hr[$0] }.last
            }
            reps.append(rep)
        }
        guard reps.count >= 3 else { return nil }
        // Un rodaje con paradas no es una sesión de series: lo rápido tiene que ser una parte, no casi todo.
        let repTime = reps.reduce(0) { $0 + $1.seconds }
        guard repTime >= 0.1 * movingS, repTime <= 0.7 * movingS else { return nil }
        // La última «serie» no lleva recuperación detrás: si es la vuelta a la calma a buen ritmo, sobra.
        if let last = reps.last, reps.count > 3, last.seconds > 3 * (Stats.median(reps.dropLast().map(\.seconds)) ?? last.seconds) {
            reps.removeLast()
        }
        return session(reps)
    }

    /// Resumen de unas series: nombre, ritmo medio, recuperación, caída y regularidad.
    public static func session(_ reps: [DetectedRep]) -> IntervalSession {
        let paces = reps.map(\.pace)
        let meanPace = Stats.mean(paces) ?? 0
        var spread: Double?
        if paces.count >= 2, meanPace > 0 {
            let sd = (paces.reduce(0) { $0 + ($1 - meanPace) * ($1 - meanPace) } / Double(paces.count - 1)).squareRoot()
            spread = sd / meanPace * 100
        }
        var fade: Double?
        if let first = reps.first?.pace, let last = reps.last?.pace, first > 0 { fade = (last - first) / first * 100 }
        return IntervalSession(reps: reps, label: label(reps), avgRepPace: meanPace,
                               avgRecoverySeconds: Stats.mean(reps.compactMap(\.recoverySeconds)), fadePct: fade, paceSpreadPct: spread)
    }

    /// «6 × 800 m» si las distancias son parecidas y redondas; «5 × 3 min» si lo son los tiempos; si no, cambios de ritmo.
    static func label(_ reps: [DetectedRep]) -> String {
        let n = reps.count
        func cv(_ xs: [Double]) -> Double {
            guard let m = Stats.mean(xs), m > 0, xs.count > 1 else { return 1 }
            return (xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count - 1)).squareRoot() / m
        }
        let distances = reps.map(\.distanceM), times = reps.map(\.seconds)
        let d = Stats.median(distances) ?? 0, t = Stats.median(times) ?? 0
        let roundD = d >= 1000 ? (d / 100).rounded() * 100 : (d / 50).rounded() * 50
        let roundT = t >= 120 ? (t / 60).rounded() * 60 : (t / 15).rounded() * 15
        let errD = roundD > 0 ? abs(d - roundD) / roundD : 1
        let errT = roundT > 0 ? abs(t - roundT) / roundT : 1
        let byDistance = cv(distances) <= 0.12 && errD <= 0.04
        let byTime = cv(times) <= 0.12 && errT <= 0.05
        if byDistance && (!byTime || errD <= errT) {
            let text = roundD >= 1000 ? (roundD.truncatingRemainder(dividingBy: 1000) == 0 ? "\(Int(roundD / 1000)) km"
                                                                                         : String(format: "%.1f km", roundD / 1000).replacingOccurrences(of: ".", with: ","))
                : "\(Int(roundD)) m"
            return "\(n) × \(text)"
        }
        if byTime {
            let text = roundT >= 60 && roundT.truncatingRemainder(dividingBy: 60) == 0 ? "\(Int(roundT / 60)) min" : "\(Int(roundT)) s"
            return "\(n) × \(text)"
        }
        return "\(n) cambios de ritmo"
    }
}
