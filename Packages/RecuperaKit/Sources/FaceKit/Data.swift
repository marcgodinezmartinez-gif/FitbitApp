import Foundation

/// Lo que enseñan las esferas: lo que calcula el iPhone (recuperación, carga, sueño, plan…) y lo que mide el propio reloj
/// (pulso, pasos, anillos, batería, brújula, el tiempo). Todo opcional: lo que falte sale como «–».
public struct FaceData: Codable, Sendable, Hashable {
    /// Cuándo mandó el iPhone sus datos.
    public var updatedAt: Date?

    // Del iPhone.
    public var recovery: Int?
    /// «high», «medium» o «low» (como en los widgets).
    public var recoveryZone: String?
    public var strain: Double?
    public var strainTargetLow: Double?
    public var strainTargetHigh: Double?
    public var sleepPerformance: Int?
    public var sleepMinutes: Int?
    public var hrv: Double?
    public var restingHR: Double?
    /// «23:10».
    public var bedtime: String?
    public var workout: FaceWorkout?
    public var race: FaceRace?

    // Del reloj.
    public var heartRate: Double?
    public var heartRateAt: Date?
    /// Pulso de la última hora, del más antiguo al último (un valor cada pocos minutos).
    public var heartRateTrend: [Double]?
    public var steps: Int?
    public var rings: FaceRings?
    /// 0–1.
    public var battery: Double?
    /// Grados desde el norte.
    public var heading: Double?
    public var weather: FaceWeather?

    public init(updatedAt: Date? = nil, recovery: Int? = nil, recoveryZone: String? = nil, strain: Double? = nil,
                strainTargetLow: Double? = nil, strainTargetHigh: Double? = nil, sleepPerformance: Int? = nil, sleepMinutes: Int? = nil,
                hrv: Double? = nil, restingHR: Double? = nil, bedtime: String? = nil, workout: FaceWorkout? = nil, race: FaceRace? = nil,
                heartRate: Double? = nil, heartRateAt: Date? = nil, heartRateTrend: [Double]? = nil, steps: Int? = nil,
                rings: FaceRings? = nil, battery: Double? = nil, heading: Double? = nil, weather: FaceWeather? = nil) {
        self.updatedAt = updatedAt
        self.recovery = recovery
        self.recoveryZone = recoveryZone
        self.strain = strain
        self.strainTargetLow = strainTargetLow
        self.strainTargetHigh = strainTargetHigh
        self.sleepPerformance = sleepPerformance
        self.sleepMinutes = sleepMinutes
        self.hrv = hrv
        self.restingHR = restingHR
        self.bedtime = bedtime
        self.workout = workout
        self.race = race
        self.heartRate = heartRate
        self.heartRateAt = heartRateAt
        self.heartRateTrend = heartRateTrend
        self.steps = steps
        self.rings = rings
        self.battery = battery
        self.heading = heading
        self.weather = weather
    }

    /// Los datos del iPhone con lo que ha medido el reloj encima (lo del reloj manda si lo tiene).
    public func merged(withWatch w: FaceData) -> FaceData {
        var d = self
        d.heartRate = w.heartRate ?? heartRate
        d.heartRateAt = w.heartRateAt ?? heartRateAt
        d.heartRateTrend = w.heartRateTrend ?? heartRateTrend
        d.steps = w.steps ?? steps
        d.rings = w.rings ?? rings
        d.battery = w.battery ?? battery
        d.heading = w.heading ?? heading
        d.weather = w.weather ?? weather
        return d
    }

    /// Solo lo que manda el iPhone (lo del reloj se mide allí).
    public var phoneOnly: FaceData {
        var d = self
        d.heartRate = nil
        d.heartRateAt = nil
        d.heartRateTrend = nil
        d.steps = nil
        d.rings = nil
        d.battery = nil
        d.heading = nil
        d.weather = nil
        return d
    }

    /// Datos de ejemplo para el modo demostración y las capturas.
    public static func demo(now: Date = Date()) -> FaceData {
        FaceData(updatedAt: now, recovery: 72, recoveryZone: "high", strain: 11.4, strainTargetLow: 12, strainTargetHigh: 15,
                 sleepPerformance: 92, sleepMinutes: 442, hrv: 64, restingHR: 51, bedtime: "23:10",
                 workout: FaceWorkout(title: "Series 6 × 800 m", detail: "8,5 km · 50 min", symbol: "bolt.heart.fill"),
                 race: FaceRace(name: "10K de Valencia", date: now.addingTimeInterval(74 * 86_400), distanceText: "10 km"),
                 heartRate: 64, heartRateAt: now,
                 heartRateTrend: [58, 60, 59, 63, 72, 95, 118, 124, 121, 104, 86, 74, 68, 66, 64],
                 steps: 8_412, rings: FaceRings(move: 0.72, exercise: 0.85, stand: 0.58), battery: 0.82, heading: 38,
                 weather: FaceWeather(temperatureC: 19, code: 2, isDay: true, updatedAt: now))
    }
}

/// El entreno que toca hoy según tu plan.
public struct FaceWorkout: Codable, Sendable, Hashable {
    public var title: String
    public var detail: String?
    /// Símbolo SF del tipo de sesión.
    public var symbol: String?
    public var done: Bool

    public init(title: String, detail: String? = nil, symbol: String? = nil, done: Bool = false) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.done = done
    }
}

/// Tu carrera objetivo.
public struct FaceRace: Codable, Sendable, Hashable {
    public var name: String
    public var date: Date
    public var distanceText: String?

    public init(name: String, date: Date, distanceText: String? = nil) {
        self.name = name
        self.date = date
        self.distanceText = distanceText
    }
}

/// Anillos de actividad (fracción del objetivo; pueden pasar de 1).
public struct FaceRings: Codable, Sendable, Hashable {
    public var move: Double
    public var exercise: Double
    public var stand: Double

    public init(move: Double, exercise: Double, stand: Double) {
        self.move = move
        self.exercise = exercise
        self.stand = stand
    }
}

/// El tiempo que hace ahora donde está el reloj (Open-Meteo).
public struct FaceWeather: Codable, Sendable, Hashable {
    public var temperatureC: Double
    /// Código WMO.
    public var code: Int
    public var isDay: Bool
    public var updatedAt: Date

    public init(temperatureC: Double, code: Int, isDay: Bool, updatedAt: Date) {
        self.temperatureC = temperatureC
        self.code = code
        self.isDay = isDay
        self.updatedAt = updatedAt
    }

    public var symbol: String { FaceWeatherService.describe(code: code, isDay: isDay).symbol }
    public var text: String { FaceWeatherService.describe(code: code, isDay: isDay).text }
}
