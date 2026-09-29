import Foundation

// Modelos de la Google Health API v4 (documento de descubrimiento, revisión 20260928).
// Los int64 llegan como cadenas, las duraciones como "3600s" y los decimales sin dato como "NaN".

/// Entero que puede llegar como número o como cadena (int64 en JSON de Google).
public struct FlexInt: Codable, Sendable, Hashable {
    public var value: Int64

    public init(_ v: Int64) { value = v }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int64.self) { value = i; return }
        if let d = try? c.decode(Double.self) { value = Int64(d); return }
        let s = try c.decode(String.self)
        guard let i = Int64(s) else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "int64 no válido: \(s)") }
        value = i
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(String(value))
    }
}

/// Decimal tolerante: número, número en texto o los valores especiales de JSON de Google ("NaN", "Infinity"), que llegan
/// como cadena cuando no hay dato (p. ej. la temperatura de referencia de las primeras noches). Lo que no es un número
/// finito se lee como `nil` en lugar de invalidar toda la respuesta.
@propertyWrapper
public struct FlexDouble: Codable, Sendable, Hashable {
    public var wrappedValue: Double?

    public init(wrappedValue: Double?) { self.wrappedValue = wrappedValue }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) {
            wrappedValue = d.isFinite ? d : nil
        } else if let s = try? c.decode(String.self), let d = Double(s.trimmingCharacters(in: .whitespaces)), d.isFinite {
            wrappedValue = d
        } else {
            wrappedValue = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let wrappedValue { try c.encode(wrappedValue) } else { try c.encodeNil() }
    }
}

extension KeyedDecodingContainer {
    /// Un `@FlexDouble` que no viene en el JSON vale `nil` (la conformidad sintetizada llama a `decode`, no a `decodeIfPresent`).
    public func decode(_ type: FlexDouble.Type, forKey key: Key) throws -> FlexDouble {
        try decodeIfPresent(type, forKey: key) ?? FlexDouble(wrappedValue: nil)
    }
}

extension KeyedEncodingContainer {
    public mutating func encode(_ value: FlexDouble, forKey key: Key) throws {
        try encodeIfPresent(value.wrappedValue, forKey: key)
    }
}

/// Lista que descarta los elementos ilegibles en lugar de fallar entera: un punto raro no bloquea la importación.
struct LossyList<Element: Decodable>: Decodable {
    var elements: [Element] = []
    var skipped = 0

    private struct Skip: Decodable {
        init(from decoder: Decoder) throws {}
    }

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        while !c.isAtEnd {
            if let e = try? c.decode(Element.self) {
                elements.append(e)
                continue
            }
            skipped += 1
            // Se salta el elemento; si ni así avanza, se para para no quedarse en bucle.
            if (try? c.decode(Skip.self)) == nil { break }
        }
    }
}

public enum GoogleTime {
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        return plain.date(from: s) ?? fractional.date(from: s) ?? {
            // Más de 3 decimales (nanosegundos): se recortan.
            guard let dot = s.firstIndex(of: "."), let zone = s[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) else { return nil }
            let frac = s[s.index(after: dot)..<zone].prefix(3)
            return fractional.date(from: String(s[..<dot]) + "." + frac + String(s[zone...]))
        }()
    }

    public static func string(_ d: Date) -> String { plain.string(from: d) }

    /// "7200s" → 7200; "-18000s" → −18000.
    public static func seconds(_ duration: String?) -> Double? {
        guard var s = duration else { return nil }
        if s.hasSuffix("s") { s.removeLast() }
        return Double(s)
    }
}

public struct APIDate: Codable, Sendable, Hashable {
    public var year: Int?
    public var month: Int?
    public var day: Int?

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }
}

public struct APITimeOfDay: Codable, Sendable, Hashable {
    public var hours: Int?
    public var minutes: Int?
    public var seconds: Int?
}

public struct CivilDateTime: Codable, Sendable, Hashable {
    public var date: APIDate?
    public var time: APITimeOfDay?

    public init(date: APIDate, time: APITimeOfDay? = nil) {
        self.date = date
        self.time = time
    }
}

public struct SampleTime: Codable, Sendable, Hashable {
    public var physicalTime: String?
    public var utcOffset: String?
    public var civilTime: CivilDateTime?
}

