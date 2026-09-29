import Foundation

// MARK: - ALG-BAS-01 · Líneas base

public enum BaselineMetric: String, Codable, Sendable, CaseIterable {
    case lnRmssd = "ln_rmssd"
    case restingHR = "rhr"
    case respiratoryRate = "resp_rate"
    case skinTemp = "skin_temp"
    case spo2

    func floor(_ p: AlgorithmParams.SDFloor) -> Double {
        switch self {
        case .lnRmssd: return p.lnRmssd
        case .restingHR: return p.rhr
        case .respiratoryRate: return p.respRate
        case .skinTemp: return p.skinTemp
        case .spo2: return p.spo2
        }
    }
}

public struct BaselineStats: Hashable, Codable, Sendable {
    public var median: Double
    public var sigma: Double
    public var n: Int

    public init(median: Double, sigma: Double, n: Int) {
        self.median = median
        self.sigma = sigma
        self.n = n
    }

    public func z(_ value: Double) -> Double { (value - median) / sigma }
}

/// Valores de una noche válida para las líneas base.
public struct NightValues: Hashable, Codable, Sendable {
    public var date: LocalDate
    public var lnRmssd: Double?
    public var restingHR: Double?
    public var respiratoryRate: Double?
    public var skinTemp: Double?
    public var spo2: Double?
    public var valid: Bool

    public init(date: LocalDate, lnRmssd: Double?, restingHR: Double?, respiratoryRate: Double?, skinTemp: Double?,
                spo2: Double?, valid: Bool) {
        self.date = date
        self.lnRmssd = lnRmssd
        self.restingHR = restingHR
        self.respiratoryRate = respiratoryRate
        self.skinTemp = skinTemp
        self.spo2 = spo2
        self.valid = valid
    }

    public func value(_ m: BaselineMetric) -> Double? {
        switch m {
        case .lnRmssd: return lnRmssd
        case .restingHR: return restingHR
        case .respiratoryRate: return respiratoryRate
        case .skinTemp: return skinTemp
        case .spo2: return spo2
        }
    }
}

public enum Baselines {
    /// RMSSD de la noche: el de sueño profundo si hay ≥ 20 min de profundo; si no, la media (parámetro `hrv_source`).
    public static func nightlyRMSSD(vitals: NightlyVitals, deepMinutes: Double, params: AlgorithmParams) -> Double? {
        if params.baseline.hrvSource == "deep_if_min_20_else_avg", deepMinutes >= 20, let d = vitals.hrvRmssdDeep, d > 0 {
            return d
        }
        if params.baseline.hrvSource == "deep", let d = vitals.hrvRmssdDeep, d > 0 { return d }
        if let a = vitals.hrvRmssdAvg, a > 0 { return a }
        return vitals.hrvRmssdDeep.flatMap { $0 > 0 ? $0 : nil }
    }

    /// Estadísticos robustos de la ventana de `window` noches válidas anteriores a `date` (sin incluirla).
    public static func stats(for metric: BaselineMetric, before date: LocalDate, nights: [NightValues], window: Int,
                             params: AlgorithmParams) -> BaselineStats? {
        let values = nights
            .filter { $0.valid && $0.date < date }
            .sorted { $0.date > $1.date }
            .compactMap { $0.value(metric) }
            .prefix(window)
        let xs = Array(values)
        guard !xs.isEmpty, let med = Stats.median(xs) else { return nil }
        let sigma = max(Stats.robustSigma(xs) ?? 0, metric.floor(params.baseline.sdFloor))
        return BaselineStats(median: med, sigma: sigma, n: xs.count)
    }

    /// Media móvil de 7 noches de lnRMSSD y su coeficiente de variación (exige ≥ 4 noches).
    public static func weeklyHRVTrend(until date: LocalDate, nights: [NightValues]) -> (mean: Double, cv: Double)? {
        let xs = nights.filter { $0.valid && $0.date <= date && $0.date > date.adding(days: -7) }.compactMap(\.lnRmssd)
        guard xs.count >= 4, let m = Stats.mean(xs), let s = Stats.sd(xs), m != 0 else { return nil }
        return (m, 100 * s / m)
    }
}

// MARK: - ALG-REC-01 · Recuperación

public enum RecoveryZone: String, Codable, Sendable {
    case high, medium, low

    public var label: String {
        switch self {
        case .high: return "Alta"
        case .medium: return "Media"
        case .low: return "Baja"
        }
    }
}

