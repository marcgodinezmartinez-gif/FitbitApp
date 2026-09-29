import Foundation
import MetricsKit

/// Formato de cifras en español (guía de redacción del doc. 11 §11).
public enum Format {
    public static func duration(minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let h = total / 60, m = total % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// Hora del día a partir de minutos desde medianoche (admite valores negativos o > 1440).
    public static func clock(minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    public static func clock(_ date: Date, utcOffsetSeconds: Int) -> String {
        let secs = Int(date.timeIntervalSince1970) + utcOffsetSeconds
        return clock(minutes: ((secs % 86_400) + 86_400) % 86_400 / 60)
    }

    /// Ritmo «5:12» a partir de segundos por km.
    public static func pace(secondsPerKm: Double) -> String {
        let s = Int(secondsPerKm.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    public static func decimal(_ v: Double, digits: Int = 1) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.\(digits)f", v)
    }

    public static func km(_ meters: Double) -> String { decimal(meters / 1000, digits: 1) + " km" }

    public static func percent(_ v: Double) -> String { "\(Int(v.rounded())) %" }

    public static func signed(_ v: Double, digits: Int = 0) -> String {
        let s = digits == 0 ? "\(Int(abs(v).rounded()))" : decimal(abs(v), digits: digits)
        return (v >= 0 ? "+" : "−") + s
    }

    public static func weekdayName(_ d: LocalDate) -> String {
        ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"][d.isoWeekday - 1]
    }

    public static func monthName(_ m: Int) -> String {
        ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"][max(0, min(11, m - 1))]
    }

    public static func longDate(_ d: LocalDate) -> String {
        "\(weekdayName(d).capitalized) \(d.day) de \(monthName(d.month))"
    }
}
