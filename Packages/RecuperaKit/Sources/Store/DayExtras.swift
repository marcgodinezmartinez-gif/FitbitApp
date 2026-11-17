import Foundation
import MetricsKit

/// Todo lo demás que mide la pulsera en un día y no entra en las puntuaciones (doc. 03 §4): el detalle de la noche (VFC y
/// SpO₂ muestra a muestra, respiración por fase, referencia de temperatura) y la actividad por intensidad (minutos activos,
/// minutos en zona, tiempo y calorías por zona de FC, sedentarismo, calorías activas, pisos y FC mínima, media y máxima).
public struct DayExtras: Codable, Sendable, Hashable {
    public struct Sample: Codable, Sendable, Hashable {
        public var t: Date
        public var v: Double

        public init(t: Date, v: Double) {
            self.t = t
            self.v = v
        }
    }

    public struct Zone: Codable, Sendable, Hashable {
        public var name: String
        public var min: Int
        public var max: Int

        public init(name: String, min: Int, max: Int) {
            self.name = name
            self.min = min
            self.max = max
        }
    }

    public var date: LocalDate

    // La noche que termina este día.
    public var hrvEntropy: Double?
    public var spo2Lower: Double?
    public var spo2Upper: Double?
    public var spo2Stddev: Double?
    public var tempBaselineC: Double?
    public var tempStddevC: Double?
    public var respLight: Double?
    public var respDeep: Double?
    public var respRem: Double?
    public var hrvSamples: [Sample]?
    public var spo2Samples: [Sample]?

    // El día.
    public var activeMinLight: Int?
    public var activeMinModerate: Int?
    public var activeMinVigorous: Int?
    public var azmFatBurn: Int?
    public var azmCardio: Int?
    public var azmPeak: Int?
    /// Minutos en cada zona de FC de Google: LIGHT, MODERATE, VIGOROUS, PEAK.
    public var zoneMinutes: [String: Double]?
    public var zoneKcal: [String: Double]?
    public var sedentaryMin: Double?
    /// Minutos por nivel de actividad: SEDENTARY, LIGHTLY_ACTIVE, MODERATELY_ACTIVE, VERY_ACTIVE.
    public var levelMinutes: [String: Double]?
    public var activeKcal: Double?
    public var floors: Int?
    public var elevationGainM: Double?
    public var hrMin: Double?
    public var hrAvg: Double?
    public var hrMax: Double?
    public var hrZones: [Zone]?

    public init(date: LocalDate) { self.date = date }

    public static let zoneOrder = ["LIGHT", "MODERATE", "VIGOROUS", "PEAK"]
    public static let levelOrder = ["SEDENTARY", "LIGHTLY_ACTIVE", "MODERATELY_ACTIVE", "VERY_ACTIVE"]

    public static func zoneLabel(_ key: String) -> String {
        switch key {
        case "LIGHT": return "Suave"
        case "MODERATE": return "Moderada"
        case "VIGOROUS": return "Intensa"
        case "PEAK": return "Máxima"
        case "SEDENTARY": return "Sedentario"
        case "LIGHTLY_ACTIVE": return "Poco activo"
        case "MODERATELY_ACTIVE": return "Bastante activo"
        case "VERY_ACTIVE": return "Muy activo"
        default: return key.capitalized
        }
    }

    /// Minutos en zona activa: los de cardio y pico cuentan doble (así los suma Google).
    public var azmTotal: Int? {
        guard azmFatBurn != nil || azmCardio != nil || azmPeak != nil else { return nil }
        return (azmFatBurn ?? 0) + (azmCardio ?? 0) + (azmPeak ?? 0)
    }

    public var activeMinTotal: Int? {
        guard activeMinLight != nil || activeMinModerate != nil || activeMinVigorous != nil else { return nil }
        return (activeMinLight ?? 0) + (activeMinModerate ?? 0) + (activeMinVigorous ?? 0)
    }

    /// Cuánto se aparta la temperatura de esta noche de tu referencia de 30 días.
    public func tempDeviation(nightlyC: Double?) -> Double? {
        guard let nightlyC, let tempBaselineC else { return nil }
        return nightlyC - tempBaselineC
    }

    public var hasNight: Bool {
        hrvEntropy != nil || spo2Lower != nil || tempBaselineC != nil || respLight != nil || respDeep != nil || respRem != nil
            || !(hrvSamples ?? []).isEmpty || !(spo2Samples ?? []).isEmpty
    }

    public var hasDay: Bool {
        activeMinTotal != nil || azmTotal != nil || !(zoneMinutes ?? [:]).isEmpty || sedentaryMin != nil || !(levelMinutes ?? [:]).isEmpty
            || activeKcal != nil || hrAvg != nil || (floors ?? 0) > 0
    }

