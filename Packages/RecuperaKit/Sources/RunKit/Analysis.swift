import Foundation
import MetricsKit
import Store

/// Lo que se sabe de tu historial y afina el análisis de una carrera.
public struct RunContext: Sendable, Hashable {
    public var vdot: Double?
    /// Velocidad de umbral (ritmo T), m/s: para el estrés (rTSS) y la intensidad.
    public var thresholdSpeed: Double?
    /// Potencia crítica estimada (W): para las zonas de potencia.
    public var criticalPower: Double?

    public init(vdot: Double? = nil, thresholdSpeed: Double? = nil, criticalPower: Double? = nil) {
        self.vdot = vdot
        self.thresholdSpeed = thresholdSpeed
        self.criticalPower = criticalPower
    }
}

public struct RunSplit: Codable, Sendable, Hashable, Identifiable {
    public var index: Int
    public var distanceM: Double
    public var seconds: Double
    public var gapSeconds: Double?
    public var avgHR: Double?
    public var maxHR: Double?
    public var cadence: Double?
    public var power: Double?
    public var stride: Double?
    public var elevationGainM: Double
    public var elevationLossM: Double
    public var avgGradePct: Double?

    public var id: Int { index }
    /// Segundos por km.
    public var pace: Double { distanceM > 0 ? seconds / distanceM * 1000 : 0 }
    public var gapPace: Double? { gapSeconds.map { distanceM > 0 ? $0 / distanceM * 1000 : 0 } }
}

public struct RunLap: Codable, Sendable, Hashable, Identifiable {
    public var index: Int
    /// lap, segment, interval, manual, distance, duration…
    public var kind: String
    public var source: DataSourceKind
    public var startS: Double
    public var endS: Double
    public var distanceM: Double?
    public var seconds: Double
    public var avgHR: Double?
    public var maxHR: Double?
    public var cadence: Double?
    public var power: Double?

    public var id: Int { index }
    public var pace: Double? { distanceM.flatMap { $0 > 50 ? seconds / $0 * 1000 : nil } }
}

public struct BestEffort: Codable, Sendable, Hashable, Identifiable {
    public var distance: RaceDistance
    public var seconds: Double
    public var startS: Double
    public var id: Double { distance.rawValue }
}

public struct CurvePoint: Codable, Sendable, Hashable {
    public var seconds: Double
    public var value: Double

    public init(seconds: Double, value: Double) {
        self.seconds = seconds
        self.value = value
    }
}

public struct Climb: Codable, Sendable, Hashable, Identifiable {
    public var index: Int
    public var startKm: Double
    public var lengthM: Double
    public var gainM: Double
    public var avgGradePct: Double
    public var seconds: Double
    /// Metros de ascenso por hora (VAM).
    public var vam: Double
    public var id: Int { index }
}

/// Técnica de carrera con una valoración orientativa.
public struct FormMetric: Codable, Sendable, Hashable, Identifiable {
    public enum Metric: String, Codable, Sendable, CaseIterable {
        case cadence, groundContact, verticalOsc, verticalRatio, stride, power

        public var label: String {
            switch self {
            case .cadence: return "Cadencia"
            case .groundContact: return "Contacto con el suelo"
            case .verticalOsc: return "Oscilación vertical"
            case .verticalRatio: return "Ratio vertical"
            case .stride: return "Longitud de zancada"
            case .power: return "Potencia"
            }
        }
    }

    public enum Rating: String, Codable, Sendable {
        case excellent, good, fair, poor, info

        public var label: String {
            switch self {
            case .excellent: return "Excelente"
            case .good: return "Buena"
            case .fair: return "Mejorable"
            case .poor: return "A trabajar"
            case .info: return ""
            }
        }
    }

    public var metric: Metric
    public var value: Double
    public var rating: Rating
    public var note: String
    public var id: String { metric.rawValue }
}

