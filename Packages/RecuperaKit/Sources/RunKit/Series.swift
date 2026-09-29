import Foundation
import MetricsKit
import Store

/// Todo lo que hace falta para analizar una carrera, ya leído de la base de datos.
public struct RunInput: Sendable {
    public var activity: FusedActivity
    /// Ruta GPS del Apple Watch.
    public var route: [RoutePoint]
    /// Series del Apple Watch: speed_mps, power_w, stride_m, vertical_osc_cm, ground_contact_ms, cadence_spm, distance_m.
    public var samples: [MetricSample]
    public var hrWatch: [HRSample]
    public var hrFitbit: [HRSample]
    public var watchDetail: ActivityDetail?
    public var fitbitDetail: ActivityDetail?
    public var zones: HRZones
    public var sex: Sex
    public var weightKg: Double?

    public init(activity: FusedActivity, route: [RoutePoint] = [], samples: [MetricSample] = [], hrWatch: [HRSample] = [],
                hrFitbit: [HRSample] = [], watchDetail: ActivityDetail? = nil, fitbitDetail: ActivityDetail? = nil,
                zones: HRZones, sex: Sex = .unspecified, weightKg: Double? = nil) {
        self.activity = activity
        self.route = route
        self.samples = samples
        self.hrWatch = hrWatch
        self.hrFitbit = hrFitbit
        self.watchDetail = watchDetail
        self.fitbitDetail = fitbitDetail
        self.zones = zones
        self.sex = sex
        self.weightKg = weightKg
    }
}

/// De dónde sale la distancia segundo a segundo.
public enum DistanceSource: String, Codable, Sendable {
    case gps, watchSamples, watchSpeed, fitbitSplits, average, none

    public var label: String {
        switch self {
        case .gps: return "GPS del Apple Watch"
        case .watchSamples: return "Apple Watch (sin GPS)"
        case .watchSpeed: return "Velocidad del Apple Watch"
        case .fitbitSplits: return "Parciales de la Fitbit Air"
        case .average: return "Ritmo medio"
        case .none: return "Sin distancia"
        }
    }
}

/// La carrera segundo a segundo (o cada `step` s en las muy largas), con lo que haya de cada fuente.
public struct RunSeries: Sendable {
    public var start: Date
    public var step: Double
    /// Segundos desde el inicio.
    public var t: [Double]
    /// Segundos activos (sin las pausas del reloj o la pulsera).
    public var activeT: [Double]
    /// Metros acumulados.
    public var distance: [Double]
    /// m/s suavizada (0 en pausa).
    public var speed: [Double]
    /// Velocidad equivalente en llano (GAP).
    public var gapSpeed: [Double]
    /// FC principal: la del Watch y, donde falte, la de la Fitbit.
    public var hr: [Double?]
    public var hrWatch: [Double?]
    public var hrFitbit: [Double?]
    public var altitude: [Double?]
    /// Pendiente (fracción: 0,05 = 5 %).
    public var grade: [Double?]
    public var cadence: [Double?]
    public var power: [Double?]
    public var stride: [Double?]
    public var verticalOsc: [Double?]
    public var groundContact: [Double?]
    public var moving: [Bool]
    public var paused: [Bool]
    public var distanceSource: DistanceSource
    public var hrSource: DataSourceKind?

    public var count: Int { t.count }

    /// Índice del punto más cercano a un instante.
    public func index(at date: Date) -> Int {
        guard count > 0 else { return 0 }
        return min(count - 1, max(0, Int((date.timeIntervalSince(start) / step).rounded())))
    }
}

