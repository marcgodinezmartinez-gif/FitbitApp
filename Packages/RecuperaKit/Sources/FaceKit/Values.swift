import Foundation

/// Color con significado: la interfaz lo convierte en un color de verdad (y en rojo en el modo noche).
public enum FaceTint: String, Sendable, Hashable {
    case accent, primary, recoveryHigh, recoveryMedium, recoveryLow, strain, sleep, heart, move, exercise, stand, weather
}

/// Un dato listo para pintar en un hueco.
public struct FaceValue: Sendable, Hashable {
    /// Rótulo corto en mayúsculas: «REC», «PULSO».
    public var title: String
    /// La cifra: «72», «11,4», «7:22».
    public var text: String
    /// «%», «lpm»…
    public var unit: String?
    /// Una línea más: «Buena», «8,5 km · 50 min».
    public var detail: String?
    /// Para los aros y barras (0–1).
    public var fraction: Double?
    public var tint: FaceTint
    /// Símbolo SF.
    public var symbol: String?

    public init(title: String, text: String, unit: String? = nil, detail: String? = nil, fraction: Double? = nil,
                tint: FaceTint = .accent, symbol: String? = nil) {
        self.title = title
        self.text = text
        self.unit = unit
        self.detail = detail
        self.fraction = fraction
        self.tint = tint
        self.symbol = symbol
    }

    /// «72 %», «64 lpm».
    public var textWithUnit: String { unit.map { "\(text) \($0)" } ?? text }
}

/// Textos de las esferas, en español.
public enum FaceValues {
    public static let missing = "–"
    static let weekdays = ["DOM", "LUN", "MAR", "MIÉ", "JUE", "VIE", "SÁB"]
    static let months = ["ENE", "FEB", "MAR", "ABR", "MAY", "JUN", "JUL", "AGO", "SEPT", "OCT", "NOV", "DIC"]

    /// El dato de un hueco; `nil` si el hueco está vacío.
    public static func value(_ c: FaceComplication, _ d: FaceData, now: Date, calendar: Calendar = .current) -> FaceValue? {
        switch c {
        case .none:
            return nil
        case .recovery:
            return FaceValue(title: "REC", text: d.recovery.map { "\($0)" } ?? missing, unit: d.recovery == nil ? nil : "%",
                             detail: zoneText(d.recoveryZone), fraction: d.recovery.map { Double($0) / 100 },
                             tint: recoveryTint(d.recoveryZone), symbol: "arrow.clockwise.heart.fill")
        case .strain:
            var detail: String?
            if let lo = d.strainTargetLow, let hi = d.strainTargetHigh { detail = "Objetivo \(decimal(lo, digits: 0))–\(decimal(hi, digits: 0))" }
            return FaceValue(title: "CARGA", text: d.strain.map { decimal($0, digits: 1) } ?? missing, detail: detail,
                             fraction: d.strain.map { min(1, $0 / 21) }, tint: .strain, symbol: "flame.fill")
        case .sleep:
            return FaceValue(title: "SUEÑO", text: d.sleepMinutes.map { clockDuration(minutes: $0) } ?? missing,
                             detail: d.sleepPerformance.map { "\($0) % de lo que necesitabas" },
                             fraction: d.sleepPerformance.map { min(1, Double($0) / 100) }, tint: .sleep, symbol: "bed.double.fill")
        case .summary:
            let parts = [d.recovery.map { "\($0) %" } ?? missing, d.strain.map { decimal($0, digits: 1) } ?? missing,
                         d.sleepMinutes.map { clockDuration(minutes: $0) } ?? missing]
            let empty = d.recovery == nil && d.strain == nil && d.sleepMinutes == nil
            return FaceValue(title: "HOY", text: empty ? missing : parts.joined(separator: " · "), detail: "Recuperación · carga · sueño",
                             fraction: d.recovery.map { Double($0) / 100 }, tint: recoveryTint(d.recoveryZone),
                             symbol: "arrow.clockwise.heart.fill")
        case .hrv:
            return FaceValue(title: "VFC", text: d.hrv.map { "\(Int($0.rounded()))" } ?? missing, unit: d.hrv == nil ? nil : "ms",
                             tint: .sleep, symbol: "waveform.path.ecg")
        case .restingHR:
            return FaceValue(title: "REPOSO", text: d.restingHR.map { "\(Int($0.rounded()))" } ?? missing,
                             unit: d.restingHR == nil ? nil : "lpm", tint: .heart, symbol: "heart")
        case .bedtime:
            return FaceValue(title: "A DORMIR", text: d.bedtime ?? missing, tint: .sleep, symbol: "moon.zzz.fill")
        case .heartRate:
            var detail: String?
            if let trend = d.heartRateTrend, let lo = trend.min(), let hi = trend.max() {
                detail = "Última hora: \(Int(lo.rounded()))–\(Int(hi.rounded()))"
            }
            return FaceValue(title: "PULSO", text: d.heartRate.map { "\(Int($0.rounded()))" } ?? missing,
                             unit: d.heartRate == nil ? nil : "lpm", detail: detail,
                             fraction: d.heartRate.map { min(1, max(0, ($0 - 40) / 150)) }, tint: .heart, symbol: "heart.fill")
        case .steps:
            return FaceValue(title: "PASOS", text: d.steps.map { thousands($0) } ?? missing,
                             fraction: d.steps.map { min(1, Double($0) / 10_000) }, tint: .exercise, symbol: "figure.walk")
        case .activity:
            let r = d.rings
            let text = r.map { "\(Int(($0.move * 100).rounded())) %" } ?? missing
            return FaceValue(title: "ACTIVIDAD", text: text,
                             detail: r.map { "Ejercicio \(Int(($0.exercise * 100).rounded())) % · De pie \(Int(($0.stand * 100).rounded())) %" },
                             fraction: r.map { min(1, $0.move) }, tint: .move, symbol: "figure.run")
        case .battery:
            return FaceValue(title: "BATERÍA", text: d.battery.map { "\(Int(($0 * 100).rounded()))" } ?? missing,
                             unit: d.battery == nil ? nil : "%", fraction: d.battery, tint: (d.battery ?? 1) < 0.2 ? .recoveryLow : .primary,
                             symbol: batterySymbol(d.battery))
        case .compass:
            return FaceValue(title: d.heading.map { cardinal($0) } ?? "N", text: d.heading.map { "\(Int($0.rounded()) % 360)°" } ?? missing,
                             fraction: d.heading.map { $0.truncatingRemainder(dividingBy: 360) / 360 }, tint: .accent, symbol: "location.north.fill")
        case .workout:
            guard let w = d.workout else {
                return FaceValue(title: "HOY", text: "Descanso", detail: "Nada en el plan", tint: .primary, symbol: "leaf.fill")
            }
            return FaceValue(title: w.done ? "HECHO" : "HOY", text: w.title, detail: w.detail, tint: w.done ? .recoveryHigh : .accent,
                             symbol: w.done ? "checkmark.circle.fill" : (w.symbol ?? "figure.run"))
        case .race:
            guard let race = d.race else { return FaceValue(title: "CARRERA", text: missing, tint: .accent, symbol: "flag.checkered") }
            let days = daysUntil(race.date, from: now, calendar: calendar)
            let text = days > 0 ? "\(days)" : (days == 0 ? "Hoy" : "Hecha")
            return FaceValue(title: race.name.uppercased(), text: text, unit: days > 0 ? (days == 1 ? "día" : "días") : nil,
                             detail: race.distanceText, fraction: days > 0 ? max(0, 1 - Double(days) / 112) : 1, tint: .accent,
                             symbol: "flag.checkered")
        case .weather:
            guard let w = d.weather else { return FaceValue(title: "TIEMPO", text: missing, tint: .weather, symbol: "cloud.sun.fill") }
            return FaceValue(title: "TIEMPO", text: "\(Int(w.temperatureC.rounded()))°", detail: w.text, tint: .weather, symbol: w.symbol)
        case .date:
            let parts = dateParts(now, calendar: calendar)
            return FaceValue(title: parts.weekday, text: parts.day, detail: parts.month, tint: .accent, symbol: "calendar")
        }
    }

