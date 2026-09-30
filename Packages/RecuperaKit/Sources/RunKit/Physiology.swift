import Foundation
import MetricsKit

// MARK: - Fórmulas de carrera (doc. 18 §3)

/// Distancias estándar para mejores marcas, récords y predicciones.
public enum RaceDistance: Double, CaseIterable, Codable, Sendable, Hashable {
    case m400 = 400
    case k1 = 1000
    case mile = 1609.344
    case k3 = 3000
    case k5 = 5000
    case k10 = 10000
    case k15 = 15000
    case half = 21097.5
    case k30 = 30000
    case marathon = 42195

    public var label: String {
        switch self {
        case .m400: return "400 m"
        case .k1: return "1 km"
        case .mile: return "1 milla"
        case .k3: return "3 km"
        case .k5: return "5 km"
        case .k10: return "10 km"
        case .k15: return "15 km"
        case .half: return "Media maratón"
        case .k30: return "30 km"
        case .marathon: return "Maratón"
        }
    }

    /// Clave estable para guardar en JSON.
    public var key: String { String(Int(rawValue.rounded())) }

    /// Distancias que se predicen a partir del VDOT.
    public static let predicted: [RaceDistance] = [.k5, .k10, .half, .marathon]
}

/// Fórmulas de Jack Daniels y Jimmy Gilbert (VDOT), Riegel, Strava (coste en pendiente) y Swain (%FC → %VO₂).
public enum RunPhysiology {
    /// VO₂ (ml/kg/min) que cuesta correr a `v` m/min en llano.
    public static func vo2(metersPerMinute v: Double) -> Double { -4.60 + 0.182258 * v + 0.000104 * v * v }

    /// Fracción del VO₂ máx. que se puede mantener durante `minutes`.
    public static func sustainableFraction(minutes t: Double) -> Double {
        0.8 + 0.1894393 * exp(-0.012778 * t) + 0.2989558 * exp(-0.1932605 * t)
    }

    /// VDOT de un esfuerzo máximo: `meters` en `seconds`.
    public static func vdot(meters: Double, seconds: Double) -> Double? {
        guard meters >= 1000, seconds > 0 else { return nil }
        let minutes = seconds / 60
        let value = vo2(metersPerMinute: meters / minutes) / sustainableFraction(minutes: minutes)
        return value.isFinite && value > 10 && value < 100 ? value : nil
    }