/// Apple Watch frente a Fitbit Air en la misma carrera.
public struct SourceComparison: Codable, Sendable, Hashable {
    public var watchDistanceM: Double?
    public var fitbitDistanceM: Double?
    public var watchAvgHR: Double?
    public var fitbitAvgHR: Double?
    /// Media de (Watch − Fitbit) y límites de concordancia al 95 % en los segundos que tienen las dos.
    public var hrBias: Double?
    public var hrLoaLow: Double?
    public var hrLoaHigh: Double?
    public var overlapMinutes: Double?
    public var watchCadence: Double?
    public var fitbitCadence: Double?
    public var watchCalories: Double?
    public var fitbitCalories: Double?
    public var fitbitVO2max: Double?
    public var fitbitActiveZoneMinutes: Double?
    public var fitbitZoneSeconds: [String: Double]?
}

/// Un punto de las gráficas (≈ 400 por carrera).
public struct ChartPoint: Codable, Sendable, Hashable {
    public var t: Double
    public var km: Double
    /// Segundos por km (solo en movimiento).
    public var pace: Double?
    public var gap: Double?
    public var hr: Double?
    public var hrWatch: Double?
    public var hrFitbit: Double?
    public var altitude: Double?
    public var cadence: Double?
    public var power: Double?
    public var stride: Double?
    public var verticalOsc: Double?
    public var groundContact: Double?
}

/// Análisis completo de una carrera (doc. 18 §4).
public struct RunAnalysis: Codable, Sendable, Hashable {
    public var activityID: String
    public var distanceM: Double
    public var elapsedS: Double
    public var movingS: Double
    public var pausedS: Double
    public var pauses: Int
    public var avgSpeed: Double?
    public var avgGAPSpeed: Double?
    public var maxSpeed: Double?
    public var avgHR: Double?
    public var maxHR: Double?
    public var avgCadence: Double?
    public var maxCadence: Double?
    public var avgPower: Double?
    public var maxPower: Double?
    public var avgStride: Double?
    public var avgVerticalOsc: Double?
    public var avgGroundContact: Double?
    public var verticalRatioPct: Double?
    public var elevationGainM: Double?
    public var elevationLossM: Double?
    public var minAltitude: Double?
    public var maxAltitude: Double?
    public var caloriesKcal: Double?
    public var steps: Int?
    /// TRIMP de Banister.
    public var trimp: Double?
    /// Estrés de la carrera (rTSS) e intensidad respecto al umbral.
    public var stressScore: Double?
    public var intensityFactor: Double?
    public var vo2maxEstimate: Double?
    /// Eficiencia: metros por minuto (ajustados por pendiente) por cada latido.
    public var efficiencyFactor: Double?
    /// Desacoplamiento aeróbico (Pa:FC) entre la primera y la segunda mitad, %.
    public var decouplingPct: Double?
    /// Deriva cardiaca entre mitades, %.
    public var hrDriftPct: Double?
    /// Segundos en Z0…Z5 de FC.
    public var hrZoneSeconds: [Double]
    /// Segundos en recuperación, E, M, T, I y R (con VDOT).
    public var paceZoneSeconds: [Double]?
    /// Segundos en las 5 zonas de potencia (con potencia crítica).
    public var powerZoneSeconds: [Double]?
    public var splits: [RunSplit]
    public var laps: [RunLap]
    public var bestEfforts: [BestEffort]
    public var paceCurve: [CurvePoint]
    public var hrCurve: [CurvePoint]
    public var powerCurve: [CurvePoint]
    public var climbs: [Climb]
    public var form: [FormMetric]
    public var comparison: SourceComparison?
    public var weather: WeatherInfo?
    public var distanceSource: DistanceSource
    public var hrSource: DataSourceKind?
    public var chart: [ChartPoint]

    public var avgPace: Double? { avgSpeed.flatMap { $0 > 0.3 ? 1000 / $0 : nil } }
    public var avgGAP: Double? { avgGAPSpeed.flatMap { $0 > 0.3 ? 1000 / $0 : nil } }
    public var hasPower: Bool { avgPower != nil }
    public var hasDynamics: Bool { avgStride != nil || avgVerticalOsc != nil || avgGroundContact != nil }
    public var hasAltitude: Bool { chart.contains { $0.altitude != nil } }
}

