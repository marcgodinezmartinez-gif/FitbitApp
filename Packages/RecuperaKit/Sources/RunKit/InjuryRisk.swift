import Foundation
import MetricsKit

/// Carga aguda y crónica de un día y su cociente (ACWR).
public struct LoadRatioPoint: Sendable, Hashable, Identifiable {
    public var date: LocalDate
    /// Carga del día entero (TRIMP de todo el día, no solo de las carreras).
    public var load: Double
    public var acute: Double
    public var chronic: Double
    public var ratio: Double?
    public var id: String { date.isoString }
}

public enum LoadRiskLevel: String, Codable, Sendable, CaseIterable {
    case low, optimal, caution, high

    public init(ratio: Double) {
        switch ratio {
        case ..<0.8: self = .low
        case ..<1.3: self = .optimal
        case ..<1.5: self = .caution
        default: self = .high
        }
    }

    public var label: String {
        switch self {
        case .low: return "Carga baja"
        case .optimal: return "Zona óptima"
        case .caution: return "Precaución"
        case .high: return "Riesgo alto"
        }
    }
}

/// Una carrera más larga que la más larga de los 30 días anteriores (Frandsen et al., 2025).
public struct SessionSpike: Sendable, Hashable, Identifiable {
    public enum Level: String, Codable, Sendable {
        /// Sin carreras en los 30 días anteriores: vuelta tras un parón.
        case returning
        case moderate, high, veryHigh

        public var label: String {
            switch self {
            case .returning: return "Vuelta tras un parón"
            case .moderate: return "Pico moderado"
            case .high: return "Pico alto"
            case .veryHigh: return "Pico muy alto"
            }
        }
    }

    public var runID: String
    public var date: LocalDate
    public var distanceM: Double
    public var previousLongestM: Double?
    public var increasePct: Double?
    public var level: Level
    public var id: String { runID }
}

/// Riesgo de lesión (doc. 18 §6): cociente de carga aguda y crónica con la carga de todo el día (Gabbett, 2016; con medias
/// exponenciales, Williams et al., 2017) y picos de distancia en una sola carrera.
public struct InjuryRisk: Sendable {
    /// Últimas 8 semanas.
    public var points: [LoadRatioPoint]
    public var ratio: Double?
    public var level: LoadRiskLevel?
    /// Picos de las últimas 4 semanas, del más reciente al más antiguo.
    public var spikes: [SessionSpike]
    /// Km de los últimos 7 días frente a la media semanal de los 21 anteriores (%).
    public var weeklyChangePct: Double?
    public var longestLast30M: Double?
    /// Hasta dónde alargar la próxima carrera sin pasar de un 10 % sobre la más larga de 30 días.
    public var safeLongRunM: Double?
    public var advice: String

    static let acuteDays = 7.0, chronicDays = 28.0

    /// `dailyLoads`: carga de cada día (del motor: TRIMP de todo el día). `runs`: las carreras, para los picos.
    public static func assess(dailyLoads: [LocalDate: Double], runs: [RunSummary], today: LocalDate) -> InjuryRisk {
        // EWMA con λ = 2 / (N + 1), desde el primer día con carga; el cociente, con al menos 28 días de historia.
        let first = dailyLoads.keys.min() ?? today
        let la = 2 / (acuteDays + 1), lc = 2 / (chronicDays + 1)
        var acute = 0.0, chronic = 0.0
        var points: [LoadRatioPoint] = []
        var day = first, n = 0
        let meanLoad = dailyLoads.isEmpty ? 0 : dailyLoads.values.reduce(0, +) / Double(dailyLoads.count)
        while day <= today {
            let load = dailyLoads[day] ?? 0
            if n == 0 {
                acute = load
                chronic = load
            } else {
                acute = la * load + (1 - la) * acute
                chronic = lc * load + (1 - lc) * chronic
            }
            n += 1
            let ratio: Double? = n >= 28 && chronic > max(1, 0.1 * meanLoad) ? acute / chronic : nil
            if today.days(since: day) < 56 { points.append(LoadRatioPoint(date: day, load: load, acute: acute, chronic: chronic, ratio: ratio)) }
            day = day.adding(days: 1)
        }
        let ratio = points.last?.ratio
        let spikes = spikes(runs: runs, since: today.adding(days: -27)).reversed()
        let longest = runs.filter { $0.date > today.adding(days: -30) && $0.date <= today }.map(\.distanceM).max()

        // Volumen de carrera: últimos 7 días frente a la media de los 21 anteriores.
        func km(_ from: LocalDate, _ to: LocalDate) -> Double {
            runs.filter { $0.date >= from && $0.date <= to }.reduce(0) { $0 + $1.distanceM } / 1000
        }
        let last7 = km(today.adding(days: -6), today)
        let previous = km(today.adding(days: -27), today.adding(days: -7)) / 3
        let weekly: Double? = previous >= 5 ? (last7 - previous) / previous * 100 : nil

        var risk = InjuryRisk(points: points, ratio: ratio, level: ratio.map(LoadRiskLevel.init(ratio:)), spikes: Array(spikes),
                              weeklyChangePct: weekly, longestLast30M: longest, safeLongRunM: longest.map { $0 * 1.1 }, advice: "")
        risk.advice = advice(risk, today: today)
        return risk
    }

    /// Carreras desde `since` más largas que la más larga de sus 30 días anteriores.
    public static func spikes(runs: [RunSummary], since: LocalDate) -> [SessionSpike] {
        let sorted = runs.sorted { $0.start < $1.start }
        var out: [SessionSpike] = []
        for (k, run) in sorted.enumerated() where run.date >= since && run.distanceM >= 3000 {
            let window = sorted[..<k].filter { run.date.days(since: $0.date) <= 30 && $0.id != run.id }
            guard let previous = window.map(\.distanceM).max() else {
                out.append(SessionSpike(runID: run.id, date: run.date, distanceM: run.distanceM, previousLongestM: nil, increasePct: nil,
                                        level: .returning))
                continue
            }
            let pct = (run.distanceM - previous) / previous * 100
            guard pct > 10 else { continue }
            let level: SessionSpike.Level = pct > 100 ? .veryHigh : (pct > 30 ? .high : .moderate)
            out.append(SessionSpike(runID: run.id, date: run.date, distanceM: run.distanceM, previousLongestM: previous, increasePct: pct,
                                    level: level))
        }
        return out
    }

    static func advice(_ r: InjuryRisk, today: LocalDate) -> String {
        var parts: [String] = []
        switch r.level {
        case .high?: parts.append("Tu carga de esta semana está muy por encima de la que llevas acostumbrada: baja el volumen o la intensidad unos días.")
        case .caution?: parts.append("Estás subiendo la carga deprisa: mantén esta semana y no añadas más.")
        case .low?: parts.append("Llevas menos carga de la habitual: puedes ir subiendo poco a poco.")
        case .optimal?: parts.append("Carga en la zona óptima: subes sin pasarte.")
        case nil: parts.append("Hacen falta cuatro semanas de datos para calcular el cociente de carga.")
        }
        if let spike = r.spikes.first(where: { $0.level != .returning && today.days(since: $0.date) <= 7 }), let pct = spike.increasePct {
            parts.append("Tu carrera del \(spike.date.day)/\(spike.date.month) fue un \(Int(pct.rounded())) % más larga que la más larga de los 30 días anteriores: los picos de más del 10 % en una sola carrera se asocian a más lesiones.")
        }
        if let w = r.weeklyChangePct, w > 30 { parts.append("Has corrido un \(Int(w.rounded())) % más que tu media semanal reciente.") }
        return parts.joined(separator: " ")
    }
}
