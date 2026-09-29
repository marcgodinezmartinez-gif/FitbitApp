import Foundation

// MARK: - ALG-EDA · Edad fisiológica y ritmo de envejecimiento («beta»)

public struct PhysioAgeInputs: Sendable {
    public var chronologicalAge: Double
    public var sex: Sex
    public var vo2max: Double?
    public var vo2maxSource: DataSourceKind?
    public var stepsPerDay: Double?
    public var restingHR: Double?
    public var moderateMinPerWeek: Double?
    public var vigorousMinPerWeek: Double?
    public var strengthMinPerWeek: Double?
    public var sleepHours: Double?
    public var sri: Double?
    public var validDays: Int
    /// El VO₂ máx. es la estimación sin ejercicio (ALG-EDA-02), no una medida del Apple Watch ni de Google.
    public var vo2maxEstimated: Bool

    public init(chronologicalAge: Double, sex: Sex, vo2max: Double?, vo2maxSource: DataSourceKind?, stepsPerDay: Double?,
                restingHR: Double?, moderateMinPerWeek: Double?, vigorousMinPerWeek: Double?, strengthMinPerWeek: Double?,
                sleepHours: Double?, sri: Double?, validDays: Int, vo2maxEstimated: Bool = false) {
        self.chronologicalAge = chronologicalAge
        self.sex = sex
        self.vo2max = vo2max
        self.vo2maxSource = vo2maxSource
        self.stepsPerDay = stepsPerDay
        self.restingHR = restingHR
        self.moderateMinPerWeek = moderateMinPerWeek
        self.vigorousMinPerWeek = vigorousMinPerWeek
        self.strengthMinPerWeek = strengthMinPerWeek
        self.sleepHours = sleepHours
        self.sri = sri
        self.validDays = validDays
        self.vo2maxEstimated = vo2maxEstimated
    }
}

public struct PhysioAgeFactor: Hashable, Codable, Sendable, Identifiable {
    public var key: String
    public var label: String
    public var value: String
    public var deltaYears: Double
    public var id: String { key }
}

public struct PhysioAgeResult: Hashable, Codable, Sendable {
    public var estimate: Double
    public var bandLow: Double
    public var bandHigh: Double
    public var factors: [PhysioAgeFactor]
    public var fitnessAge: Double?
    public var calibrated: Bool
    public var omittedFitness: Bool
    /// La forma física sale del modelo sin ejercicio (ALG-EDA-02).
    public var fitnessEstimated: Bool?
}

public enum PhysioAgeCalculator {
    /// VO₂ máx. de referencia (HUNT): 54,4 (hombres) y 43,0 (mujeres) a los 20–29 años, −3,5 por década.
    public static func referenceVO2(age: Double, sex: Sex) -> Double {
        let base: Double
        switch sex {
        case .male: base = 54.4
        case .female: base = 43.0
        case .unspecified: base = 48.7
        }
        return base - 3.5 * max(0, age - 25) / 10
    }

    public static func fitnessAge(vo2max: Double, sex: Sex) -> Double {
        let base = referenceVO2(age: 25, sex: sex)
        return Stats.clip(25 + (base - vo2max) * 10 / 3.5, 20, 90)
    }

    /// Interpolación lineal de log(HR) entre puntos (x, HR).
    static func logInterp(_ x: Double, _ pts: [(Double, Double)]) -> Double {
        guard let first = pts.first, let last = pts.last else { return 1 }
        if x <= first.0 { return first.1 }
        if x >= last.0 { return last.1 }
        for i in 1..<pts.count where x <= pts[i].0 {
            let (x0, h0) = pts[i - 1], (x1, h1) = pts[i]
            let f = (x - x0) / (x1 - x0)
            return exp(log(h0) + f * (log(h1) - log(h0)))
        }
        return last.1
    }

    /// Años que suma (+) o resta (−) un factor, con encogimiento y tope (ALG-EDA-01).
    static func years(hrRelative: Double, params: AlgorithmParams) -> Double {
        let p = params.physioAge
        let raw = p.gompertzDoublingYears * log2(max(hrRelative, 1e-6))
        return Stats.clip(p.shrinkage * raw, -p.capPerFactorYears, p.capPerFactorYears)
    }