public enum RunAnalyzer {
    public static func analyze(_ input: RunInput, context: RunContext = RunContext()) -> RunAnalysis {
        let s = RunSeriesBuilder.build(input)
        return analyze(series: s, input: input, context: context)
    }

    public static func analyze(series s: RunSeries, input: RunInput, context: RunContext) -> RunAnalysis {
        let a = input.activity
        let n = s.count
        let step = s.step
        let movingIdx = (0..<n).filter { s.moving[$0] }
        let movingS = Double(movingIdx.count) * step
        let distance = s.distance.last ?? 0
        let pausedS = Double(s.paused.filter { $0 }.count) * step
        let pauseCount = ((input.watchDetail?.events ?? []) + (input.fitbitDetail?.events ?? [])).filter { $0.kind == .pause }.count

        func mean(_ xs: [Double?], _ indices: [Int]) -> Double? { Stats.mean(indices.compactMap { xs[$0] }) }
        let avgSpeed = movingS > 0 && distance > 0 ? distance / movingS : nil
        let avgGAP = movingIdx.isEmpty || s.distanceSource == .none ? nil : Stats.mean(movingIdx.map { s.gapSpeed[$0] })
        let maxSpeed = movingIdx.map { s.speed[$0] }.max().flatMap { $0 > 0 ? $0 : nil }
        let active = (0..<n).filter { !s.paused[$0] }
        let avgHR = mean(s.hr, active)
        let maxHR = s.hr.compactMap { $0 }.max()
        let avgStride = mean(s.stride, movingIdx)
        let avgVO = mean(s.verticalOsc, movingIdx)
        var verticalRatio: Double?
        if let vo = avgVO, let st = avgStride, st > 0.3 { verticalRatio = vo / st }
        verticalRatio = verticalRatio ?? input.fitbitDetail?.verticalRatioPct

        // Desnivel: el del reloj si lo da; si no, el de la altitud suavizada.
        let (gain, loss) = elevation(s.altitude, from: 0, to: n, threshold: 3)
        let hasAlt = s.altitude.contains { $0 != nil }
        let elevationGain = a.watchMember?.elevationGainM ?? (hasAlt ? gain : a.fitbitMember?.elevationGainM)
        let elevationLoss = input.watchDetail?.elevationLossM ?? (hasAlt ? loss : nil)

        // Carga: TRIMP de Banister segundo a segundo, estrés rTSS e intensidad.
        let params = AlgorithmParams.default
        var trimp = 0.0
        var hrSeconds = 0.0
        for i in active { if let h = s.hr[i] { trimp += StrainCalculator.impulse(bpm: h, zones: input.zones, sex: input.sex, params: params) / 60 * step; hrSeconds += step } }
        var intensity: Double?
        var stress: Double?
        if let threshold = context.thresholdSpeed, threshold > 0, let g = avgGAP, movingS > 60 {
            intensity = g / threshold
            stress = movingS / 3600 * pow(g / threshold, 2) * 100
        }

        // VO₂ máx. estimado, eficiencia, desacoplamiento y deriva.
        let hrCoverage = movingS > 0 ? Double(movingIdx.filter { s.hr[$0] != nil }.count) * step / movingS : 0
        let movingHR = mean(s.hr, movingIdx)
        var vo2: Double?
        if movingS >= 720, hrCoverage >= 0.7, let g = avgGAP, let h = movingHR {
            vo2 = RunPhysiology.estimatedVO2max(avgSpeed: g, avgHR: h, hrMax: input.zones.hrMax)
        }
        var ef: Double?
        if let g = avgGAP, let h = movingHR, h > 0, hrCoverage >= 0.5 { ef = g * 60 / h }
        var decoupling: Double?
        var drift: Double?
        if movingS >= 1200, hrCoverage >= 0.7, let lastActive = s.activeT.last {
            let mid = lastActive / 2
            let first = movingIdx.filter { s.activeT[$0] < mid && s.hr[$0] != nil }
            let second = movingIdx.filter { s.activeT[$0] >= mid && s.hr[$0] != nil }
            if let g1 = Stats.mean(first.map { s.gapSpeed[$0] }), let g2 = Stats.mean(second.map { s.gapSpeed[$0] }),
               let h1 = mean(s.hr, first), let h2 = mean(s.hr, second), h1 > 0, h2 > 0, g1 > 0 {
                let ef1 = g1 / h1, ef2 = g2 / h2
                decoupling = (ef1 - ef2) / ef1 * 100
                drift = (h2 - h1) / h1 * 100
            }
        }

        // Zonas.
        var hrZones = [Double](repeating: 0, count: 6)
        for i in active { if let h = s.hr[i] { hrZones[input.zones.zone(of: h)] += step } }
        var paceZones: [Double]?
        if let vdot = context.vdot, s.distanceSource != .average, s.distanceSource != .none {
            let bounds = RunPhysiology.paceZoneBounds(vdot: vdot)
            var z = [Double](repeating: 0, count: 6)
            for i in movingIdx {
                let v = s.gapSpeed[i]
                z[bounds.filter { v >= $0 }.count] += step
            }
            paceZones = z
        }
        var powerZones: [Double]?
        if let cp = context.criticalPower, cp > 0, s.power.contains(where: { $0 != nil }) {
            let bounds = [0.80, 0.90, 1.00, 1.15].map { $0 * cp }
            var z = [Double](repeating: 0, count: 5)
            for i in movingIdx { if let p = s.power[i] { z[bounds.filter { p >= $0 }.count] += step } }
            powerZones = z
        }

        let usableDistance = s.distanceSource != .average && s.distanceSource != .none
        let analysis = RunAnalysis(
            activityID: a.id, distanceM: distance, elapsedS: a.end.timeIntervalSince(a.start), movingS: movingS, pausedS: pausedS,
            pauses: pauseCount, avgSpeed: avgSpeed, avgGAPSpeed: avgGAP, maxSpeed: maxSpeed, avgHR: avgHR, maxHR: maxHR,
            avgCadence: mean(s.cadence, movingIdx), maxCadence: s.cadence.compactMap { $0 }.max(),
            avgPower: mean(s.power, movingIdx), maxPower: s.power.compactMap { $0 }.max(), avgStride: avgStride,
            avgVerticalOsc: avgVO, avgGroundContact: mean(s.groundContact, movingIdx), verticalRatioPct: verticalRatio,
            elevationGainM: elevationGain, elevationLossM: elevationLoss,
            minAltitude: s.altitude.compactMap { $0 }.min(), maxAltitude: s.altitude.compactMap { $0 }.max(),
            caloriesKcal: a.caloriesKcal, steps: a.watchMember?.steps ?? a.fitbitMember?.steps,
            trimp: hrSeconds > 60 ? trimp : nil, stressScore: stress, intensityFactor: intensity, vo2maxEstimate: vo2,
            efficiencyFactor: ef, decouplingPct: decoupling, hrDriftPct: drift, hrZoneSeconds: hrZones, paceZoneSeconds: paceZones,
            powerZoneSeconds: powerZones, splits: usableDistance ? splits(s) : [], laps: laps(s, input: input),
            bestEfforts: usableDistance ? bestEfforts(s) : [], paceCurve: usableDistance ? paceCurve(s) : [],
            hrCurve: averageCurve(s.hr, step: step, durations: [60, 300, 600, 1200, 1800, 3600]),
            powerCurve: averageCurve(s.power, step: step, durations: [5, 15, 30, 60, 120, 300, 600, 1200, 1800, 3600]),
            climbs: hasAlt && usableDistance ? climbs(s) : [], form: [], comparison: comparison(s, input: input),
            weather: input.watchDetail?.weather, distanceSource: s.distanceSource, hrSource: s.hrSource, chart: chart(s))
        var result = analysis
        result.form = form(result, weightKg: input.weightKg)
        return result
    }

