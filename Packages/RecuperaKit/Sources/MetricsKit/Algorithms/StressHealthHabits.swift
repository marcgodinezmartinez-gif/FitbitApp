import Foundation

// MARK: - ALG-EST-01 · Estrés (FC no metabólica, «beta»)

public struct StressWindow: Hashable, Codable, Sendable {
    public var start: Int            // época (s) del inicio de la ventana de 5 min
    public var level: Double?        // 0–3; nil si no es elegible
    public var excludedReason: String?
}

public struct StressDay: Hashable, Codable, Sendable {
    public var windows: [StressWindow]
    public var average: Double?
    public var minutesLow: Int
    public var minutesMedium: Int
    public var minutesHigh: Int
    public var sustainedHigh: Bool

    public static let empty = StressDay(windows: [], average: nil, minutesLow: 0, minutesMedium: 0, minutesHigh: 0, sustainedHigh: false)
}

public enum StressCalculator {
    /// FC de calma = percentil 10 de las ventanas elegibles de los últimos 14 días.
    public static func calmHR(eligibleMedians: [Double], params: AlgorithmParams) -> Double? {
        guard eligibleMedians.count >= 12 else { return nil }
        return Stats.percentile(eligibleMedians, params.stress.calmPercentile)
    }

    /// Ventanas de 5 min de un periodo de vigilia con su mediana de FC si son elegibles.
    public static func eligibleWindows(range: TimeRange, hr: [Int: Double], steps: [Int: Int], sleep: [TimeRange],
                                       workouts: [TimeRange], params: AlgorithmParams) -> [(start: Int, median: Double?, reason: String?)] {
        let p = params.stress
        let w = p.windowMin * 60
        var out: [(Int, Double?, String?)] = []
        var t = range.start.minuteEpoch
        let end = Int(range.end.timeIntervalSince1970)
        while t + w <= end {
            let windowRange = TimeRange(start: Date(timeIntervalSince1970: TimeInterval(t)),
                                        end: Date(timeIntervalSince1970: TimeInterval(t + w)))
            var reason: String?
            if sleep.contains(where: { $0.intersects(windowRange) }) {
                reason = "sueño"
            } else if workouts.contains(where: { r in
                windowRange.start < r.end.addingTimeInterval(TimeInterval(p.postExerciseExclusionMin * 60)) && windowRange.end > r.start
            }) {
                reason = "ejercicio"
            } else {
                var moving = false
                var m = t - p.zeroStepsLookbackMin * 60
                while m < t + w {
                    if (steps[m] ?? 0) > 0 { moving = true; break }
                    m += 60
                }
                if moving { reason = "movimiento" }
            }
            if reason != nil {
                out.append((t, nil, reason))
            } else {
                var vals: [Double] = []
                var m = t
                while m < t + w {
                    if let v = hr[m], Validity.isValidBPM(v) { vals.append(v) }
                    m += 60
                }
                out.append((t, vals.count >= 3 ? Stats.median(vals) : nil, vals.count >= 3 ? nil : "sin FC"))
            }
            t += w
        }
        return out
    }

    public static func day(windows: [(start: Int, median: Double?, reason: String?)], calmHR: Double?, hrMax: Double,
                           restingRef: Double, params: AlgorithmParams) -> StressDay {
        guard let calm = calmHR else {
            return StressDay(windows: windows.map { StressWindow(start: $0.start, level: nil, excludedReason: $0.reason ?? "calibrando") },
                             average: nil, minutesLow: 0, minutesMedium: 0, minutesHigh: 0, sustainedHigh: false)
        }
        let p = params.stress
        let deltaRef = max(p.deltaRefMinBpm, p.deltaRefHrrFraction * (hrMax - restingRef))
        var out: [StressWindow] = []
        var low = 0, med = 0, high = 0
        var run = 0, sustained = false
        for w in windows {
            guard let m = w.median else {
                out.append(StressWindow(start: w.start, level: nil, excludedReason: w.reason))
                run = 0
                continue
            }
            let level = Stats.clip(3 * (m - calm) / deltaRef, 0, 3)
            out.append(StressWindow(start: w.start, level: (level * 10).rounded() / 10, excludedReason: nil))
            if level < 1 { low += p.windowMin } else if level < 2 { med += p.windowMin } else { high += p.windowMin }
            if level >= p.sustainedHigh.level {
                run += p.windowMin
                if run >= p.sustainedHigh.minutes { sustained = true }
            } else {
                run = 0
            }
        }
        let levels = out.compactMap(\.level)
        return StressDay(windows: out, average: Stats.mean(levels).map { ($0 * 10).rounded() / 10 },
                         minutesLow: low, minutesMedium: med, minutesHigh: high, sustainedHigh: sustained)
    }
}