    public static func estimate(_ input: PhysioAgeInputs, params: AlgorithmParams) -> PhysioAgeResult? {
        guard input.validDays >= params.physioAge.minValidDays else { return nil }
        var factors: [PhysioAgeFactor] = []
        let age = input.chronologicalAge

        if let vo2 = input.vo2max {
            let deltaMET = (vo2 - referenceVO2(age: age, sex: input.sex)) / 3.5
            let hr = pow(0.87, deltaMET) // cada MET ⇒ RR 0,87 [R28]
            factors.append(PhysioAgeFactor(key: "vo2max",
                                           label: input.vo2maxEstimated ? "Forma cardiorrespiratoria (estimada)" : "Forma cardiorrespiratoria",
                                           value: String(format: "%.0f ml/kg/min", vo2), deltaYears: years(hrRelative: hr, params: params)))
        }
        if let steps = input.stepsPerDay {
            let cap = age >= 60 ? 8000.0 : 10_000.0
            let pts: [(Double, Double)] = [(3553, 1.0), (5801, 0.60), (7842, 0.55), (10_901, 0.47)] // [R29]
            let hr = logInterp(min(steps, cap), pts) / logInterp(7000, pts)
            factors.append(PhysioAgeFactor(key: "steps", label: "Pasos diarios", value: String(format: "%.0f", steps),
                                           deltaYears: years(hrRelative: hr, params: params)))
        }
        if let rhr = input.restingHR {
            let hr = pow(1.09, (rhr - 65) / 10) // RR 1,09 por +10 lpm [R30]
            factors.append(PhysioAgeFactor(key: "rhr", label: "FC en reposo", value: String(format: "%.0f lpm", rhr),
                                           deltaYears: years(hrRelative: hr, params: params)))
        }
        if input.moderateMinPerWeek != nil || input.vigorousMinPerWeek != nil {
            let eq = (input.moderateMinPerWeek ?? 0) + 2 * (input.vigorousMinPerWeek ?? 0)
            let pts: [(Double, Double)] = [(0, 1.0), (150, 0.80), (300, 0.74), (600, 0.70)] // [R32] [heurístico]
            let hr = logInterp(eq, pts) / 0.80
            factors.append(PhysioAgeFactor(key: "zones", label: "Minutos en zonas", value: String(format: "%.0f min/sem", eq),
                                           deltaYears: years(hrRelative: hr, params: params)))
        }
        if let s = input.strengthMinPerWeek {
            let pts: [(Double, Double)] = [(0, 1.0), (30, 0.85), (60, 0.85), (130, 0.87)] // [R43] [heurístico]
            factors.append(PhysioAgeFactor(key: "strength", label: "Fuerza", value: String(format: "%.0f min/sem", s),
                                           deltaYears: years(hrRelative: logInterp(s, pts), params: params)))
        }
        if let h = input.sleepHours {
            let pts: [(Double, Double)] = [(5, 1.12), (6, 1.06), (7, 1.0), (8, 1.0), (9, 1.15), (10, 1.30)] // [R31]
            factors.append(PhysioAgeFactor(key: "sleep_hours", label: "Horas de sueño", value: String(format: "%.1f h", h).replacingOccurrences(of: ".", with: ","),
                                           deltaYears: years(hrRelative: logInterp(h, pts), params: params)))
        }
        if let sri = input.sri {
            let pts: [(Double, Double)] = [(60, 1.25), (70, 1.10), (81, 1.0), (90, 0.95)] // [R19] [heurístico]
            factors.append(PhysioAgeFactor(key: "sri", label: "Regularidad del sueño", value: String(format: "%.0f", sri),
                                           deltaYears: years(hrRelative: logInterp(sri, pts), params: params)))
        }
        guard !factors.isEmpty else { return nil }
        let p = params.physioAge
        let total = Stats.clip(factors.reduce(0) { $0 + $1.deltaYears }, -p.capTotalYears, p.capTotalYears)
        let estimate = age + total
        let spread = 2 + 0.3 * factors.reduce(0) { $0 + abs($1.deltaYears) }
        return PhysioAgeResult(estimate: (estimate * 10).rounded() / 10,
                               bandLow: ((estimate - spread) * 10).rounded() / 10,
                               bandHigh: ((estimate + spread) * 10).rounded() / 10,
                               factors: factors.map { var f = $0; f.deltaYears = (f.deltaYears * 10).rounded() / 10; return f },
                               fitnessAge: input.vo2max.map { fitnessAge(vo2max: $0, sex: input.sex) },
                               calibrated: input.validDays >= p.calibratedDays,
                               omittedFitness: input.vo2max == nil,
                               fitnessEstimated: input.vo2max != nil && input.vo2maxEstimated ? true : nil)
    }

    /// ALG-EDA-03: ritmo = ΔEdadF / (30/365), recortado a [−3, 3].
    public static func pace(current: Double, thirtyDaysAgo: Double, params: AlgorithmParams) -> Double {
        let days = Double(params.physioAge.paceWindowDays)
        return Stats.clip((current - thirtyDaysAgo) / (days / 365), -3, 3)
    }
}