    // MARK: Desnivel

    /// Subida y bajada acumuladas con histéresis (ignora el ruido por debajo de `threshold` metros).
    static func elevation(_ alt: [Double?], from: Int, to: Int, threshold: Double) -> (gain: Double, loss: Double) {
        var gain = 0.0, loss = 0.0
        var ref: Double?
        for i in from..<to {
            guard let a = alt[i] else { continue }
            guard let r = ref else { ref = a; continue }
            if a - r >= threshold { gain += a - r; ref = a } else if r - a >= threshold { loss += r - a; ref = a }
        }
        return (gain, loss)
    }

    // MARK: Parciales por km

    static func splits(_ s: RunSeries) -> [RunSplit] {
        let n = s.count
        guard n > 2, let total = s.distance.last, total >= 100 else { return [] }
        var out: [RunSplit] = []
        var startIdx = 0
        var startT = 0.0
        var boundary = 1000.0
        func make(_ index: Int, _ from: Int, _ to: Int, seconds: Double, meters: Double) -> RunSplit {
            let range = Array(from..<max(from + 1, to))
            let moving = range.filter { s.moving[$0] }
            let (g, l) = elevation(s.altitude, from: from, to: max(from + 1, to), threshold: 1)
            var grade: Double?
            if let a0 = s.altitude[from], let a1 = s.altitude[max(from, to - 1)], meters > 0 { grade = (a1 - a0) / meters * 100 }
            let gapSpeed = Stats.mean(moving.map { s.gapSpeed[$0] })
            let speed = Stats.mean(moving.map { s.speed[$0] })
            var gapSeconds: Double?
            if let gs = gapSpeed, let sp = speed, gs > 0, sp > 0 { gapSeconds = seconds * sp / gs }
            return RunSplit(index: index, distanceM: meters, seconds: seconds, gapSeconds: gapSeconds,
                            avgHR: Stats.mean(moving.compactMap { s.hr[$0] }), maxHR: range.compactMap { s.hr[$0] }.max(),
                            cadence: Stats.mean(moving.compactMap { s.cadence[$0] }), power: Stats.mean(moving.compactMap { s.power[$0] }),
                            stride: Stats.mean(moving.compactMap { s.stride[$0] }), elevationGainM: g, elevationLossM: l, avgGradePct: grade)
        }
        for i in 1..<n {
            while s.distance[i] >= boundary {
                let d0 = s.distance[i - 1], d1 = s.distance[i]
                let f = d1 > d0 ? (boundary - d0) / (d1 - d0) : 1
                let tCross = s.activeT[i - 1] + Stats.clip(f, 0, 1) * (s.activeT[i] - s.activeT[i - 1])
                out.append(make(out.count + 1, startIdx, i, seconds: tCross - startT, meters: 1000))
                startIdx = i
                startT = tCross
                boundary += 1000
            }
        }
        let remainder = total - (boundary - 1000)
        if remainder >= 100, let lastT = s.activeT.last {
            out.append(make(out.count + 1, startIdx, n, seconds: lastT - startT, meters: remainder))
        }
        return out.filter { $0.seconds > 0 }
    }