// MARK: - ALG-SAL-01 · Monitor de salud

public enum VitalKind: String, Codable, Sendable, CaseIterable {
    case hrv, restingHR, respiratoryRate, skinTemp, spo2

    public var label: String {
        switch self {
        case .hrv: return "VFC"
        case .restingHR: return "FC en reposo"
        case .respiratoryRate: return "Frecuencia respiratoria"
        case .skinTemp: return "Temperatura"
        case .spo2: return "SpO₂"
        }
    }

    var baselineMetric: BaselineMetric {
        switch self {
        case .hrv: return .lnRmssd
        case .restingHR: return .restingHR
        case .respiratoryRate: return .respiratoryRate
        case .skinTemp: return .skinTemp
        case .spo2: return .spo2
        }
    }

    /// Dirección desfavorable: +1 si subir es malo, −1 si bajar es malo.
    var badDirection: Double {
        switch self {
        case .hrv, .spo2: return -1
        case .restingHR, .respiratoryRate, .skinTemp: return 1
        }
    }
}

public struct VitalStatus: Hashable, Codable, Sendable {
    public var kind: VitalKind
    public var value: Double
    public var rangeLow: Double
    public var rangeHigh: Double
    public var z: Double
    public var outOfRange: Bool
}

public struct HealthCheck: Hashable, Codable, Sendable {
    public var date: LocalDate
    public var vitals: [VitalStatus]
    public var signals: [String]
    public var combinedAlert: Bool
}

public enum HealthMonitor {
    public static func check(date: LocalDate, tonight: NightValues, nights: [NightValues], params: AlgorithmParams) -> HealthCheck? {
        let hp = params.healthMonitor
        let bp = params.baseline
        var vitals: [VitalStatus] = []
        for kind in VitalKind.allCases {
            guard let v = tonight.value(kind.baselineMetric),
                  let b = Baselines.stats(for: kind.baselineMetric, before: date, nights: nights, window: bp.longWindow, params: params),
                  b.n >= 14 else { continue }
            let z = b.z(v)
            let out = kind.badDirection * z > hp.zThreshold
            let lo = b.median - 2 * b.sigma, hi = b.median + 2 * b.sigma
            let display = kind == .hrv ? exp(v) : v
            let (dlo, dhi) = kind == .hrv ? (exp(lo), exp(hi)) : (lo, hi)
            vitals.append(VitalStatus(kind: kind, value: display, rangeLow: dlo, rangeHigh: dhi, z: z, outOfRange: out))
        }
        guard !vitals.isEmpty else { return nil }
        var signals: [String] = []
        // FCR ≥ 4 lpm sobre su base dos noches seguidas (NightSignal).
        if let rhrBase = Baselines.stats(for: .restingHR, before: date, nights: nights, window: bp.shortWindow, params: params),
           let tonightRHR = tonight.restingHR, tonightRHR - rhrBase.median >= hp.rhrDeltaBpm {
            let yesterday = nights.first { $0.date == date.adding(days: -1) }
            if let y = yesterday?.restingHR, y - rhrBase.median >= hp.rhrDeltaBpm { signals.append("fcr_alta_2_noches") }
        }
        if let rrBase = Baselines.stats(for: .respiratoryRate, before: date, nights: nights, window: bp.shortWindow, params: params),
           let rr = tonight.respiratoryRate, rr - rrBase.median >= hp.respRateDeltaBpm || rrBase.z(rr) >= hp.zThreshold {
            signals.append("fr_alta")
        }
        if let tBase = Baselines.stats(for: .skinTemp, before: date, nights: nights, window: bp.shortWindow, params: params),
           let t = tonight.skinTemp, tBase.z(t) >= hp.tempZHigh {
            signals.append("temperatura_alta")
        }
        if let hBase = Baselines.stats(for: .lnRmssd, before: date, nights: nights, window: bp.shortWindow, params: params),
           let h = tonight.lnRmssd, hBase.z(h) <= hp.hrvZLow {
            signals.append("vfc_baja")
        }
        return HealthCheck(date: date, vitals: vitals, signals: signals, combinedAlert: signals.count >= hp.minSignalsForAlert)
    }