public struct TimeInterval_: Codable, Sendable, Hashable {
    public var startTime: String?
    public var endTime: String?
    public var startUtcOffset: String?
    public var endUtcOffset: String?
}

public struct DataSourceInfo: Codable, Sendable, Hashable {
    public struct Device: Codable, Sendable, Hashable {
        public var manufacturer: String?
        public var formFactor: String?
        public var displayName: String?
    }

    public struct Application: Codable, Sendable, Hashable {
        public var packageName: String?
    }

    public var platform: String?
    public var recordingMethod: String?
    public var device: Device?
    public var application: Application?
}

public struct HeartRatePoint: Codable, Sendable, Hashable {
    public var beatsPerMinute: FlexInt?
    public var sampleTime: SampleTime?
}

public struct DailyHRVPoint: Codable, Sendable, Hashable {
    public var date: APIDate?
    @FlexDouble public var averageHeartRateVariabilityMilliseconds: Double?
    @FlexDouble public var deepSleepRootMeanSquareOfSuccessiveDifferencesMilliseconds: Double?
    public var nonRemHeartRateBeatsPerMinute: FlexInt?
    @FlexDouble public var entropy: Double?
}

public struct DailyRestingHRPoint: Codable, Sendable, Hashable {
    public var date: APIDate?
    public var beatsPerMinute: FlexInt?
}

public struct DailyOxygenPoint: Codable, Sendable, Hashable {
    public var date: APIDate?
    @FlexDouble public var averagePercentage: Double?
    @FlexDouble public var lowerBoundPercentage: Double?
    @FlexDouble public var upperBoundPercentage: Double?
}

public struct DailyRespiratoryPoint: Codable, Sendable, Hashable {
    public var date: APIDate?
    @FlexDouble public var breathsPerMinute: Double?
}

public struct DailyTemperaturePoint: Codable, Sendable, Hashable {
    public var date: APIDate?
    @FlexDouble public var nightlyTemperatureCelsius: Double?
    @FlexDouble public var baselineTemperatureCelsius: Double?
    @FlexDouble public var relativeNightlyStddev30dCelsius: Double?
}

public struct SleepStagePoint: Codable, Sendable, Hashable {
    public var type: String?
    public var startTime: String?
    public var endTime: String?
    public var startUtcOffset: String?
}

public struct SleepPoint: Codable, Sendable, Hashable {
    public struct Metadata: Codable, Sendable, Hashable {
        public var mainSleep: Bool?
        public var nap: Bool?
        public var externalId: String?
        public var manuallyEdited: Bool?
        public var processed: Bool?
    }

    public struct Summary: Codable, Sendable, Hashable {
        public var minutesAsleep: FlexInt?
        public var minutesAwake: FlexInt?
        public var minutesToFallAsleep: FlexInt?
        public var minutesInSleepPeriod: FlexInt?
    }

    public var interval: TimeInterval_?
    public var stages: [SleepStagePoint]?
    public var metadata: Metadata?
    public var summary: Summary?
    public var type: String?
    public var updateTime: String?
}

public struct ExercisePoint: Codable, Sendable, Hashable {
    public struct Metrics: Codable, Sendable, Hashable {
        @FlexDouble public var caloriesKcal: Double?
        public var steps: FlexInt?
        @FlexDouble public var distanceMillimeters: Double?
        public var averageHeartRateBeatsPerMinute: FlexInt?
        @FlexDouble public var elevationGainMillimeters: Double?
        @FlexDouble public var averageSpeedMillimetersPerSecond: Double?
        @FlexDouble public var runVo2Max: Double?
    }

    public struct Metadata: Codable, Sendable, Hashable {
        public var hasGps: Bool?
    }

    public var exerciseType: String?
    public var displayName: String?
    public var interval: TimeInterval_?
    public var metricsSummary: Metrics?
    public var exerciseMetadata: Metadata?
    public var notes: String?
    public var updateTime: String?
}

public struct IntervalCount: Codable, Sendable, Hashable {
    public var interval: TimeInterval_?
    public var count: FlexInt?
    public var millimeters: FlexInt?
}

public struct VO2Point: Codable, Sendable, Hashable {
    public var sampleTime: SampleTime?
    @FlexDouble public var vo2Max: Double?
}

public struct DailyVO2Point: Codable, Sendable, Hashable {
    public var date: APIDate?
    @FlexDouble public var vo2Max: Double?
    public var estimated: Bool?
}