    // MARK: Vueltas e intervalos

    static func laps(_ s: RunSeries, input: RunInput) -> [RunLap] {
        let start = input.activity.start
        let watch = input.watchDetail
        var raw: [(start: Date, end: Date, kind: String, source: DataSourceKind, distance: Double?, hr: Double?)] = []
        if let w = watch, !w.laps.isEmpty {
            raw = w.laps.map { ($0.start, $0.end, $0.kind, .appleHealth, $0.distanceM, $0.avgHR) }
        } else if let w = watch, w.events.contains(where: { $0.kind == .lap }) {
            raw = w.events.filter { $0.kind == .lap }.map { ($0.start, $0.end, "lap", .appleHealth, nil, nil) }
        } else if let w = watch, w.events.contains(where: { $0.kind == .segment }) {
            raw = w.events.filter { $0.kind == .segment }.map { ($0.start, $0.end, "segment", .appleHealth, nil, nil) }
        } else if let f = input.fitbitDetail, f.laps.count > 1 {
            raw = f.laps.map { ($0.start, $0.end, $0.kind, .googleHealth, $0.distanceM, $0.avgHR) }
        }
        guard raw.count > 1 else { return [] }
        return raw.sorted { $0.start < $1.start }.enumerated().map { k, r in
            let lo = s.index(at: r.start), hi = max(s.index(at: r.end), lo + 1)
            let range = Array(lo..<min(hi, s.count))
            let moving = range.filter { s.moving[$0] }
            let seriesDistance = hi - 1 < s.count ? s.distance[min(hi, s.count - 1)] - s.distance[lo] : nil
            let seconds = s.activeT[min(hi, s.count - 1)] - s.activeT[lo]
            let useSeries = s.distanceSource != .average && s.distanceSource != .none
            return RunLap(index: k + 1, kind: r.kind, source: r.source, startS: r.start.timeIntervalSince(start),
                          endS: r.end.timeIntervalSince(start), distanceM: r.distance ?? (useSeries ? seriesDistance : nil),
                          seconds: seconds > 0 ? seconds : r.end.timeIntervalSince(r.start),
                          avgHR: Stats.mean(range.compactMap { s.hr[$0] }) ?? r.hr, maxHR: range.compactMap { s.hr[$0] }.max(),
                          cadence: Stats.mean(moving.compactMap { s.cadence[$0] }), power: Stats.mean(moving.compactMap { s.power[$0] }))
        }
    }