public struct RecoveryComponent: Hashable, Codable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case hrv, restingHR, sleep, respiratoryRate, skinTemp, spo2
    }

    public var kind: Kind
    public var z: Double
    public var weight: Double
    public var contribution: Double
    public var value: Double?
    public var baseline: Double?
    public var id: String { kind.rawValue }

    public init(kind: Kind, z: Double, weight: Double, value: Double?, baseline: Double?) {
        self.kind = kind
        self.z = z
        self.weight = weight
        self.contribution = z * weight
        self.value = value
        self.baseline = baseline
    }
}

public enum ScoreStatus: Codable, Sendable, Hashable {
    case ok
    case calibrating(nights: Int, needed: Int)
    case insufficient(reason: String)
}

public struct RecoveryResult: Hashable, Codable, Sendable {
    public var score: Int?
    public var zone: RecoveryZone?
    public var confidence: Confidence
    public var components: [RecoveryComponent]
    public var baselineNights: Int
    public var status: ScoreStatus
    public var composite: Double?

    public static func insufficient(_ reason: String, nights: Int) -> RecoveryResult {
        RecoveryResult(score: nil, zone: nil, confidence: .low, components: [], baselineNights: nights,
                       status: .insufficient(reason: reason), composite: nil)
    }
}

public struct RecoveryInput: Sendable {
    public var date: LocalDate
    public var rmssd: Double?
    public var restingHR: Double?
    public var sleepSufficiency: Double?
    public var respiratoryRate: Double?
    public var skinTemp: Double?
    public var spo2: Double?
    public var nightCoverage: Double
    public var minutesAsleep: Double

    public init(date: LocalDate, rmssd: Double?, restingHR: Double?, sleepSufficiency: Double?, respiratoryRate: Double?,
                skinTemp: Double?, spo2: Double?, nightCoverage: Double, minutesAsleep: Double) {
        self.date = date
        self.rmssd = rmssd
        self.restingHR = restingHR
        self.sleepSufficiency = sleepSufficiency
        self.respiratoryRate = respiratoryRate
        self.skinTemp = skinTemp
        self.spo2 = spo2
        self.nightCoverage = nightCoverage
        self.minutesAsleep = minutesAsleep
    }
}

