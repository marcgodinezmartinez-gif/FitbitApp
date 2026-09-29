import Foundation
import GRDB
import MetricsKit

// MARK: - Datos ampliados de los entrenamientos (doc. 18)

/// Pausa, vuelta, segmento o intervalo de un entreno.
public struct WorkoutEvent: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable { case pause, lap, segment, interval, marker }

    public var kind: Kind
    public var start: Date
    public var end: Date
    /// Pausa automática (el reloj o la pulsera detectaron que te habías parado).
    public var automatic: Bool

    public init(kind: Kind, start: Date, end: Date, automatic: Bool = false) {
        self.kind = kind
        self.start = start
        self.end = max(start, end)
        self.automatic = automatic
    }
}

/// Parcial o vuelta con las métricas que calcula la propia fuente (la Fitbit da las suyas por km y por vuelta).
public struct SourceSplit: Codable, Sendable, Hashable {
    public var start: Date
    public var end: Date
    /// km, manual, distance, duration, calories, segment o interval.
    public var kind: String
    public var distanceM: Double?
    public var activeSeconds: Double?
    public var avgHR: Double?
    public var avgCadence: Double?
    public var elevationGainM: Double?
    public var caloriesKcal: Double?
    public var steps: Int?

    public init(start: Date, end: Date, kind: String, distanceM: Double? = nil, activeSeconds: Double? = nil, avgHR: Double? = nil,
                avgCadence: Double? = nil, elevationGainM: Double? = nil, caloriesKcal: Double? = nil, steps: Int? = nil) {
        self.start = start
        self.end = max(start, end)
        self.kind = kind
        self.distanceM = distanceM
        self.activeSeconds = activeSeconds
        self.avgHR = avgHR
        self.avgCadence = avgCadence
        self.elevationGainM = elevationGainM
        self.caloriesKcal = caloriesKcal
        self.steps = steps
    }
}

public struct WeatherInfo: Codable, Sendable, Hashable {
    public var temperatureC: Double?
    public var humidityPct: Double?
    public var condition: String?

    public init(temperatureC: Double? = nil, humidityPct: Double? = nil, condition: String? = nil) {
        self.temperatureC = temperatureC
        self.humidityPct = humidityPct
        self.condition = condition
    }

    public var isEmpty: Bool { temperatureC == nil && humidityPct == nil && condition == nil }
}

/// Lo que da cada fuente de un entreno además del resumen: se guarda aparte y se carga al abrir su análisis.
public struct ActivityDetail: Codable, Sendable, Hashable {
    public var activityID: String
    public var events: [WorkoutEvent]
    /// Parciales por km calculados por la fuente (Fitbit).
    public var splits: [SourceSplit]
    /// Vueltas (Fitbit) o segmentos e intervalos (Apple Watch).
    public var laps: [SourceSplit]
    public var weather: WeatherInfo?
    public var elevationLossM: Double?
    /// Tiempo sin pausas según la fuente.
    public var activeSeconds: Double?
    public var avgMETs: Double?
    /// Fitbit: segundos en las zonas light, moderate, vigorous y peak.
    public var zoneSeconds: [String: Double]?
    public var activeZoneMinutes: Double?
    /// Fitbit: cadencia, zancada, oscilación vertical y contacto con el suelo medios.
    public var mobility: RunningDynamics?
    public var verticalRatioPct: Double?
    /// VO₂ máx. de esta carrera según la fuente.
    public var vo2max: Double?
    public var indoor: Bool?

    public init(activityID: String, events: [WorkoutEvent] = [], splits: [SourceSplit] = [], laps: [SourceSplit] = [],
                weather: WeatherInfo? = nil, elevationLossM: Double? = nil, activeSeconds: Double? = nil, avgMETs: Double? = nil,
                zoneSeconds: [String: Double]? = nil, activeZoneMinutes: Double? = nil, mobility: RunningDynamics? = nil,
                verticalRatioPct: Double? = nil, vo2max: Double? = nil, indoor: Bool? = nil) {
        self.activityID = activityID
        self.events = events
        self.splits = splits
        self.laps = laps
        self.weather = weather
        self.elevationLossM = elevationLossM
        self.activeSeconds = activeSeconds
        self.avgMETs = avgMETs
        self.zoneSeconds = zoneSeconds
        self.activeZoneMinutes = activeZoneMinutes
        self.mobility = mobility
        self.verticalRatioPct = verticalRatioPct
        self.vo2max = vo2max
        self.indoor = indoor
    }

    enum CodingKeys: String, CodingKey {
        case activityID, events, splits, laps, weather, elevationLossM, activeSeconds, avgMETs, zoneSeconds, activeZoneMinutes
        case mobility, verticalRatioPct, vo2max, indoor
    }