    // MARK: Mejores marcas y curvas

    static func bestEfforts(_ s: RunSeries) -> [BestEffort] {
        guard let total = s.distance.last else { return [] }
        return RaceDistance.allCases.filter { $0.rawValue <= total }.compactMap { d in
            bestEffort(meters: d.rawValue, distance: s.distance, time: s.activeT).map { BestEffort(distance: d, seconds: $0.seconds, startS: $0.start) }
        }
    }

    /// Tramo más rápido de `meters` metros (tiempo activo, interpolando el punto exacto de inicio).
    static func bestEffort(meters target: Double, distance d: [Double], time at: [Double]) -> (seconds: Double, start: Double)? {
        guard let last = d.last, let first = d.first, last - first >= target else { return nil }
        var best = Double.infinity
        var bestStart = 0.0
        var i = 0
        for j in 0..<d.count where d[j] - first >= target {
            while i + 1 < j && d[j] - d[i + 1] >= target { i += 1 }
            let want = d[j] - target
            var startT = at[i]
            if i + 1 <= j, d[i + 1] > d[i] {
                startT = at[i] + Stats.clip((want - d[i]) / (d[i + 1] - d[i]), 0, 1) * (at[i + 1] - at[i])
            }
            let secs = at[j] - startT
            if secs > 0, secs < best { best = secs; bestStart = startT }
        }
        // Una marca imposible (más de 10 m/s) es un salto de GPS.
        guard best.isFinite, target / best <= 10 else { return nil }
        return (best, bestStart)
    }

    /// Mejor velocidad media para cada duración (curva de ritmo).
    static func paceCurve(_ s: RunSeries) -> [CurvePoint] {
        let d = s.distance, at = s.activeT
        guard let total = at.last else { return [] }
        return [60.0, 300, 600, 1200, 1800, 3600, 5400, 7200].filter { $0 <= total }.compactMap { dur in
            var best = 0.0
            var i = 0
            for j in 0..<at.count where at[j] - at[0] >= dur {
                while i + 1 < j && at[j] - at[i + 1] >= dur { i += 1 }
                let want = at[j] - dur
                var d0 = d[i]
                if i + 1 <= j, at[i + 1] > at[i] { d0 = d[i] + Stats.clip((want - at[i]) / (at[i + 1] - at[i]), 0, 1) * (d[i + 1] - d[i]) }
                best = max(best, (d[j] - d0) / dur)
            }
            return best > 0 && best <= 10 ? CurvePoint(seconds: dur, value: best) : nil
        }
    }

