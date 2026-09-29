import Foundation

// MARK: - ALG-SUE · Sueño

public struct SleepNeedBreakdown: Hashable, Codable, Sendable {
    public var baseMin: Double
    public var strainAdjMin: Double
    public var debtAdjMin: Double
    public var napCreditMin: Double

    public var totalMin: Double { max(0, baseMin + strainAdjMin + debtAdjMin - napCreditMin) }
    /// Necesidad sin el término de deuda (para calcular la deuda sin contarla dos veces).
    public var withoutDebtMin: Double { max(0, baseMin + strainAdjMin - napCreditMin) }
}

public enum SleepBand: String, Codable, Sendable {
    case optimal, sufficient, poor

    public var label: String {
        switch self {
        case .optimal: return "Óptimo"
        case .sufficient: return "Suficiente"
        case .poor: return "Bajo"
        }
    }
}

public struct SleepResult: Hashable, Codable, Sendable {
    public var sessionID: String
    public var need: SleepNeedBreakdown
    public var asleepMin: Double
    public var timeInBedMin: Double
    public var sufficiency: Double          // 0–100
    public var efficiency: Double           // %
    public var efficiencyScaled: Double     // 0–100
    public var consistency: Double?         // SRI 0–100
    public var performance: Double          // 0–100
    public var band: SleepBand
    public var debtMin: Double
    public var restorativeMin: Double
    public var restorativePct: Double
    public var deepMin: Double
    public var remMin: Double
    public var lightMin: Double
    public var latencyMin: Double?
    public var awakenings: Int
    public var wasoMin: Double
}

public enum SleepCalculator {
    /// ALG-SUE-01 · base por edad (8 h hasta los 64, 7 h 30 después) o personalizada.
    public static func baseNeed(profile: UserProfile, date: LocalDate, params: AlgorithmParams) -> Double {
        if let o = profile.sleepBaseOverrideMin { return o }
        let age = profile.age(on: date) ?? 35
        return age >= 65 ? (params.sleep.baseByAge["65+"] ?? 450) : (params.sleep.baseByAge["18-64"] ?? 480)
    }

    public static func need(base: Double, previousCycleStrain: Double?, strainMean28: Double?, currentDebt: Double,
                            napMinutes: Double, params: AlgorithmParams) -> SleepNeedBreakdown {
        let p = params.sleep
        var strainAdj = 0.0
        if let s = previousCycleStrain, let m = strainMean28 {
            strainAdj = min(p.strainAdjMax, p.strainAdjPerPoint * max(0, s - m))
        }
        let debtAdj = min(p.debtRepayMax, p.debtRepayFraction * currentDebt)
        let nap = min(p.napCreditMax, napMinutes)
        return SleepNeedBreakdown(baseMin: base, strainAdjMin: strainAdj, debtAdjMin: debtAdj, napCreditMin: nap)
    }

    /// ALG-SUE-02 · suficiencia.
    public static func sufficiency(asleep: Double, need: Double) -> Double {
        guard need > 0 else { return 100 }
        return min(100, 100 * asleep / need)
    }

    /// ALG-SUE-03 · deuda.
    public static func debt(previous: Double, needWithoutDebt: Double, asleep: Double, params: AlgorithmParams) -> Double {
        Stats.clip(params.sleep.debtDecay * previous + (needWithoutDebt - asleep), 0, params.sleep.debtCap)
    }

    /// ALG-SUE-04 · índice de regularidad del sueño (SRI) de los últimos días (≥ 5 pares válidos).
    /// `asleepMinutes`: minutos (época en segundos, múltiplos de 60) en que se estaba dormido, incluidas siestas.
    /// `coveredDays`: fechas con datos de sueño registrados.
    public static func sri(asleepMinutes: Set<Int>, coveredDays: [LocalDate], until date: LocalDate, utcOffset: Int, days: Int = 7) -> Double? {
        let covered = Set(coveredDays)
        var agree = 0
        var total = 0
        var pairs = 0
        for k in 0..<(days - 1) {
            let d1 = date.adding(days: -(days - 1) + k)
            let d2 = d1.adding(days: 1)
            guard covered.contains(d1), covered.contains(d2) else { continue }
            pairs += 1
            let start = d1.startDate(utcOffsetSeconds: utcOffset).timeIntervalSince1970
            for j in 0..<1440 {
                let m1 = Int(start) + j * 60
                let m2 = m1 + 86_400
                total += 1
                if asleepMinutes.contains(m1) == asleepMinutes.contains(m2) { agree += 1 }
            }
        }
        guard pairs >= 5, total > 0 else { return nil }
        let sri = -100 + 200 * Double(agree) / Double(total)
        return max(0, sri)
    }

