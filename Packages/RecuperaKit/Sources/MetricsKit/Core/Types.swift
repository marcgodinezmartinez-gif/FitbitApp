import Foundation

/// Origen de un dato (doc. 09): la Fitbit Air llega por la Google Health API,
/// el Apple Watch por Salud (HealthKit) y lo registrado en la app es manual.
public enum DataSourceKind: String, Codable, Sendable, CaseIterable, Hashable {
    case googleHealth = "google_health"
    case appleHealth = "apple_health"
    case manual

    /// Nombre del dispositivo que se muestra en la interfaz.
    public var deviceName: String {
        switch self {
        case .googleHealth: return "Fitbit Air"
        case .appleHealth: return "Apple Watch"
        case .manual: return "Manual"
        }
    }

    /// Identificador que usa el esquema del análisis del día (ALG-ANA-01).
    public var analysisSourceID: String {
        switch self {
        case .googleHealth: return "fitbit_air"
        case .appleHealth: return "apple_watch"
        case .manual: return "manual"
        }
    }
}

public enum Sex: String, Codable, Sendable, CaseIterable {
    case male, female, unspecified
}

public enum Confidence: String, Codable, Sendable, Comparable {
    case low, medium, high

    private var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    public static func < (lhs: Confidence, rhs: Confidence) -> Bool { lhs.rank < rhs.rank }

    /// Baja un nivel (p. ej. cuando falta un componente secundario).
    public var lowered: Confidence {
        switch self {
        case .high: return .medium
        case .medium, .low: return .low
        }
    }
}

/// Fecha civil (sin hora ni zona), como `Date` de la Google Health API.
public struct LocalDate: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Fecha local de un instante con un desfase UTC en segundos.
    public init(_ date: Date, utcOffsetSeconds: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: utcOffsetSeconds) ?? TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// Fecha local de un instante en una zona horaria.
    public init(_ date: Date, timeZone: TimeZone) {
        self.init(date, utcOffsetSeconds: timeZone.secondsFromGMT(for: date))
    }

    /// Admite "2026-09-29".
    public init?(isoString: String) {
        let parts = isoString.prefix(10).split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public var isoString: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public var description: String { isoString }

    /// Número de días desde 1970-01-01 (útil para restar fechas).
    public var dayNumber: Int {
        // Algoritmo de días desde la época para el calendario gregoriano proléptico.
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    public init(dayNumber z0: Int) {
        let z = z0 + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        self.init(year: m <= 2 ? y + 1 : y, month: m, day: d)
    }

    public func adding(days: Int) -> LocalDate { LocalDate(dayNumber: dayNumber + days) }
    public func days(since other: LocalDate) -> Int { dayNumber - other.dayNumber }

    /// 1 = lunes … 7 = domingo.
    public var isoWeekday: Int {
        let w = (dayNumber + 3) % 7 // 1970-01-01 fue jueves
        return (w < 0 ? w + 7 : w) + 1
    }

    public var isWeekend: Bool { isoWeekday >= 6 }

    /// Medianoche local de esta fecha con un desfase dado.
    public func startDate(utcOffsetSeconds: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(dayNumber * 86_400 - utcOffsetSeconds))
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool { lhs.dayNumber < rhs.dayNumber }
}

extension Date {
    /// Inicio del minuto (UTC) como segundos desde la época.
    public var minuteEpoch: Int { Int((timeIntervalSince1970 / 60).rounded(.down)) * 60 }
}

/// Intervalo semiabierto [start, end).
public struct TimeRange: Hashable, Codable, Sendable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = max(start, end)
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
    public var minutes: Double { duration / 60 }

    public func contains(_ date: Date) -> Bool { date >= start && date < end }

    public func overlap(with other: TimeRange) -> TimeInterval {
        let s = max(start, other.start)
        let e = min(end, other.end)
        return max(0, e.timeIntervalSince(s))
    }

    public func intersects(_ other: TimeRange) -> Bool { overlap(with: other) > 0 }

    /// Partes de este intervalo que no cubre ninguno de `others`.
    public func subtracting(_ others: [TimeRange]) -> [TimeRange] {
        var pieces = [self]
        for o in others {
            var next: [TimeRange] = []
            for p in pieces {
                if !p.intersects(o) { next.append(p); continue }
                if o.start > p.start { next.append(TimeRange(start: p.start, end: o.start)) }
                if o.end < p.end { next.append(TimeRange(start: o.end, end: p.end)) }
            }
            pieces = next
        }
        return pieces.filter { $0.duration > 0 }
    }
}