    /// Mejor media de una serie (FC o potencia) para cada duración, con al menos el 80 % de datos en la ventana.
    static func averageCurve(_ xs: [Double?], step: Double, durations: [Double]) -> [CurvePoint] {
        let n = xs.count
        var sum = [Double](repeating: 0, count: n + 1)
        var cnt = [Int](repeating: 0, count: n + 1)
        for i in 0..<n {
            sum[i + 1] = sum[i] + (xs[i] ?? 0)
            cnt[i + 1] = cnt[i] + (xs[i] == nil ? 0 : 1)
        }
        guard cnt[n] > 0 else { return [] }
        return durations.compactMap { dur in
            let w = max(1, Int((dur / step).rounded()))
            guard w <= n else { return nil }
            var best: Double?
            for i in 0...(n - w) {
                let c = cnt[i + w] - cnt[i]
                guard Double(c) >= 0.8 * Double(w) else { continue }
                let v = (sum[i + w] - sum[i]) / Double(c)
                if v > (best ?? -1) { best = v }
            }
            return best.map { CurvePoint(seconds: dur, value: $0) }
        }
    }

    // MARK: Subidas

    static func climbs(_ s: RunSeries) -> [Climb] {
        // Extremos con histéresis de 3 m y, de cada valle a su cima, una subida si merece la pena.
        var extremes: [(Int, Double)] = []
        var candidate: (Int, Double)?
        var trend = 0
        for i in 0..<s.count {
            guard let a = s.altitude[i] else { continue }
            guard let c = candidate else { candidate = (i, a); extremes.append((i, a)); continue }
            if trend >= 0 {
                if a > c.1 { candidate = (i, a) } else if c.1 - a >= 3 { extremes.append(c); trend = -1; candidate = (i, a); continue }
            }
            if trend <= 0 {
                if a < c.1 { candidate = (i, a) } else if a - c.1 >= 3 { extremes.append(c); trend = 1; candidate = (i, a) }
            }
        }
        if let c = candidate { extremes.append(c) }
        var out: [Climb] = []
        for k in 1..<max(1, extremes.count) {
            var (v, va) = extremes[k - 1]
            var (p, pa) = extremes[k]
            guard pa > va else { continue }
            // La subida empieza donde la altitud deja el llano del valle y acaba donde llega a la cima.
            let base = va, top = pa
            while v + 1 < p, let next = s.altitude[v + 1], next <= base + 1 { v += 1; va = next }
            while p - 1 > v, let prev = s.altitude[p - 1], prev >= top - 1 { p -= 1; pa = prev }
            let gain = pa - va
            let length = s.distance[p] - s.distance[v]
            guard gain >= 15, length >= 150, gain / length >= 0.03 else { continue }
            let seconds = s.activeT[p] - s.activeT[v]
            out.append(Climb(index: out.count + 1, startKm: s.distance[v] / 1000, lengthM: length, gainM: gain,
                             avgGradePct: gain / length * 100, seconds: seconds, vam: seconds > 0 ? gain / seconds * 3600 : 0))
        }
        return out
    }

    // MARK: Técnica

    static func form(_ r: RunAnalysis, weightKg: Double?) -> [FormMetric] {
        var out: [FormMetric] = []
        if let c = r.avgCadence {
            let rating: FormMetric.Rating = c >= 170 && c <= 192 ? .good : (c >= 162 ? .fair : (c > 192 ? .good : .poor))
            out.append(FormMetric(metric: .cadence, value: c, rating: rating,
                                  note: c < 170 ? "Más pasos cortos (5–10 % más de cadencia) reducen el impacto." : "Buena frecuencia de paso."))
        }
        if let g = r.avgGroundContact {
            let rating: FormMetric.Rating = g < 240 ? .excellent : (g < 260 ? .good : (g < 290 ? .fair : .poor))
            out.append(FormMetric(metric: .groundContact, value: g, rating: rating,
                                  note: g < 260 ? "Pies ligeros: poco tiempo en el suelo." : "Un contacto largo suele venir de pisar por delante del cuerpo."))
        }
        if let v = r.avgVerticalOsc {
            let rating: FormMetric.Rating = v < 6.5 ? .excellent : (v < 8.5 ? .good : (v < 10.5 ? .fair : .poor))
            out.append(FormMetric(metric: .verticalOsc, value: v, rating: rating,
                                  note: v < 8.5 ? "Rebotas poco: la energía va hacia delante." : "Rebotas bastante: gastas energía subiendo y bajando."))
        }
        if let vr = r.verticalRatioPct {
            let rating: FormMetric.Rating = vr < 6.1 ? .excellent : (vr < 7.5 ? .good : (vr < 8.7 ? .fair : .poor))
            out.append(FormMetric(metric: .verticalRatio, value: vr, rating: rating,
                                  note: "Oscilación entre zancada: cuanto más bajo, más económica la zancada."))
        }
        if let st = r.avgStride {
            out.append(FormMetric(metric: .stride, value: st, rating: .info, note: "Crece con el ritmo; compárala con tus carreras parecidas."))
        }
        if let p = r.avgPower {
            let perKg = weightKg.map { p / $0 }
            out.append(FormMetric(metric: .power, value: p, rating: .info,
                                  note: perKg.map { "\(String(format: "%.2f", $0)) W/kg" } ?? "Potencia media en movimiento."))
        }
        return out
    }