    /// ALG-SUE-06/07 · métricas de una sesión y rendimiento.
    public static func evaluate(session: SleepSession, need: SleepNeedBreakdown, debt: Double, consistency: Double?,
                                params: AlgorithmParams) -> SleepResult {
        let asleep = session.minutesAsleep
        let inBed = max(session.timeInBedMinutes, asleep)
        let efficiency = inBed > 0 ? 100 * asleep / inBed : 0
        let es = params.sleep.efficiencyScale
        let effScaled = Stats.clip((efficiency - es[0]) / (es[1] - es[0]) * 100, 0, 100)
        let suff = sufficiency(asleep: asleep, need: need.totalMin)
        let w = params.sleep.performanceWeights
        let perf: Double
        if let c = consistency {
            perf = w.sufficiency * suff + w.efficiency * effScaled + w.consistency * c
        } else {
            perf = 0.82 * suff + 0.18 * effScaled
        }
        let deep = session.minutes(in: .deep), rem = session.minutes(in: .rem), light = session.minutes(in: .light)
        let restorative = deep + rem
        let wakeSegments = session.stages.filter { $0.stage == .wake }
        // Vigilia intra-sueño: segmentos «despierto» entre el primer y el último segmento dormido.
        let firstAsleep = session.stages.first { $0.stage.isAsleep }?.start
        let lastAsleep = session.stages.last { $0.stage.isAsleep }?.end
        let inner = wakeSegments.filter { s in
            guard let a = firstAsleep, let b = lastAsleep else { return false }
            return s.start >= a && s.end <= b
        }
        let latency: Double? = session.latencyFromSource.map(Double.init)
            ?? firstAsleep.map { $0.timeIntervalSince(session.start) / 60 }
        return SleepResult(
            sessionID: session.id, need: need, asleepMin: asleep, timeInBedMin: inBed, sufficiency: suff,
            efficiency: efficiency, efficiencyScaled: effScaled, consistency: consistency,
            performance: Stats.clip(perf, 0, 100), band: band(perf, params: params), debtMin: debt,
            restorativeMin: restorative, restorativePct: asleep > 0 ? 100 * restorative / asleep : 0,
            deepMin: deep, remMin: rem, lightMin: light, latencyMin: latency,
            awakenings: inner.filter { $0.minutes >= 5 }.count, wasoMin: inner.reduce(0) { $0 + $1.minutes })
    }

    public static func band(_ value: Double, params: AlgorithmParams) -> SleepBand {
        if value >= params.sleep.bands.optimal { return .optimal }
        if value >= params.sleep.bands.sufficient { return .sufficient }
        return .poor
    }

    /// Bandas propias de eficiencia (≥ 90 / 80–89 / < 80) y constancia (≥ 80 / 70–79 / < 70).
    public static func efficiencyBand(_ e: Double) -> SleepBand { e >= 90 ? .optimal : (e >= 80 ? .sufficient : .poor) }
    public static func consistencyBand(_ c: Double) -> SleepBand { c >= 80 ? .optimal : (c >= 70 ? .sufficient : .poor) }

    // MARK: ALG-SUE-05 · Planificador

    public enum PlannerGoal: Int, Codable, Sendable, CaseIterable {
        case peak = 0, perform = 1, minimum = 2

        public var label: String {
            switch self {
            case .peak: return "Máximo (100 %)"
            case .perform: return "Rendir (85 %)"
            case .minimum: return "Mínimo (70 %)"
            }
        }
    }

    /// Hora de acostarse en minutos desde medianoche (puede ser negativa = día anterior), redondeada a 5 min.
    public static func bedtime(wakeMinutes: Int, needMin: Double, goal: PlannerGoal, usualEfficiency: Double?,
                               usualLatency: Double?, params: AlgorithmParams) -> Int {
        let f = params.sleep.plannerFactors[min(goal.rawValue, params.sleep.plannerFactors.count - 1)]
        let eff = max(0.5, min(1.0, (usualEfficiency ?? 90) / 100))
        let latency = usualLatency ?? 15
        let minutes = Double(wakeMinutes) - (needMin * f) / eff - latency
        return Int((minutes / 5).rounded()) * 5
    }

    /// Modo «Mejorar mi constancia»: acerca la hora habitual al objetivo en pasos de ≤ 15 min.
    public static func consistencyBedtime(usualBedtime: Int, target: Int, params: AlgorithmParams) -> Int {
        let step = params.sleep.consistencyStepMaxMin
        let delta = Stats.clip(Double(target - usualBedtime), -step, step)
        return usualBedtime + Int(delta)
    }
}
