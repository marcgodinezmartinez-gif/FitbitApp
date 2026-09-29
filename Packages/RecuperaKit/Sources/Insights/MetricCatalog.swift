import Foundation
import MetricsKit

/// Métricas diarias que se pueden ver en Tendencias y elegir para «Mi panel» (doc. 11 §4).
public enum DayMetric: String, CaseIterable, Codable, Sendable, Identifiable {
    case recovery, hrv, rhr, sleep, sleepPerformance, strain, zoneMinutes, steps, stress, respiratory, spo2, skinTemp

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .recovery: return "Recuperación"
        case .hrv: return "VFC"
        case .rhr: return "FC en reposo"
        case .sleep: return "Horas de sueño"
        case .sleepPerformance: return "Rendimiento del sueño"
        case .strain: return "Carga"
        case .zoneMinutes: return "Minutos en zonas"
        case .steps: return "Pasos"
        case .stress: return "Estrés"
        case .respiratory: return "Frec. respiratoria"
        case .spo2: return "SpO₂"
        case .skinTemp: return "Temperatura de la piel"
        }
    }

    public var unit: String {
        switch self {
        case .recovery, .sleepPerformance, .spo2: return "%"
        case .hrv: return "ms"
        case .rhr: return "lpm"
        case .sleep: return "h"
        case .strain, .stress: return ""
        case .zoneMinutes: return "min"
        case .steps: return "pasos"
        case .respiratory: return "rpm"
        case .skinTemp: return "°C"
        }
    }

    public var digits: Int {
        switch self {
        case .sleep, .strain, .stress, .respiratory, .spo2, .skinTemp: return 1
        default: return 0
        }
    }

    public var symbolName: String {
        switch self {
        case .recovery: return "bolt.heart.fill"
        case .hrv: return "waveform.path.ecg"
        case .rhr: return "heart.fill"
        case .sleep: return "bed.double.fill"
        case .sleepPerformance: return "moon.stars.fill"
        case .strain: return "flame.fill"
        case .zoneMinutes: return "chart.bar.fill"
        case .steps: return "figure.walk"
        case .stress: return "brain.head.profile"
        case .respiratory: return "lungs.fill"
        case .spo2: return "drop.fill"
        case .skinTemp: return "thermometer.medium"
        }
    }

    /// Escala fija del eje (las demás se ajustan a los datos).
    public var domain: ClosedRange<Double>? {
        switch self {
        case .recovery, .sleepPerformance: return 0...100
        case .strain: return 0...21
        case .stress: return 0...3
        default: return nil
        }
    }

    /// `true` si subir es bueno, `false` si bajar es bueno y `nil` si depende (se muestra sin color).
    public var higherIsBetter: Bool? {
        switch self {
        case .recovery, .hrv, .sleep, .sleepPerformance, .zoneMinutes, .steps: return true
        case .rhr, .stress: return false
        case .strain, .respiratory, .spo2, .skinTemp: return nil
        }
    }

    public func value(_ c: CycleMetrics) -> Double? {
        switch self {
        case .recovery: return c.recovery.score.map(Double.init)
        case .hrv: return c.vitals?.hrvRmssdAvg
        case .rhr: return c.vitals?.restingHR
        case .sleep: return c.sleep.map { $0.asleepMin / 60 }
        case .sleepPerformance: return c.sleep?.performance
        case .strain: return c.strain.strain
        case .zoneMinutes: return Double(c.strain.zoneMinutes.dropFirst().reduce(0, +))
        case .steps: return c.totals.map { Double($0.steps) }
        case .stress: return c.stress.average
        case .respiratory: return c.vitals?.respiratoryRate
        case .spo2: return c.vitals?.spo2Avg
        case .skinTemp: return c.vitals?.skinTempC
        }
    }

    public func formatted(_ v: Double) -> String {
        switch self {
        case .sleep: return Format.duration(minutes: v * 60)
        case .steps: return Format.decimal(v, digits: 0)
        default: return Format.decimal(v, digits: digits)
        }
    }

    /// Lista de «Mi panel» saneada: claves conocidas, sin repetir y en el orden elegido.
    public static func dashboard(_ keys: [String]) -> [DayMetric] {
        var seen = Set<DayMetric>()
        return keys.compactMap(DayMetric.init(rawValue:)).filter { seen.insert($0).inserted }
    }
}

/// Resumen de una métrica para su tarjeta de «Mi panel»: último valor, referencia y últimos 7 días.
public struct MetricSummary: Sendable, Hashable {
    public var metric: DayMetric
    public var latest: Double?
    public var latestDate: LocalDate?
    /// Mediana de los 30 días anteriores al último valor (con ≥ 5 datos).
    public var usual: Double?
    public var last7: [Double?]

    public var delta: Double? {
        guard let latest, let usual else { return nil }
        return latest - usual
    }

    /// Si la diferencia con lo habitual es buena (`true`), mala (`false`) o neutra (`nil`).
    public var isImprovement: Bool? {
        guard let d = delta, let better = metric.higherIsBetter, abs(d) > 0.0001 else { return nil }
        return better ? d > 0 : d < 0
    }

    public static func build(_ metric: DayMetric, cycles: [CycleMetrics], until date: LocalDate) -> MetricSummary {
        let upTo = cycles.filter { $0.date <= date }
        let latestCycle = upTo.last { metric.value($0) != nil }
        let latest = latestCycle.flatMap { metric.value($0) }
        var usual: Double?
        if let d = latestCycle?.date {
            let prior = upTo.filter { $0.date < d && d.days(since: $0.date) <= 30 }.compactMap { metric.value($0) }
            if prior.count >= 5 { usual = Stats.median(prior) }
        }
        let byDate = Dictionary(upTo.map { ($0.date, $0) }, uniquingKeysWith: { _, b in b })
        let last7 = (0..<7).reversed().map { i in byDate[date.adding(days: -i)].flatMap { metric.value($0) } }
        return MetricSummary(metric: metric, latest: latest, latestDate: latestCycle?.date, usual: usual, last7: last7)
    }
}