public enum RecoveryCalculator {
    public static func compute(_ input: RecoveryInput, nights: [NightValues], history: [RecoveryHistoryPoint],
                               params: AlgorithmParams) -> RecoveryResult {
        let p = params.recovery
        let bp = params.baseline
        guard let rmssd = input.rmssd, rmssd > 0 else {
            let n = nights.filter { $0.valid && $0.date < input.date }.count
            return .insufficient("No hay variabilidad cardiaca de esta noche", nights: n)
        }
        let hrvBase = Baselines.stats(for: .lnRmssd, before: input.date, nights: nights, window: bp.shortWindow, params: params)
        let n = hrvBase?.n ?? 0
        guard let hrvBase, n >= bp.minNights else {
            return RecoveryResult(score: nil, zone: nil, confidence: .low, components: [], baselineNights: n,
                                  status: .calibrating(nights: n, needed: bp.minNights), composite: nil)
        }

        var components: [RecoveryComponent] = []
        let lnR = log(rmssd)
        let zHRV = Stats.clip(hrvBase.z(lnR), -3, p.hrvZCapHigh)
        components.append(RecoveryComponent(kind: .hrv, z: zHRV, weight: p.wHrv, value: rmssd, baseline: exp(hrvBase.median)))

        var wHRV = p.wHrv, wRHR = p.wRhr, wSleep = p.wSleep
        var confidence: Confidence = n >= bp.fullNights ? .high : .medium

        var zRHR: Double?
        if let rhr = input.restingHR,
           let b = Baselines.stats(for: .restingHR, before: input.date, nights: nights, window: bp.shortWindow, params: params) {
            zRHR = Stats.clip(-b.z(rhr), -3, 3)
            components.append(RecoveryComponent(kind: .restingHR, z: zRHR!, weight: wRHR, value: rhr, baseline: b.median))
        } else {
            // Sin FCR, su peso pasa a la HRV y baja la confianza.
            wHRV += wRHR
            wRHR = 0
            confidence = confidence.lowered
        }

        var zSleep: Double?
        if let sp = input.sleepSufficiency {
            zSleep = Stats.clip((sp - p.sleepAnchor) / p.sleepScale, -3, 1.5)
            components.append(RecoveryComponent(kind: .sleep, z: zSleep!, weight: wSleep, value: sp, baseline: p.sleepAnchor))
        } else {
            // Sin sueño, su peso se reparte entre HRV y FCR.
            let total = wHRV + wRHR
            if total > 0 {
                wHRV += wSleep * wHRV / total
                wRHR += wSleep * wRHR / total
            }
            wSleep = 0
            confidence = confidence.lowered
        }
        // Actualiza los pesos efectivos de los componentes principales.
        for i in components.indices {
            switch components[i].kind {
            case .hrv: components[i] = RecoveryComponent(kind: .hrv, z: zHRV, weight: wHRV, value: rmssd, baseline: exp(hrvBase.median))
            case .restingHR: components[i].weight = wRHR; components[i].contribution = components[i].z * wRHR
            case .sleep: components[i].weight = wSleep; components[i].contribution = components[i].z * wSleep
            default: break
            }
        }

        // Penalizaciones: solo restan.
        var penalty = 0.0
        var missingSecondary = false
        if let rr = input.respiratoryRate,
           let b = Baselines.stats(for: .respiratoryRate, before: input.date, nights: nights, window: bp.shortWindow, params: params) {
            let z = -Stats.clip(b.z(rr), 0, 3)
            penalty += z
            components.append(RecoveryComponent(kind: .respiratoryRate, z: z, weight: p.wPenalties, value: rr, baseline: b.median))
        } else { missingSecondary = true }
        if let t = input.skinTemp,
           let b = Baselines.stats(for: .skinTemp, before: input.date, nights: nights, window: bp.shortWindow, params: params) {
            let z = -Stats.clip(b.z(t), 0, 3)
            penalty += z
            components.append(RecoveryComponent(kind: .skinTemp, z: z, weight: p.wPenalties, value: t, baseline: b.median))
        } else { missingSecondary = true }
        if let s = input.spo2,
           let b = Baselines.stats(for: .spo2, before: input.date, nights: nights, window: bp.shortWindow, params: params) {
            let z = -Stats.clip(-b.z(s), 0, 3)
            penalty += z
            components.append(RecoveryComponent(kind: .spo2, z: z, weight: p.wPenalties, value: s, baseline: b.median))
        } else { missingSecondary = true }
        if missingSecondary { confidence = confidence.lowered }

        let c = wHRV * zHRV + wRHR * (zRHR ?? 0) + wSleep * (zSleep ?? 0) + p.wPenalties * penalty
        let s = scale(history: history, date: input.date, weights: [p.wHrv, p.wRhr, p.wSleep], params: params)
        let score = Int((100 * Stats.normalCDF((c - p.c0) / s)).rounded())

        // Confianza por cobertura y horas dormidas.
        if input.nightCoverage < 0.5 || input.minutesAsleep < 240 {
            confidence = .low
        } else if input.nightCoverage < 0.7 {
            confidence = min(confidence, .medium)
        }
        return RecoveryResult(score: score, zone: zone(for: score, params: params), confidence: confidence,
                              components: components, baselineNights: n, status: .ok, composite: c)
    }

    public static func zone(for score: Int, params: AlgorithmParams) -> RecoveryZone {
        if Double(score) >= params.recovery.zones.high { return .high }
        if Double(score) > params.recovery.zones.low { return .medium }
        return .low
    }

    /// s = 0,8 con < 30 noches; después √(wᵀRw) con la matriz de correlación personal de los z.
    static func scale(history: [RecoveryHistoryPoint], date: LocalDate, weights: [Double], params: AlgorithmParams) -> Double {
        let prior = history.filter { $0.date < date }
        guard params.recovery.sMethod == "sqrt_wRw_after_30_nights", prior.count >= 30 else { return params.recovery.sInitial }
        let cols: [[Double]] = [prior.map(\.zHRV), prior.map(\.zRHR), prior.map(\.zSleep)]
        var r = Array(repeating: Array(repeating: 0.0, count: 3), count: 3)
        for i in 0..<3 {
            for j in 0..<3 {
                r[i][j] = i == j ? 1 : (Stats.pearson(cols[i], cols[j]) ?? 0)
            }
        }
        var v = 0.0
        for i in 0..<3 { for j in 0..<3 { v += weights[i] * r[i][j] * weights[j] } }
        let s = v.squareRoot()
        return s.isFinite && s > 0.2 ? s : params.recovery.sInitial
    }
}

/// z de los componentes principales de noches anteriores (para la escala s).
public struct RecoveryHistoryPoint: Hashable, Codable, Sendable {
    public var date: LocalDate
    public var zHRV: Double
    public var zRHR: Double
    public var zSleep: Double

    public init(date: LocalDate, zHRV: Double, zRHR: Double, zSleep: Double) {
        self.date = date
        self.zHRV = zHRV
        self.zRHR = zRHR
        self.zSleep = zSleep
    }
}