    /// Texto fijo del aviso combinado (RL-02: nunca menciona enfermedades).
    public static let alertMessage = "Tus métricas nocturnas están fuera de tu rango habitual. Puede deberse a alcohol, estrés, poco descanso o un viaje. Tómatelo con calma y, si te encuentras mal, consulta a un profesional sanitario."
}

// MARK: - ALG-DIA-01 · Impacto de hábitos

public struct HabitImpact: Hashable, Codable, Sendable {
    public var questionKey: String
    public var effect: Double?
    public var ciLow: Double?
    public var ciHigh: Double?
    public var nYes: Int
    public var nNo: Int

    public enum Status: String, Codable, Sendable { case needMoreData, noClearEffect, effect }

    public var status: Status {
        guard nYes >= 5, nNo >= 5, let lo = ciLow, let hi = ciHigh else { return .needMoreData }
        return (lo <= 0 && hi >= 0) ? .noClearEffect : .effect
    }
}

public struct HabitDay: Hashable, Sendable {
    public var date: LocalDate
    public var habit: Bool
    public var strain: Double
    public var nextDayRecovery: Double

    public init(date: LocalDate, habit: Bool, strain: Double, nextDayRecovery: Double) {
        self.date = date
        self.habit = habit
        self.strain = strain
        self.nextDayRecovery = nextDayRecovery
    }
}

public enum HabitImpactCalculator {
    /// Recuperación_{t+1} = β₀ + β_h·h_t + β_c·Carga_t + β_f·FinDeSemana_t; IC 95 % por *bootstrap* por bloques de 7 días.
    public static func impact(questionKey: String, days: [HabitDay], resamples: Int = 1000, seed: UInt64 = 42) -> HabitImpact {
        let sorted = days.sorted { $0.date < $1.date }
        let nYes = sorted.filter(\.habit).count
        let nNo = sorted.count - nYes
        guard nYes >= 5, nNo >= 5 else {
            return HabitImpact(questionKey: questionKey, effect: nil, ciLow: nil, ciHigh: nil, nYes: nYes, nNo: nNo)
        }
        guard let beta = fit(sorted) else {
            return HabitImpact(questionKey: questionKey, effect: nil, ciLow: nil, ciHigh: nil, nYes: nYes, nNo: nNo)
        }
        // Bootstrap por bloques de 7 días.
        let blocks = stride(from: 0, to: sorted.count, by: 7).map { Array(sorted[$0..<min($0 + 7, sorted.count)]) }
        var rng = SeededGenerator(seed: seed)
        var estimates: [Double] = []
        for _ in 0..<resamples {
            var sample: [HabitDay] = []
            while sample.count < sorted.count {
                sample.append(contentsOf: blocks[Int.random(in: 0..<blocks.count, using: &rng)])
            }
            if let b = fit(Array(sample.prefix(sorted.count))) { estimates.append(b) }
        }
        let lo = Stats.percentile(estimates, 2.5)
        let hi = Stats.percentile(estimates, 97.5)
        return HabitImpact(questionKey: questionKey, effect: (beta * 10).rounded() / 10,
                           ciLow: lo.map { ($0 * 10).rounded() / 10 }, ciHigh: hi.map { ($0 * 10).rounded() / 10 },
                           nYes: nYes, nNo: nNo)
    }

    static func fit(_ days: [HabitDay]) -> Double? {
        let yes = days.filter(\.habit).count
        guard yes > 0, yes < days.count else { return nil }
        let x = days.map { [1.0, $0.habit ? 1 : 0, $0.strain, $0.date.isWeekend ? 1 : 0] }
        let y = days.map(\.nextDayRecovery)
        if let b = Stats.ols(x, y) { return b[1] }
        // Si la matriz es singular (p. ej. sin fines de semana), se quita esa columna.
        let x2 = days.map { [1.0, $0.habit ? 1 : 0, $0.strain] }
        return Stats.ols(x2, y)?[1]
    }
}
