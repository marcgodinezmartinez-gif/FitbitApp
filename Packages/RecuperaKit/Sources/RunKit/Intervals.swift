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

        // Dos grupos (k-medias con k = 2) que tienen que ser distintos: en un rodaje constante apenas se separan.
        guard let (slow, fast) = twoMeans(values, q1, q3), slow > 0.5, fast / slow >= 1.15 else { return nil }
        var threshold = (slow + fast) / 2
        var below = slow
        // Con tres ritmos (calentamiento suave, series y trote más lento aún) el corte entre dos grupos deja el
        // calentamiento con las series: se vuelve a partir la mitad rápida y, si hay otro escalón claro, las series son
        // solo lo de arriba.
        if let median = Stats.median(values) {
            let upper = values.filter { $0 >= median }
            if let q = Stats.percentile(upper, 10), let r = Stats.percentile(upper, 90), let (a, b) = twoMeans(upper, q, r), b / a >= 1.08 {
                let t = (a + b) / 2
                if Double(values.filter { $0 >= t }.count) >= 0.08 * Double(values.count), t > threshold {
                    threshold = t
                    below = a
                }
            }
        }

        // Tramos rápidos y lentos, con histéresis: una serie empieza al pasar el corte y no acaba hasta bajar a medio camino
        // del ritmo de abajo (una bajada o un bache de ritmo no la parten en dos).
        let exit = threshold - 0.5 * (threshold - below)
        var segments: [(fast: Bool, lo: Int, hi: Int)] = []
        var inRep = false
        for i in 0..<n {
            let v = smooth[i] ?? 0
            inRep = inRep ? v >= exit : v >= threshold
            if let last = segments.last, last.fast == inRep { segments[segments.count - 1].hi = i } else { segments.append((inRep, i, i)) }
        }
        // Los tramos muy cortos se funden con los vecinos. Las series cuentan el tiempo activo; lo lento, también el tiempo
        // con el reloj en pausa (parado un minuto entre series, eso es la recuperación).
        func duration(_ seg: (fast: Bool, lo: Int, hi: Int)) -> Double {
            (seg.fast ? s.activeT[seg.hi] - s.activeT[seg.lo] : s.t[seg.hi] - s.t[seg.lo]) + s.step
        }
        while segments.count > 1, let k = segments.indices.filter({ duration(segments[$0]) < minSegmentS })
                .min(by: { duration(segments[$0]) < duration(segments[$1]) }) {
            segments[k].fast.toggle()
            var merged: [(fast: Bool, lo: Int, hi: Int)] = []
            for seg in segments {
                if let last = merged.last, last.fast == seg.fast { merged[merged.count - 1].hi = seg.hi } else { merged.append(seg) }
            }
            segments = merged
        }

        // Bordes de cada serie: donde la velocidad (apenas suavizada) cruza el punto medio entre la serie y el tramo de al lado.
        // (Con un solo corte para todo, un umbral alto acorta las series y uno bajo las alarga.)
        let light = RunSeriesBuilder.smooth(raw, window: max(1, Int((4 / s.step).rounded())))
        func level(_ lo: Int, _ hi: Int) -> Double? {
            let pad = min(Int(10 / s.step), (hi - lo) / 4)
            return Stats.mean(((lo + pad)...max(lo + pad, hi - pad)).compactMap { raw[$0] })
        }
        let reach = Int((20 / s.step).rounded())
        for k in segments.indices where segments[k].fast {
            guard let repLevel = level(segments[k].lo, segments[k].hi) else { continue }
            if k > 0, let prev = level(segments[k - 1].lo, segments[k - 1].hi) {
                let target = (repLevel + prev) / 2
                let from = max(segments[k - 1].lo, segments[k].lo - reach), to = min(segments[k].hi, segments[k].lo + reach)
                if from < to, let i = (from...to).first(where: { (light[$0] ?? 0) >= target }) {
                    segments[k].lo = i
                    segments[k - 1].hi = max(segments[k - 1].lo, i - 1)
                }
            }
            if k + 1 < segments.count, let next = level(segments[k + 1].lo, segments[k + 1].hi) {
                let target = (repLevel + next) / 2
                let from = max(segments[k].lo, segments[k].hi - reach), to = min(segments[k + 1].hi, segments[k].hi + reach)
                if from < to, let i = (from...to).reversed().first(where: { (light[$0] ?? 0) >= target }) {
                    segments[k].hi = i
                    segments[k + 1].lo = min(segments[k + 1].hi, i + 1)
                }
            }
        }

        // Si lo rápido y lo lento van con el terreno (las «series» cuesta abajo o las «recuperaciones» cuesta arriba), son las
        // cuestas de un rodaje, no un entreno de series.
        func meanGrade(_ fast: Bool) -> Double? {
            let idx = segments.filter { $0.fast == fast && duration($0) >= minRepS }.flatMap { Array($0.lo...$0.hi) }
            return Stats.mean(idx.compactMap { s.grade[$0] })
        }
        if let gf = meanGrade(true), let gs = meanGrade(false), abs(gf - gs) > 0.012 { return nil }

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
        // Entre serie y serie se recupera: lo lento de en medio tiene que ir bastante más despacio (si se para, vale).
        let between = segments.filter { !$0.fast && s.activeT[$0.lo] > reps[0].startS && s.activeT[$0.hi] < reps[reps.count - 1].startS }
        if let repSpeed = Stats.mean(reps.compactMap(\.avgGAPSpeed)),
           let recoverySpeed = Stats.mean(between.flatMap { Array($0.lo...$0.hi) }.compactMap { raw[$0] }),
           repSpeed / recoverySpeed < 1.25 { return nil }
        // Un rodaje con paradas no es una sesión de series: lo rápido tiene que ser una parte, no casi todo.
        let repTime = reps.reduce(0) { $0 + $1.seconds }
        guard repTime >= 0.1 * movingS, repTime <= 0.7 * movingS else { return nil }
        // La última «serie» no lleva recuperación detrás: si es la vuelta a la calma a buen ritmo, sobra.
        if let last = reps.last, reps.count > 3, last.seconds > 3 * (Stats.median(reps.dropLast().map(\.seconds)) ?? last.seconds) {
            reps.removeLast()
        }
        return session(reps)
    }

    /// Centros de dos grupos (k-medias, k = 2) partiendo de `lo` y `hi`.
    static func twoMeans(_ values: [Double], _ lo: Double, _ hi: Double) -> (Double, Double)? {
        var slow = lo, fast = hi
        for _ in 0..<20 {
            let mid = (slow + fast) / 2
            guard let a = Stats.mean(values.filter { $0 < mid }), let b = Stats.mean(values.filter { $0 >= mid }) else { return nil }
            if abs(a - slow) < 1e-4 && abs(b - fast) < 1e-4 { break }
            slow = a
            fast = b
        }
        return (slow, fast)
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

    /// Distancias y tiempos de series de siempre: si encajan, mandan sobre cualquier otra cifra redonda.
    static let usualDistances: [Double] = [100, 150, 200, 250, 300, 400, 500, 600, 800, 1_000, 1_200, 1_500, 1_600, 2_000, 3_000, 4_000, 5_000]
    static let usualSeconds: [Double] = [15, 20, 30, 40, 45, 60, 90, 120, 150, 180, 240, 300, 360, 420, 480, 600, 720, 900, 1_200]

    /// «6 × 800 m» si las distancias son parecidas y redondas; «5 × 3 min» si lo son los tiempos; si no, cambios de ritmo.
    static func label(_ reps: [DetectedRep]) -> String {
        let n = reps.count
        func cv(_ xs: [Double]) -> Double {
            guard let m = Stats.mean(xs), m > 0, xs.count > 1 else { return 1 }
            return (xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count - 1)).squareRoot() / m
        }
        func error(_ x: Double, _ target: Double) -> Double { target > 0 ? abs(x - target) / target : 1 }
        func usual(_ x: Double, _ list: [Double], tolerance: Double) -> Double? {
            list.min { error(x, $0) < error(x, $1) }.flatMap { error(x, $0) <= tolerance ? $0 : nil }
        }
        let distances = reps.map(\.distanceM), times = reps.map(\.seconds)
        let d = Stats.median(distances) ?? 0, t = Stats.median(times) ?? 0
        let regularD = cv(distances) <= 0.12, regularT = cv(times) <= 0.12

        // Primero las de siempre (400 m, 1 km, 3 min…).
        let usualD = regularD ? usual(d, usualDistances, tolerance: 0.04) : nil
        let usualT = regularT ? usual(t, usualSeconds, tolerance: 0.05) : nil
        if let ud = usualD, usualT.map({ error(d, ud) <= error(t, $0) }) ?? true { return "\(n) × \(distanceText(ud))" }
        if let ut = usualT { return "\(n) × \(timeText(ut))" }

        // Si no, cualquier cifra redonda.
        let roundD = d >= 1000 ? (d / 100).rounded() * 100 : (d / 50).rounded() * 50
        let roundT = t >= 120 ? (t / 60).rounded() * 60 : (t / 15).rounded() * 15
        let errD = error(d, roundD), errT = error(t, roundT)
        let byDistance = regularD && errD <= 0.04
        let byTime = regularT && errT <= 0.05
        if byDistance && (!byTime || errD <= errT) { return "\(n) × \(distanceText(roundD))" }
        if byTime { return "\(n) × \(timeText(roundT))" }
        return "\(n) cambios de ritmo"
    }

    /// «800 m», «1 km», «1,5 km».
    static func distanceText(_ m: Double) -> String {
        guard m >= 1000 else { return "\(Int(m)) m" }
        if m.truncatingRemainder(dividingBy: 1000) == 0 { return "\(Int(m / 1000)) km" }
        return String(format: "%.1f km", m / 1000).replacingOccurrences(of: ".", with: ",")
    }

    /// «45 s», «90 s», «3 min», «2 min 30 s».
    static func timeText(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s < 120 && s % 60 != 0 { return "\(s) s" }
        return s % 60 == 0 ? "\(s / 60) min" : "\(s / 60) min \(s % 60) s"
    }
}