public enum RunSeriesBuilder {
    public static func build(_ input: RunInput) -> RunSeries {
        let a = input.activity
        let start = a.start
        let duration = max(1, a.end.timeIntervalSince(start))
        let step = max(1, (duration / 20_000).rounded(.up))
        let n = Int(duration / step) + 1
        let grid = (0..<n).map { Double($0) * step }
        func idx(_ seconds: Double) -> Int { min(n - 1, max(0, Int((seconds / step).rounded()))) }

        // Pausas explícitas del reloj o de la pulsera.
        let pauseEvents = ((input.watchDetail?.events ?? []) + (input.fitbitDetail?.events ?? [])).filter { $0.kind == .pause }
        let pauses = pauseEvents.map { ($0.start.timeIntervalSince(start), $0.end.timeIntervalSince(start)) }
            .filter { $0.1 > $0.0 && $0.1 > 0 && $0.0 < duration }
        var paused = [Bool](repeating: false, count: n)
        for (s, e) in pauses {
            let lo = idx(max(0, s)), hi = idx(min(duration, e))
            if lo < hi { for i in lo..<hi { paused[i] = true } }
        }
        var activeT = [Double](repeating: 0, count: n)
        for i in 1..<n { activeT[i] = activeT[i - 1] + (paused[i - 1] ? 0 : step) }

        let byMetric = Dictionary(grouping: input.samples, by: \.metric)
        func points(_ metric: String) -> [(Double, Double)] {
            dedupe((byMetric[metric] ?? []).map { ($0.time.timeIntervalSince(start), $0.value) }.filter { $0.0 >= -60 && $0.0 <= duration + 60 })
        }

        // Distancia acumulada.
        let official = a.distanceM
        var distanceSource = DistanceSource.none
        var distance = [Double](repeating: 0, count: n)
        let gps = gpsDistance(input.route, start: start, pauses: pauses)
        let watchDistance = points("distance_m")
        let watchSpeed = points("speed_mps")
        let fitbitSplits = (input.fitbitDetail?.splits ?? []).sorted { $0.end < $1.end }
        if a.kind != .treadmill, gps.count >= 30, let total = gps.last?.1, total > 200 {
            distanceSource = .gps
            var scale = 1.0
            if let official, official > 0 { let r = official / total; if r > 0.85 && r < 1.15 { scale = r } }
            distance = resampleCumulative(gps.map { ($0.0, $0.1 * scale) }, grid: grid)
        } else if watchDistance.count >= 5 {
            distanceSource = .watchSamples
            var total = 0.0
            let cumulative = [(0.0, 0.0)] + watchDistance.map { p -> (Double, Double) in total += p.1; return (p.0, total) }
            distance = resampleCumulative(cumulative, grid: grid)
        } else if watchSpeed.count >= 10 {
            distanceSource = .watchSpeed
            let v = resample(watchSpeed, grid: grid, maxGap: 30)
            for i in 1..<n { distance[i] = distance[i - 1] + (paused[i - 1] ? 0 : (v[i - 1] ?? 0) * step) }
        } else if !fitbitSplits.isEmpty {
            distanceSource = .fitbitSplits
            var total = 0.0
            var cumulative: [(Double, Double)] = [(0, 0)]
            for s in fitbitSplits {
                total += s.distanceM ?? 0
                cumulative.append((s.end.timeIntervalSince(start), total))
            }
            if let official, official > total { cumulative.append((duration, official)) }
            distance = resampleCumulative(cumulative, grid: grid)
        } else if let official, official > 0 {
            distanceSource = .average
            let activeTotal = max(activeT[n - 1], 1)
            distance = activeT.map { official * $0 / activeTotal }
        }

        // Velocidad: la del reloj si la hay y, si no, la derivada de la distancia (ventana de ~15 s).
        var speed = [Double](repeating: 0, count: n)
        let w = max(1, Int((7 / step).rounded()))
        for i in 0..<n {
            let lo = max(0, i - w), hi = min(n - 1, i + w)
            let dt = grid[hi] - grid[lo]
            speed[i] = dt > 0 ? max(0, (distance[hi] - distance[lo]) / dt) : 0
        }
        if distanceSource != .gps, watchSpeed.count >= 10 {
            let v = smooth(resample(watchSpeed, grid: grid, maxGap: 20), window: max(1, Int(5 / step)))
            for i in 0..<n { if let x = v[i] { speed[i] = x } }
        }
        for i in 0..<n where paused[i] { speed[i] = 0 }

        // En movimiento: sin pausa y sin estar parado más de 10 s seguidos.
        var moving = paused.map { !$0 }
        if distanceSource != .average && distanceSource != .none {
            var runStart: Int?
            for i in 0...n {
                let slow = i < n && !paused[i] && speed[i] < 0.5
                if slow { if runStart == nil { runStart = i } } else if let s = runStart {
                    if Double(i - s) * step >= 10 { for k in s..<i { moving[k] = false } }
                    runStart = nil
                }
            }
        }

        // FC: la del Watch; donde falte, la de la Fitbit.
        let hrWatch = resample(dedupe(input.hrWatch.map { ($0.time.timeIntervalSince(start), $0.bpm) }), grid: grid, maxGap: 20)
        let hrFitbit = resample(dedupe(input.hrFitbit.map { ($0.time.timeIntervalSince(start), $0.bpm) }), grid: grid, maxGap: 20)
        let watchCoverage = Double(hrWatch.compactMap { $0 }.count) / Double(n)
        let fitbitCoverage = Double(hrFitbit.compactMap { $0 }.count) / Double(n)
        let watchFirst = watchCoverage >= 0.3 || watchCoverage >= fitbitCoverage
        let hr: [Double?] = (0..<n).map { watchFirst ? (hrWatch[$0] ?? hrFitbit[$0]) : (hrFitbit[$0] ?? hrWatch[$0]) }
        let hrSource: DataSourceKind? = watchCoverage == 0 && fitbitCoverage == 0 ? nil : (watchFirst ? .appleHealth : .googleHealth)

        // Altitud (suavizada ~30 s) y pendiente sobre ~20 s de recorrido.
        let alt = input.route.compactMap { p -> (Double, Double)? in
            guard let al = p.altitude, (p.horizontalAccuracy ?? 0) <= 50 else { return nil }
            return (p.time.timeIntervalSince(start), al)
        }
        let altitude = smooth(resample(dedupe(alt), grid: grid, maxGap: 60), window: max(1, Int(31 / step)))
        var grade = [Double?](repeating: nil, count: n)
        let gw = max(1, Int((10 / step).rounded()))
        for i in 0..<n {
            let lo = max(0, i - gw), hi = min(n - 1, i + gw)
            guard let a0 = altitude[lo], let a1 = altitude[hi] else { continue }
            let dd = distance[hi] - distance[lo]
            if dd >= 15 { grade[i] = Stats.clip((a1 - a0) / dd, -0.45, 0.45) }
        }
        grade = smooth(grade, window: max(1, Int(11 / step)))
        let gapSpeed = (0..<n).map { RunPhysiology.gradeAdjusted(speed: speed[$0], grade: grade[$0]) }

        // Cadencia, potencia y dinámica de carrera.
        func series(_ metric: String, maxGap: Double) -> [Double?] {
            smooth(resample(points(metric), grid: grid, maxGap: maxGap), window: max(1, Int(5 / step)))
        }
        var cadence = series("cadence_spm", maxGap: 45)
        if cadence.allSatisfy({ $0 == nil }) {
            // Sin cadencia del reloj: la de cada parcial de la Fitbit.
            for s in fitbitSplits {
                guard let c = s.avgCadence else { continue }
                let lo = idx(s.start.timeIntervalSince(start)), hi = idx(s.end.timeIntervalSince(start))
                if lo < hi { for i in lo..<hi { cadence[i] = c } }
            }
        }
        return RunSeries(start: start, step: step, t: grid, activeT: activeT, distance: distance, speed: speed, gapSpeed: gapSpeed,
                         hr: hr, hrWatch: hrWatch, hrFitbit: hrFitbit, altitude: altitude, grade: grade, cadence: cadence,
                         power: series("power_w", maxGap: 30), stride: series("stride_m", maxGap: 45),
                         verticalOsc: series("vertical_osc_cm", maxGap: 45), groundContact: series("ground_contact_ms", maxGap: 45),
                         moving: moving, paused: paused, distanceSource: distanceSource, hrSource: hrSource)
    }