    /// Día de ejemplo para el modo demostración (siempre el mismo para la misma fecha).
    public static func demo(date: LocalDate, sleepStart: Date?, sleepEnd: Date?, hrv: Double?, restingHR: Double?, strain: Double) -> DayExtras {
        var x = DayExtras(date: date)
        var seed = UInt64(truncatingIfNeeded: date.year * 10_000 + date.month * 100 + date.day) &* 6_364_136_223_846_793_005 &+ 1
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 33) / Double(1 << 31)
        }
        let effort = Swift.min(1, Swift.max(0, strain / 18))
        x.hrvEntropy = 2.4 + next() * 0.8
        x.spo2Lower = 92.5 + next() * 1.5
        x.spo2Upper = 98 + next() * 1.5
        x.spo2Stddev = 0.8 + next() * 0.6
        x.tempBaselineC = 33.6
        x.tempStddevC = 0.35
        let rr = 14.2 + next()
        x.respLight = rr + 0.4
        x.respDeep = rr - 0.6
        x.respRem = rr + 0.9
        if let a = sleepStart, let b = sleepEnd, b > a {
            let base = hrv ?? 55
            var h: [Sample] = [], o: [Sample] = []
            var t = a.addingTimeInterval(600)
            var i = 0.0
            while t < b {
                h.append(Sample(t: t, v: Swift.max(15, base * (0.8 + 0.25 * sin(i / 5) + 0.25 * next()))))
                o.append(Sample(t: t, v: Swift.min(100, 95.5 + 1.5 * sin(i / 7) + 1.2 * next())))
                t = t.addingTimeInterval(300)
                i += 1
            }
            x.hrvSamples = h
            x.spo2Samples = o
        }
        x.activeMinLight = Int(90 + 80 * next())
        x.activeMinModerate = Int(10 + 40 * effort + 10 * next())
        x.activeMinVigorous = Int(45 * effort * next())
        x.azmFatBurn = Int(8 + 35 * effort)
        x.azmCardio = Int(40 * effort * next()) * 2
        x.azmPeak = Int(8 * effort * next()) * 2
        x.zoneMinutes = ["LIGHT": 60 + 120 * next(), "MODERATE": 8 + 35 * effort, "VIGOROUS": 20 * effort * next(), "PEAK": 4 * effort * next()]
        x.zoneKcal = ["LIGHT": 180 + 200 * next(), "MODERATE": 60 + 250 * effort, "VIGOROUS": 220 * effort * next(), "PEAK": 60 * effort * next()]
        x.sedentaryMin = 560 + 180 * next()
        x.levelMinutes = ["SEDENTARY": x.sedentaryMin ?? 600, "LIGHTLY_ACTIVE": 150 + 80 * next(), "MODERATELY_ACTIVE": 15 + 40 * effort,
                          "VERY_ACTIVE": 5 + 50 * effort * next()]
        x.activeKcal = 320 + 700 * effort + 120 * next()
        let rest = restingHR ?? 54
        x.hrMin = rest - 4
        x.hrAvg = rest + 14 + 8 * effort
        x.hrMax = rest + 55 + 70 * effort
        x.hrZones = [Zone(name: "LIGHT", min: 95, max: 114), Zone(name: "MODERATE", min: 115, max: 137),
                     Zone(name: "VIGOROUS", min: 138, max: 167), Zone(name: "PEAK", min: 168, max: 220)]
        return x
    }
}

extension AppDatabase {
    /// Guarda los datos ampliados de cada día; lo que llega nuevo sustituye a lo guardado y lo que no llega se conserva.
    public func mergeDayExtras(_ items: [DayExtras]) throws {
        guard !items.isEmpty else { return }
        try writer.write { db in
            for x in items {
                var merged = x
                if let json = try String.fetchOne(db, sql: "SELECT json FROM day_extras WHERE date = ?", arguments: [x.date.isoString]),
                   let old = try? Self.decode(DayExtras.self, json) {
                    merged = Self.decodeMerging(try Self.json(x), defaults: old)
                }
                try db.execute(sql: "INSERT INTO day_extras(date, json) VALUES (?, ?) ON CONFLICT(date) DO UPDATE SET json = excluded.json",
                               arguments: [x.date.isoString, try Self.json(merged)])
            }
        }
    }

    public func dayExtras(on date: LocalDate) throws -> DayExtras? {
        try writer.read { db in
            try String.fetchOne(db, sql: "SELECT json FROM day_extras WHERE date = ?", arguments: [date.isoString])
                .flatMap { try? Self.decode(DayExtras.self, $0) }
        }
    }

    /// Los días de un periodo (extremos incluidos), del más antiguo al más reciente.
    public func dayExtras(from: LocalDate, to: LocalDate) throws -> [DayExtras] {
        try writer.read { db in
            try String.fetchAll(db, sql: "SELECT json FROM day_extras WHERE date >= ? AND date <= ? ORDER BY date",
                                arguments: [from.isoString, to.isoString])
                .compactMap { try? Self.decode(DayExtras.self, $0) }
        }
    }
}