public struct RunVO2Point: Codable, Sendable, Hashable {
    public var sampleTime: SampleTime?
    @FlexDouble public var runVo2Max: Double?
}

/// Punto de datos (`list`) o punto reconciliado (`reconcile`): un campo por tipo.
public struct APIDataPoint: Codable, Sendable, Hashable {
    public var name: String?
    public var dataPointName: String?
    public var dataSource: DataSourceInfo?
    public var heartRate: HeartRatePoint?
    public var dailyHeartRateVariability: DailyHRVPoint?
    public var dailyRestingHeartRate: DailyRestingHRPoint?
    public var dailyOxygenSaturation: DailyOxygenPoint?
    public var dailyRespiratoryRate: DailyRespiratoryPoint?
    public var dailySleepTemperatureDerivations: DailyTemperaturePoint?
    public var sleep: SleepPoint?
    public var exercise: ExercisePoint?
    public var steps: IntervalCount?
    public var distance: IntervalCount?
    public var vo2Max: VO2Point?
    public var dailyVo2Max: DailyVO2Point?
    public var runVo2Max: RunVO2Point?

    public var identifier: String? { name ?? dataPointName }
}

public struct ListDataPointsResponse: Codable, Sendable {
    public var dataPoints: [APIDataPoint]?
    public var nextPageToken: String?
    /// Puntos ilegibles descartados en esta página.
    public var skipped = 0

    enum CodingKeys: String, CodingKey { case dataPoints, nextPageToken }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let list = try c.decodeIfPresent(LossyList<APIDataPoint>.self, forKey: .dataPoints)
        dataPoints = list?.elements
        skipped = list?.skipped ?? 0
        nextPageToken = try c.decodeIfPresent(String.self, forKey: .nextPageToken)
    }
}

public struct RollupDataPoint: Codable, Sendable, Hashable {
    public struct HR: Codable, Sendable, Hashable {
        @FlexDouble public var beatsPerMinuteAvg: Double?
        @FlexDouble public var beatsPerMinuteMin: Double?
        @FlexDouble public var beatsPerMinuteMax: Double?
    }

    public struct StepsSum: Codable, Sendable, Hashable { public var countSum: FlexInt? }
    public struct DistanceSum: Codable, Sendable, Hashable { public var millimetersSum: FlexInt? }
    public struct CaloriesSum: Codable, Sendable, Hashable { @FlexDouble public var kcalSum: Double? }

    public var startTime: String?
    public var endTime: String?
    public var civilStartTime: CivilDateTime?
    public var civilEndTime: CivilDateTime?
    public var heartRate: HR?
    public var steps: StepsSum?
    public var distance: DistanceSum?
    public var totalCalories: CaloriesSum?
}

public struct RollUpResponse: Codable, Sendable {
    public var rollupDataPoints: [RollupDataPoint]?
    public var nextPageToken: String?
    /// Puntos ilegibles descartados en esta página.
    public var skipped = 0

    enum CodingKeys: String, CodingKey { case rollupDataPoints, nextPageToken }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let list = try c.decodeIfPresent(LossyList<RollupDataPoint>.self, forKey: .rollupDataPoints)
        rollupDataPoints = list?.elements
        skipped = list?.skipped ?? 0
        nextPageToken = try c.decodeIfPresent(String.self, forKey: .nextPageToken)
    }
}

public struct PairedDevice: Codable, Sendable, Hashable {
    public var name: String?
    public var deviceVersion: String?
    public var deviceType: String?
    public var lastSyncTime: String?
    public var batteryLevel: Int?
    public var batteryStatus: String?
    public var features: [String]?
}

public struct PairedDevicesResponse: Codable, Sendable {
    public var pairedDevices: [PairedDevice]?
    public var nextPageToken: String?
}

public struct Identity: Codable, Sendable, Hashable {
    public var name: String?
    public var healthUserId: String?
    public var legacyUserId: String?
}

public struct UserSettings: Codable, Sendable, Hashable {
    public var timeZone: String?
    public var utcOffset: String?
    public var distanceUnit: String?
    public var languageLocale: String?
}

public struct UserProfileAPI: Codable, Sendable, Hashable {
    public var age: Int?
    public var membershipStartDate: APIDate?
}