    /// Tolerante con campos que falten (versiones anteriores del formato).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activityID = try c.decode(String.self, forKey: .activityID)
        events = try c.decodeIfPresent([WorkoutEvent].self, forKey: .events) ?? []
        splits = try c.decodeIfPresent([SourceSplit].self, forKey: .splits) ?? []
        laps = try c.decodeIfPresent([SourceSplit].self, forKey: .laps) ?? []
        weather = try c.decodeIfPresent(WeatherInfo.self, forKey: .weather)
        elevationLossM = try c.decodeIfPresent(Double.self, forKey: .elevationLossM)
        activeSeconds = try c.decodeIfPresent(Double.self, forKey: .activeSeconds)
        avgMETs = try c.decodeIfPresent(Double.self, forKey: .avgMETs)
        zoneSeconds = try c.decodeIfPresent([String: Double].self, forKey: .zoneSeconds)
        activeZoneMinutes = try c.decodeIfPresent(Double.self, forKey: .activeZoneMinutes)
        mobility = try c.decodeIfPresent(RunningDynamics.self, forKey: .mobility)
        verticalRatioPct = try c.decodeIfPresent(Double.self, forKey: .verticalRatioPct)
        vo2max = try c.decodeIfPresent(Double.self, forKey: .vo2max)
        indoor = try c.decodeIfPresent(Bool.self, forKey: .indoor)
    }
}

// MARK: - Zapatillas

public struct Shoe: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    /// Km que ya tenían al empezar a registrarlas.
    public var startKm: Double
    /// Km a partir de los que conviene cambiarlas.
    public var limitKm: Double
    public var retired: Bool
    /// Se asignan solas a las carreras nuevas.
    public var isDefault: Bool
    public var addedAt: Date

    public init(id: String = UUID().uuidString, name: String, startKm: Double = 0, limitKm: Double = 700, retired: Bool = false,
                isDefault: Bool = false, addedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.startKm = startKm
        self.limitKm = limitKm
        self.retired = retired
        self.isDefault = isDefault
        self.addedAt = addedAt
    }
}

/// Envoltorio para guardar la lista en `app_state` (que guarda objetos, no listas).
struct ShoeCloset: Codable, Sendable {
    var shoes: [Shoe] = []
}

// MARK: - Repositorio

extension AppDatabase {
    public func saveActivityDetails(_ details: [ActivityDetail]) throws {
        guard !details.isEmpty else { return }
        try writer.write { db in
            let st = try db.makeStatement(sql: """
                INSERT INTO activity_detail(activity_id, json) VALUES (?, ?)
                ON CONFLICT(activity_id) DO UPDATE SET json = excluded.json
                """)
            for d in details { try st.execute(arguments: [d.activityID, try Self.json(d)]) }
        }
    }

    public func activityDetail(activityID: String) throws -> ActivityDetail? {
        try writer.read { db in
            try String.fetchOne(db, sql: "SELECT json FROM activity_detail WHERE activity_id = ?", arguments: [activityID])
                .flatMap { try? Self.decode(ActivityDetail.self, $0) }
        }
    }

    /// Muestras de FC de una fuente en un intervalo (las del entreno y las de alrededor).
    public func hrSamples(source: DataSourceKind, from: Date, to: Date) throws -> [HRSample] {
        try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT ts, bpm FROM hr_sample WHERE source = ? AND ts >= ? AND ts <= ? ORDER BY ts",
                             arguments: [source.rawValue, from.timeIntervalSince1970, to.timeIntervalSince1970])
                .map { HRSample(time: Date(timeIntervalSince1970: $0["ts"]), bpm: $0["bpm"], source: source) }
        }
    }

    public func hrSampleCount(source: DataSourceKind, from: Date, to: Date) throws -> Int {
        try writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM hr_sample WHERE source = ? AND ts >= ? AND ts <= ?",
                             arguments: [source.rawValue, from.timeIntervalSince1970, to.timeIntervalSince1970]) ?? 0
        }
    }

    // Zapatillas

    public func shoes() throws -> [Shoe] { try readState("shoes", default: ShoeCloset()).shoes }

    public func saveShoes(_ shoes: [Shoe]) throws { try writeState("shoes", ShoeCloset(shoes: shoes)) }

    // Caché de análisis por carrera (lo calcula RunKit; aquí solo se guarda el JSON con su versión).

    public func saveRunSummary(activityID: String, version: Int, start: Date, json: String) throws {
        try writer.write { db in
            try db.execute(sql: """
                INSERT INTO run_summary(activity_id, version, start_ts, json) VALUES (?, ?, ?, ?)
                ON CONFLICT(activity_id) DO UPDATE SET version = excluded.version, start_ts = excluded.start_ts, json = excluded.json
                """, arguments: [activityID, version, start.timeIntervalSince1970, json])
        }
    }

    public func runSummaries() throws -> [(activityID: String, version: Int, json: String)] {
        try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT activity_id, version, json FROM run_summary ORDER BY start_ts")
                .map { (activityID: $0["activity_id"], version: $0["version"], json: $0["json"]) }
        }
    }

    public func deleteRunSummaries(keeping ids: Set<String>) throws {
        let stale = try runSummaries().map(\.activityID).filter { !ids.contains($0) }
        guard !stale.isEmpty else { return }
        try writer.write { db in
            for id in stale { try db.execute(sql: "DELETE FROM run_summary WHERE activity_id = ?", arguments: [id]) }
        }
    }

    public func clearRunSummaries() throws {
        try writer.write { db in try db.execute(sql: "DELETE FROM run_summary") }
    }
}