    // MARK: Apple Watch frente a Fitbit Air

    static func comparison(_ s: RunSeries, input: RunInput) -> SourceComparison? {
        let a = input.activity
        guard let w = a.watchMember, let f = a.fitbitMember else { return nil }
        var c = SourceComparison()
        c.watchDistanceM = w.distanceM
        c.fitbitDistanceM = f.distanceM
        c.watchAvgHR = Stats.mean(s.hrWatch.compactMap { $0 }) ?? w.avgHR
        c.fitbitAvgHR = Stats.mean(s.hrFitbit.compactMap { $0 }) ?? f.avgHR
        let pairs = (0..<s.count).compactMap { i -> Double? in
            guard let x = s.hrWatch[i], let y = s.hrFitbit[i] else { return nil }
            return x - y
        }
        if pairs.count >= 60, let bias = Stats.mean(pairs) {
            let sd = (pairs.reduce(0) { $0 + ($1 - bias) * ($1 - bias) } / Double(pairs.count - 1)).squareRoot()
            c.hrBias = bias
            c.hrLoaLow = bias - 1.96 * sd
            c.hrLoaHigh = bias + 1.96 * sd
            c.overlapMinutes = Double(pairs.count) * s.step / 60
        }
        c.watchCadence = w.dynamics?.avgCadenceSpm
        c.fitbitCadence = input.fitbitDetail?.mobility?.avgCadenceSpm
        c.watchCalories = w.caloriesKcal
        c.fitbitCalories = f.caloriesKcal
        c.fitbitVO2max = input.fitbitDetail?.vo2max
        c.fitbitActiveZoneMinutes = input.fitbitDetail?.activeZoneMinutes
        c.fitbitZoneSeconds = input.fitbitDetail?.zoneSeconds
        return c
    }

    // MARK: Gráficas

    static func chart(_ s: RunSeries, maxPoints: Int = 400) -> [ChartPoint] {
        let n = s.count
        guard n > 0 else { return [] }
        let bucket = max(1, Int((Double(n) / Double(maxPoints)).rounded(.up)))
        var out: [ChartPoint] = []
        var i = 0
        while i < n {
            let range = Array(i..<min(n, i + bucket))
            let moving = range.filter { s.moving[$0] }
            func avg(_ xs: [Double?], _ r: [Int]) -> Double? { Stats.mean(r.compactMap { xs[$0] }) }
            let v = Stats.mean(moving.map { s.speed[$0] })
            let g = Stats.mean(moving.map { s.gapSpeed[$0] })
            func pace(_ x: Double?) -> Double? { x.flatMap { $0 >= 1 ? min(1200, 1000 / $0) : nil } }
            let usable = s.distanceSource != .none && s.distanceSource != .average
            let last = range[range.count - 1]
            out.append(ChartPoint(t: s.activeT[last], km: s.distance[last] / 1000, pace: usable ? pace(v) : nil, gap: usable ? pace(g) : nil,
                                  hr: avg(s.hr, range), hrWatch: avg(s.hrWatch, range), hrFitbit: avg(s.hrFitbit, range),
                                  altitude: avg(s.altitude, range), cadence: avg(s.cadence, moving), power: avg(s.power, moving),
                                  stride: avg(s.stride, moving), verticalOsc: avg(s.verticalOsc, moving), groundContact: avg(s.groundContact, moving)))
            i += bucket
        }
        return out
    }
}