    // MARK: Utilidades

    /// Distancia acumulada por GPS: sin puntos imprecisos, sin saltos imposibles y sin lo recorrido en pausa.
    static func gpsDistance(_ route: [RoutePoint], start: Date, pauses: [(Double, Double)]) -> [(Double, Double)] {
        var out: [(Double, Double)] = []
        var total = 0.0
        var prev: RoutePoint?
        for p in route.sorted(by: { $0.time < $1.time }) {
            if let acc = p.horizontalAccuracy, acc > 50 { continue }
            let tp = p.time.timeIntervalSince(start)
            if let q = prev {
                let tq = q.time.timeIntervalSince(start)
                let d = Geo.distance(q.latitude, q.longitude, p.latitude, p.longitude)
                let dt = tp - tq
                let inPause = pauses.contains { $0.0 < tp && $0.1 > tq }
                if dt > 0, d / dt < 12, !inPause { total += d }
            }
            if out.last.map({ tp > $0.0 }) ?? true { out.append((tp, total)) }
            prev = p
        }
        return out
    }

    /// Ordena y quita tiempos repetidos.
    static func dedupe(_ pts: [(Double, Double)]) -> [(Double, Double)] {
        var out: [(Double, Double)] = []
        for p in pts.sorted(by: { $0.0 < $1.0 }) where p.1.isFinite {
            if let last = out.last, last.0 == p.0 { out[out.count - 1] = p } else { out.append(p) }
        }
        return out
    }