    // MARK: Hora y fecha

    /// Horas y minutos en texto («09» o «9» con 12 h, como en las esferas de Apple) y los números para las agujas.
    public static func clock(_ date: Date, use24h: Bool, calendar: Calendar = .current)
        -> (hours: String, minutes: String, hour: Int, minute: Int, second: Double) {
        let c = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let hour = c.hour ?? 0, minute = c.minute ?? 0
        let second = Double(c.second ?? 0) + Double(c.nanosecond ?? 0) / 1e9
        let shown = use24h ? hour : (hour % 12 == 0 ? 12 : hour % 12)
        return (use24h ? String(format: "%02d", shown) : "\(shown)", String(format: "%02d", minute), hour, minute, second)
    }

    /// «MIÉ», «30», «SEPT».
    public static func dateParts(_ date: Date, calendar: Calendar = .current) -> (weekday: String, day: String, month: String) {
        let c = calendar.dateComponents([.weekday, .day, .month], from: date)
        return (weekdays[((c.weekday ?? 1) - 1 + 7) % 7], "\(c.day ?? 1)", months[((c.month ?? 1) - 1 + 12) % 12])
    }

    /// Días de calendario que faltan (0 = hoy, negativo si ya pasó).
    public static func daysUntil(_ date: Date, from now: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    }

    // MARK: Números en español

    /// «11,4».
    public static func decimal(_ x: Double, digits: Int) -> String {
        String(format: "%.\(max(0, digits))f", x).replacingOccurrences(of: ".", with: ",")
    }

    /// «8.412».
    public static func thousands(_ n: Int) -> String {
        let digits = String(abs(n))
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out += "." }
            out.append(ch)
        }
        return n < 0 ? "-" + out : out
    }

    /// «7:22».
    public static func clockDuration(minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    /// Rumbo en 8 puntos: «N», «NE», «E»…
    public static func cardinal(_ heading: Double) -> String {
        let names = ["N", "NE", "E", "SE", "S", "SO", "O", "NO"]
        let h = (heading.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return names[Int((h / 45).rounded()) % 8]
    }

    static func zoneText(_ zone: String?) -> String? {
        switch zone {
        case "high": return "Buena"
        case "medium": return "Normal"
        case "low": return "Baja"
        default: return nil
        }
    }

    public static func recoveryTint(_ zone: String?) -> FaceTint {
        switch zone {
        case "high": return .recoveryHigh
        case "medium": return .recoveryMedium
        case "low": return .recoveryLow
        default: return .primary
        }
    }

    static func batterySymbol(_ level: Double?) -> String {
        guard let level else { return "battery.100" }
        switch level {
        case ..<0.13: return "battery.0"
        case ..<0.38: return "battery.25"
        case ..<0.63: return "battery.50"
        case ..<0.88: return "battery.75"
        default: return "battery.100"
        }
    }
}