    /// Tiempo previsto (s) para `meters` con un VDOT dado (bisección: el VDOT baja al subir el tiempo).
    public static func predictedSeconds(meters: Double, vdot: Double) -> Double? {
        guard vdot > 10, meters > 0 else { return nil }
        var lo = meters / 700 * 60      // 700 m/min
        var hi = meters / 40 * 60       // 40 m/min
        for _ in 0..<80 {
            let mid = (lo + hi) / 2
            guard let v = self.vdot(meters: meters, seconds: mid) else { return nil }
            if v > vdot { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// Velocidad (m/s) a la que el coste es `fraction` del VDOT.
    public static func speed(fractionOfVDOT fraction: Double, vdot: Double) -> Double {
        let target = fraction * vdot
        let a = 0.000104, b = 0.182258, c = -(4.60 + target)
        let v = (-b + (b * b - 4 * a * c).squareRoot()) / (2 * a)   // m/min
        return v / 60
    }

    /// Riegel: tiempo en `toMeters` a partir de `seconds` en `fromMeters`.
    public static func riegel(seconds: Double, fromMeters: Double, toMeters: Double, exponent: Double = 1.06) -> Double {
        seconds * pow(toMeters / fromMeters, exponent)
    }

    /// Cuánto más cuesta correr con pendiente `grade` (fracción) que en llano a igual frecuencia cardiaca: la curva empírica
    /// de Strava (Robb, 2017), ajustada como 1 + 0,0287·g + 0,00152·g² con g en % [R79]. Subir un 4 % cuesta un 14 % más;
    /// bajar ayuda como mucho un 14 % (hacia el −9 %) y en bajadas muy fuertes vuelve a costar. (El coste energético de
    /// Minetti et al., 2002, medido en cinta, exagera las dos cosas frente a lo que hacen los corredores.)
    public static func gradeFactor(grade: Double) -> Double {
        let g = Stats.clip(grade, -0.45, 0.45) * 100
        return 1 + 0.028_695_56 * g + 0.001_520_768 * g * g
    }

    /// Velocidad equivalente en llano (ritmo ajustado por pendiente, GAP).
    public static func gradeAdjusted(speed: Double, grade: Double?) -> Double {
        guard let grade else { return speed }
        return speed * gradeFactor(grade: grade)
    }

    /// VO₂ máx. estimado de una carrera submáxima: coste del ritmo (ajustado por pendiente) entre la fracción de VO₂ máx.
    /// que corresponde a la FC media (Swain et al., 1994: %FCmáx = 0,64·%VO₂máx + 0,37).
    public static func estimatedVO2max(avgSpeed: Double, avgHR: Double, hrMax: Double) -> Double? {
        guard avgSpeed > 1.5, avgHR > 0, hrMax > 100 else { return nil }
        let hrFraction = avgHR / hrMax
        guard hrFraction >= 0.65, hrFraction <= 0.98 else { return nil }
        let vo2Fraction = (hrFraction - 0.37) / 0.64
        let value = vo2(metersPerMinute: avgSpeed * 60) / vo2Fraction
        return value >= 20 && value <= 90 ? value : nil
    }

    /// Ritmos de entrenamiento de Daniels para un VDOT.
    public static func trainingPaces(vdot: Double) -> [TrainingPace] {
        let marathon = predictedSeconds(meters: RaceDistance.marathon.rawValue, vdot: vdot).map { RaceDistance.marathon.rawValue / $0 }
        return [
            TrainingPace(zone: .easy, slowSpeed: speed(fractionOfVDOT: 0.62, vdot: vdot), fastSpeed: speed(fractionOfVDOT: 0.70, vdot: vdot)),
            TrainingPace(zone: .marathon, slowSpeed: marathon ?? speed(fractionOfVDOT: 0.80, vdot: vdot),
                         fastSpeed: marathon ?? speed(fractionOfVDOT: 0.80, vdot: vdot)),
            TrainingPace(zone: .threshold, slowSpeed: speed(fractionOfVDOT: 0.88, vdot: vdot), fastSpeed: speed(fractionOfVDOT: 0.88, vdot: vdot)),
            TrainingPace(zone: .interval, slowSpeed: speed(fractionOfVDOT: 0.975, vdot: vdot), fastSpeed: speed(fractionOfVDOT: 0.975, vdot: vdot)),
            TrainingPace(zone: .repetition, slowSpeed: speed(fractionOfVDOT: 1.05, vdot: vdot), fastSpeed: speed(fractionOfVDOT: 1.05, vdot: vdot)),
        ]
    }

    /// Límites de las zonas de ritmo (velocidad mínima de cada zona 2…6) a partir del VDOT.
    public static func paceZoneBounds(vdot: Double) -> [Double] {
        [0.60, 0.75, 0.84, 0.92, 1.00].map { speed(fractionOfVDOT: $0, vdot: vdot) }
    }
}

/// Ritmo de entrenamiento (velocidades en m/s; en los ritmos de un solo valor, las dos iguales).
public struct TrainingPace: Codable, Sendable, Hashable {
    public enum Zone: String, Codable, Sendable, CaseIterable {
        case easy, marathon, threshold, interval, repetition

        public var label: String {
            switch self {
            case .easy: return "Suave (E)"
            case .marathon: return "Maratón (M)"
            case .threshold: return "Umbral (T)"
            case .interval: return "Intervalos (I)"
            case .repetition: return "Repeticiones (R)"
            }
        }

        public var purpose: String {
            switch self {
            case .easy: return "Rodajes y tirada larga: base aeróbica y recuperación."
            case .marathon: return "Ritmo de maratón: resistencia específica."
            case .threshold: return "Tempo o series largas de 5–15 min: sube el umbral."
            case .interval: return "Series de 3–5 min: VO₂ máx."
            case .repetition: return "Series cortas de 200–400 m: velocidad y economía."
            }
        }
    }

    public var zone: Zone
    public var slowSpeed: Double
    public var fastSpeed: Double
}
