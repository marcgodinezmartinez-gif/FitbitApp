import Foundation

// MARK: - ALG-CAR · Carga («Strain»)

public struct HRZones: Hashable, Codable, Sendable {
    /// Límites inferiores de Z1…Z5 en lpm (Z0 por debajo de Z1).
    public var lowerBounds: [Double]
    public var hrMax: Double
    public var restingRef: Double

    /// Zona 0…5 de un valor de FC.
    public func zone(of bpm: Double) -> Int {
        var z = 0
        for (i, lb) in lowerBounds.enumerated() where bpm >= lb { z = i + 1 }
        return z
    }
}

public struct StrainResult: Hashable, Codable, Sendable {
    public var strain: Double              // 0–21
    public var loadRaw: Double             // TRIMP (L)
    public var zoneMinutes: [Int]          // Z0…Z5
    public var validHours: Double
    public var confidence: Confidence

    public static let empty = StrainResult(strain: 0, loadRaw: 0, zoneMinutes: Array(repeating: 0, count: 6),
                                           validHours: 0, confidence: .low)
}

public struct TargetBand: Hashable, Codable, Sendable {
    public var low: Double
    public var high: Double
    public var center: Double

    public enum Status: String, Codable, Sendable { case below, within, above }

    public func status(of strain: Double) -> Status {
        if strain < low { return .below }
        if strain > high { return .above }
        return .within
    }
}

public enum StrainMode: String, Codable, Sendable, CaseIterable {
    case maintain, progress, deload

    public var offset: Double {
        switch self {
        case .maintain: return 0
        case .progress: return 1
        case .deload: return -2
        }
    }

    public var label: String {
        switch self {
        case .maintain: return "Mantener"
        case .progress: return "Progresar"
        case .deload: return "Descargar"
        }
    }
}

public enum StrainCalculator {
    /// ALG-CAR-06: FC máx. (manual > observada confirmada > fórmula de Tanaka).
    public static func hrMax(profile: UserProfile, on date: LocalDate) -> Double {
        if let m = profile.hrMaxOverride { return m }
        if let o = profile.observedHRMaxConfirmed { return o }
        let age = profile.age(on: date) ?? 35
        return 208 - 0.7 * age
    }

    /// Máxima observada robusta: mediana móvil de 30 s de la FC de alta resolución; exige ≥ 2 entrenamientos.
    public static func observedHRMax(workoutSamples: [[HRSample]]) -> Double? {
        var peaks: [Double] = []
        for samples in workoutSamples {
            let s = Validity.filterSamples(samples)
            guard s.count >= 10 else { continue }
            var best = 0.0
            var window: [HRSample] = []
            for x in s {
                window.append(x)
                while let f = window.first, x.time.timeIntervalSince(f.time) > 30 { window.removeFirst() }
                if let med = Stats.median(window.map(\.bpm)) { best = max(best, med) }
            }
            if best > 0 { peaks.append(best) }
        }
        guard peaks.count >= 2 else { return nil }
        let top = peaks.sorted(by: >)
        return top[1] // la segunda mayor: exige que el pico se repita en otro entrenamiento
    }

    public static func zones(hrMax: Double, restingRef: Double) -> HRZones {
        let hrr = max(hrMax - restingRef, 1)
        let bounds = [0.5, 0.6, 0.7, 0.8, 0.9].map { restingRef + $0 * hrr }
        return HRZones(lowerBounds: bounds, hrMax: hrMax, restingRef: restingRef)
    }

    /// Impulso de un minuto (TRIMP de Banister) con la fracción de FC de reserva x.
    public static func impulse(bpm: Double, zones: HRZones, sex: Sex, params: AlgorithmParams) -> Double {
        let x = Stats.clip((bpm - zones.restingRef) / max(zones.hrMax - zones.restingRef, 1), 0, 1)
        guard x >= params.strain.xMin else { return 0 }
        let (a, b) = params.banisterCoefficients(for: sex)
        return x * a * exp(b * x)
    }

    /// Escala no lineal 0–21.
    public static func scale(load: Double, params: AlgorithmParams) -> Double {
        guard load > 0 else { return 0 }
        let v = 21 * (1 - exp(-pow(load / params.strain.tau, params.strain.gamma)))
        return (v * 10).rounded() / 10
    }

    /// ALG-CAR-01/02: carga de un conjunto de minutos (ciclo o actividad).
    public static func compute(minutes: [HRMinute], zones: HRZones, sex: Sex, params: AlgorithmParams,
                               expectedHours: Double? = nil, extraLoad: Double = 0) -> StrainResult {
        var load = 0.0
        var zoneMinutes = Array(repeating: 0, count: 6)
        var valid = 0
        for m in minutes where Validity.isValidBPM(m.bpmAvg) {
            valid += 1
            load += impulse(bpm: m.bpmAvg, zones: zones, sex: sex, params: params)
            zoneMinutes[zones.zone(of: m.bpmAvg)] += 1
        }
        load += extraLoad
        let hours = Double(valid) / 60
        var confidence: Confidence = .high
        if let expected = expectedHours {
            if hours < min(10, expected * 0.6) { confidence = .low } else if hours < expected * 0.85 { confidence = .medium }
        }
        return StrainResult(strain: scale(load: load, params: params), loadRaw: load, zoneMinutes: zoneMinutes,
                            validHours: hours, confidence: valid == 0 ? .low : confidence)
    }

    /// ALG-CAR-05: carga extra de fuerza por sRPE que se suma al ciclo.
    public static func strengthExtraLoad(cardioLoad: Double, rpe: Double?, minutes: Double, params: AlgorithmParams) -> Double {
        guard let rpe else { return 0 }
        let srpe = rpe * minutes
        return max(0, params.strain.kappaSrpe * srpe - cardioLoad)
    }

    /// ALG-CAR-03: carga objetivo según la recuperación y la media de 28 ciclos.
    public static func target(recovery: Int?, recentStrains: [Double], mode: StrainMode, params: AlgorithmParams) -> TargetBand? {
        guard let recovery, recentStrains.count >= 7, let mean = Stats.mean(Array(recentStrains.suffix(28))) else { return nil }
        let center = mean + params.strain.targetK * (Double(recovery) - 50) / 50 + mode.offset
        let lo = params.strain.targetBounds.first ?? 4, hi = params.strain.targetBounds.last ?? 19
        let low = Stats.clip(center - params.strain.targetHalfWidth, lo, hi)
        let high = Stats.clip(center + params.strain.targetHalfWidth, lo, hi)
        return TargetBand(low: (low * 10).rounded() / 10, high: (high * 10).rounded() / 10, center: (center * 10).rounded() / 10)
    }

    /// ALG-CAR-04: medias móviles exponenciales de la carga bruta diaria.
    public static func ewma(_ loads: [Double], days: Int) -> Double? {
        guard let first = loads.first else { return nil }
        let lambda = 2 / Double(days + 1)
        return loads.dropFirst().reduce(first) { lambda * $1 + (1 - lambda) * $0 }
    }
}
