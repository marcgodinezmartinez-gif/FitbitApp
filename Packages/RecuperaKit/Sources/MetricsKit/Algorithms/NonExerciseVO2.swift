import Foundation

// MARK: - ALG-EDA-02 · VO₂ máx. estimado sin ejercicio (modelo HUNT) [R44]

/// Las tres preguntas de actividad física del estudio HUNT. El índice (PA-I, 0–15) es el producto de las tres respuestas.
public struct ActivityQuestionnaire: Hashable, Codable, Sendable {
    /// «¿Con qué frecuencia haces ejercicio?»
    public enum Frequency: String, Codable, Sendable, CaseIterable {
        case never, lessThanWeekly, weekly, twoToThreeWeekly, almostDaily

        public var score: Double {
            switch self {
            case .never, .lessThanWeekly: return 0
            case .weekly: return 1
            case .twoToThreeWeekly: return 2.5
            case .almostDaily: return 5
            }
        }

        public var label: String {
            switch self {
            case .never: return "Nunca"
            case .lessThanWeekly: return "Menos de una vez por semana"
            case .weekly: return "Una vez por semana"
            case .twoToThreeWeekly: return "2–3 veces por semana"
            case .almostDaily: return "Casi todos los días"
            }
        }
    }

    /// «Si haces ejercicio una vez por semana o más, ¿cuánto te esfuerzas?»
    public enum Intensity: String, Codable, Sendable, CaseIterable {
        case easy, breathless, nearExhaustion

        public var score: Double {
            switch self {
            case .easy: return 1
            case .breathless: return 2
            case .nearExhaustion: return 3
            }
        }

        public var label: String {
            switch self {
            case .easy: return "Con calma, sin sudar ni quedarme sin aliento"
            case .breathless: return "Hasta quedarme sin aliento y sudar"
            case .nearExhaustion: return "Casi hasta el agotamiento"
            }
        }
    }

    /// «¿Cuánto dura cada sesión?»
    public enum Duration: String, Codable, Sendable, CaseIterable {
        case under15, from15to29, from30to60, over60

        public var score: Double {
            switch self {
            case .under15: return 0.1
            case .from15to29: return 0.38
            case .from30to60: return 0.75
            case .over60: return 1.0
            }
        }

        public var label: String {
            switch self {
            case .under15: return "Menos de 15 minutos"
            case .from15to29: return "15–29 minutos"
            case .from30to60: return "30 minutos a 1 hora"
            case .over60: return "Más de 1 hora"
            }
        }
    }

    public var frequency: Frequency
    public var intensity: Intensity
    public var duration: Duration

    public init(frequency: Frequency, intensity: Intensity, duration: Duration) {
        self.frequency = frequency
        self.intensity = intensity
        self.duration = duration
    }

    /// Índice de actividad física (PA-I) = frecuencia × intensidad × duración, de 0 a 15.
    public var index: Double { frequency.score * intensity.score * duration.score }
}

public enum NonExerciseVO2 {
    /// VO₂ máx. (ml/kg/min) con las ecuaciones por sexo de Nes et al. (2011):
    /// hombres 100,27 − 0,296·edad − 0,369·cintura − 0,155·FCR + 0,226·PA-I;
    /// mujeres 74,74 − 0,247·edad − 0,259·cintura − 0,114·FCR + 0,198·PA-I.
    /// El modelo es específico de cada sexo: sin sexo indicado no se estima.
    public static func estimate(age: Double, sex: Sex, waistCm: Double, restingHR: Double, activityIndex: Double) -> Double? {
        guard age >= 18, (40...200).contains(waistCm), (30...120).contains(restingHR) else { return nil }
        let pai = Stats.clip(activityIndex, 0, 15)
        let value: Double
        switch sex {
        case .male: value = 100.27 - 0.296 * age - 0.369 * waistCm - 0.155 * restingHR + 0.226 * pai
        case .female: value = 74.74 - 0.247 * age - 0.259 * waistCm - 0.114 * restingHR + 0.198 * pai
        case .unspecified: return nil
        }
        return (value * 10).rounded() / 10
    }

    /// Qué le falta al perfil para poder estimarlo (vacío si está completo).
    public static func missingInputs(profile: UserProfile) -> [String] {
        var out: [String] = []
        if profile.birthDate == nil { out.append("fecha de nacimiento") }
        if profile.sex == .unspecified { out.append("sexo") }
        if profile.waistCm == nil { out.append("perímetro de cintura") }
        if profile.activityQuestionnaire == nil { out.append("cuestionario de actividad") }
        return out
    }
}