    /// Interpolación lineal en la rejilla; `nil` si el hueco entre muestras supera `maxGap` o se sale del rango.
    static func resample(_ pts: [(Double, Double)], grid: [Double], maxGap: Double) -> [Double?] {
        var out = [Double?](repeating: nil, count: grid.count)
        guard !pts.isEmpty else { return out }
        var j = 0
        for (i, x) in grid.enumerated() {
            while j + 1 < pts.count && pts[j + 1].0 <= x { j += 1 }
            let a = pts[j]
            if x < a.0 {
                if a.0 - x <= maxGap / 2 { out[i] = a.1 }
            } else if j + 1 < pts.count {
                let b = pts[j + 1]
                if b.0 - a.0 <= maxGap {
                    out[i] = a.1 + (x - a.0) / max(b.0 - a.0, 1e-9) * (b.1 - a.1)
                } else if x - a.0 <= maxGap / 2 {
                    out[i] = a.1
                }
            } else if x - a.0 <= maxGap / 2 {
                out[i] = a.1
            }
        }
        return out
    }

    /// Serie acumulada (monótona): interpola en cualquier hueco y mantiene los extremos.
    static func resampleCumulative(_ pts: [(Double, Double)], grid: [Double]) -> [Double] {
        let clean = dedupe(pts)
        guard let first = clean.first, let last = clean.last else { return grid.map { _ in 0 } }
        var j = 0
        var running = 0.0
        return grid.map { x in
            if x <= first.0 { return max(running, first.1 * (first.0 > 0 ? max(0, x) / first.0 : 1)) }
            if x >= last.0 { running = max(running, last.1); return running }
            while j + 1 < clean.count && clean[j + 1].0 <= x { j += 1 }
            let a = clean[j], b = clean[min(j + 1, clean.count - 1)]
            let v = b.0 > a.0 ? a.1 + (x - a.0) / (b.0 - a.0) * (b.1 - a.1) : a.1
            running = max(running, v)
            return running
        }
    }

    /// Media móvil centrada que ignora los huecos (y los respeta: donde no había dato sigue sin haberlo).
    static func smooth(_ xs: [Double?], window: Int) -> [Double?] {
        guard window > 1, !xs.isEmpty else { return xs }
        let n = xs.count
        var sum = [Double](repeating: 0, count: n + 1)
        var cnt = [Int](repeating: 0, count: n + 1)
        for i in 0..<n {
            sum[i + 1] = sum[i] + (xs[i] ?? 0)
            cnt[i + 1] = cnt[i] + (xs[i] == nil ? 0 : 1)
        }
        let h = window / 2
        return (0..<n).map { i in
            guard xs[i] != nil else { return nil }
            let lo = max(0, i - h), hi = min(n, i + h + 1)
            let c = cnt[hi] - cnt[lo]
            return c > 0 ? (sum[hi] - sum[lo]) / Double(c) : xs[i]
        }
    }
}

/// Distancias en la esfera (sin CoreLocation, para poder probarlo en Linux).
public enum Geo {
    public static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6_371_008.8
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dp = p2 - p1, dl = (lon2 - lon1) * .pi / 180
        let h = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * asin(min(1, h.squareRoot()))
    }
}
