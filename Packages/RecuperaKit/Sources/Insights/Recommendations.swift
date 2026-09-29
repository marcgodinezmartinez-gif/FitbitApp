import Foundation
import MetricsKit

/// Recomendación corta de la pantalla Hoy (plantillas deterministas, F1–F2).
public enum TodayRecommendation {
    /// `nowMinutes`: minuto del día local; si la hora de acostarse ya ha pasado, se dice que es hora de dormir.
    public static func text(for cycle: CycleMetrics, output: MetricsOutput, profile: UserProfile, nowMinutes: Int? = nil,
                            params: AlgorithmParams = .default) -> String {
        var parts: [String] = []
        switch cycle.recovery.zone {
        case .high?: parts.append("Buen día para apretar.")
        case .medium?: parts.append("Día para mantener.")
        case .low?: parts.append("Hoy toca recuperar.")
        case nil:
            if case .calibrating(let n, let needed) = cycle.recovery.status {
                parts.append("Estamos conociendo tu cuerpo: \(n) de \(needed) noches.")
            } else {
                parts.append("Aún no hay recuperación de hoy.")
            }
        }
        if let t = cycle.target {
            switch t.status(of: cycle.strain.strain) {
            case .below: parts.append("Objetivo de carga \(Format.decimal(t.low, digits: 0))–\(Format.decimal(t.high, digits: 0)).")
            case .within: parts.append("Ya estás en tu objetivo de carga.")
            case .above: parts.append("Has superado tu objetivo: prioriza descansar.")
            }
        }
        if let need = output.tonightNeed {
            let bed = SleepCalculator.bedtime(wakeMinutes: profile.usualWakeMinutes, needMin: need.totalMin, goal: .peak,
                                              usualEfficiency: output.usualEfficiency, usualLatency: output.usualLatency, params: params)
            if let nowMinutes, bedtimePassed(bed: bed, now: nowMinutes) {
                parts.append("Lo ideal era acostarte a las \(Format.clock(minutes: bed)): acuéstate en cuanto puedas.")
            } else {
                parts.append("Acuéstate a las \(Format.clock(minutes: bed)).")
            }
        }
        return parts.joined(separator: " ")
    }

    /// La hora de acostarse ya ha pasado si ahora cae en las 6 h siguientes (cruzando la medianoche: a las 23:48 la de las
    /// 22:35 ya pasó; la de las 00:30, todavía no).
    static func bedtimePassed(bed: Int, now: Int) -> Bool {
        let elapsed = ((now - bed) % 1440 + 1440) % 1440
        return elapsed < 6 * 60
    }

    /// Explicación en lenguaje natural de cada componente de la recuperación (RF-REC-04).
    public static func explain(_ c: RecoveryComponent) -> String {
        DayAnalyzer.componentSentence(c) ?? {
            switch c.kind {
            case .respiratoryRate: return "Tu frecuencia respiratoria está en tu rango habitual."
            case .skinTemp: return "Tu temperatura nocturna está en tu rango habitual."
            case .spo2: return "Tu SpO₂ está en tu rango habitual."
            default: return ""
            }
        }()
    }
}

/// Informe semanal (RF-INF-01), determinista.
public struct WeeklyReport: Codable, Sendable, Hashable {
    public var periodStart: String
    public var periodEnd: String
    public var avgRecovery: Double?
    public var avgStrain: Double?
    public var totalLoad: Double
    public var avgSleepMin: Double?
    public var avgNeedMin: Double?
    public var zoneDays: [String: Int]     // high/medium/low
    public var best: [String]
    public var recommendations: [String]
    public var previousAvgRecovery: Double?
    public var previousAvgStrain: Double?
    public var runs: Int
    public var runDistanceKm: Double
}

public enum WeeklyReportBuilder {
    public static func build(output: MetricsOutput, weekStart: LocalDate) -> WeeklyReport {
        let week = output.cycles.filter { $0.date >= weekStart && $0.date < weekStart.adding(days: 7) }
        let prev = output.cycles.filter { $0.date >= weekStart.adding(days: -7) && $0.date < weekStart }
        let recoveries = week.compactMap { $0.recovery.score.map(Double.init) }
        let strains = week.map(\.strain.strain)
        var zones: [String: Int] = ["high": 0, "medium": 0, "low": 0]
        for c in week { if let z = c.recovery.zone { zones[z.rawValue, default: 0] += 1 } }
        let sleeps = week.compactMap(\.sleep)
        var best: [String] = []
        if let top = week.max(by: { ($0.recovery.score ?? -1) < ($1.recovery.score ?? -1) }), let s = top.recovery.score {
            best.append("Mejor recuperación: \(s) % el \(Format.weekdayName(top.date)).")
        }
        if let longest = sleeps.max(by: { $0.asleepMin < $1.asleepMin }) {
            best.append("Noche más larga: \(Format.duration(minutes: longest.asleepMin)).")
        }
        let runs = week.flatMap(\.activities).filter { $0.activity.kind.isRun }
        let km = runs.compactMap(\.activity.distanceM).reduce(0, +) / 1000
        if !runs.isEmpty { best.append("\(runs.count) carreras, \(Format.decimal(km)) km en total.") }

        var recs: [String] = []
        let avgSleep = Stats.mean(sleeps.map(\.asleepMin))
        let avgNeed = Stats.mean(sleeps.map(\.need.totalMin))
        if let s = avgSleep, let n = avgNeed, s < n - 20 {
            recs.append("Duerme más: te faltaron de media \(Format.duration(minutes: n - s)) por noche.")
        }
        if let c = Stats.mean(sleeps.compactMap(\.consistency)), c < 70 {
            recs.append("Intenta acostarte y levantarte a horas más parecidas (constancia \(Int(c)) %).")
        }
        if (zones["low"] ?? 0) >= 3 { recs.append("Varios días en rojo: reserva un día de descanso completo.") }
        if (zones["high"] ?? 0) >= 4, let s = Stats.mean(strains), s < 10 { recs.append("Te has recuperado bien: hay margen para subir la carga.") }
        if recs.isEmpty { recs.append("Sigue así: tu semana ha sido equilibrada.") }
        return WeeklyReport(periodStart: weekStart.isoString, periodEnd: weekStart.adding(days: 6).isoString,
                            avgRecovery: Stats.mean(recoveries), avgStrain: Stats.mean(strains),
                            totalLoad: week.reduce(0) { $0 + $1.strain.loadRaw }, avgSleepMin: avgSleep, avgNeedMin: avgNeed,
                            zoneDays: zones, best: best, recommendations: Array(recs.prefix(3)),
                            previousAvgRecovery: Stats.mean(prev.compactMap { $0.recovery.score.map(Double.init) }),
                            previousAvgStrain: Stats.mean(prev.map(\.strain.strain)), runs: runs.count, runDistanceKm: km)
    }
}

/// Catálogo de preguntas del diario (RF-DIA-01).
public struct JournalQuestion: Codable, Sendable, Hashable, Identifiable {
    public enum AnswerType: String, Codable, Sendable { case yesNo = "bool", number, scale = "scale_1_5" }

    public var key: String
    public var text: String
    public var shortLabel: String
    public var category: String
    public var answerType: AnswerType
    public var enabledByDefault: Bool
    public var id: String { key }
}

public enum JournalCatalog {
    public static let questions: [JournalQuestion] = [
        q("alcohol", "¿Tomaste alcohol?", "alcohol", "Estilo de vida", true),
        q("late_caffeine", "¿Tomaste cafeína después de las 14:00?", "cafeína tarde", "Estilo de vida", true),
        q("late_meal", "¿Cenaste menos de 2 h antes de acostarte?", "cena tardía", "Nutrición", true),
        q("screens_in_bed", "¿Usaste pantallas en la cama?", "pantallas en la cama", "Sueño", true),
        q("work_stress", "¿Tuviste un día estresante en el trabajo?", "estrés laboral", "Salud mental", true),
        q("travel", "¿Viajaste?", "viaje", "Estilo de vida", false),
        q("sick", "¿Te sentías enfermo?", "enfermedad", "Salud", true),
        q("meditation", "¿Meditaste?", "meditación", "Recuperación", false),
        q("stretching", "¿Estiraste o hiciste movilidad?", "estiramientos", "Recuperación", false),
        q("sauna", "¿Fuiste a la sauna?", "sauna", "Recuperación", false),
        q("cold_exposure", "¿Te diste un baño o una ducha fría?", "frío", "Recuperación", false),
        q("supplements", "¿Tomaste suplementos?", "suplementos", "Nutrición", false),
        q("hydration", "¿Bebiste suficiente agua?", "hidratación", "Nutrición", false),
        q("sugar", "¿Tomaste mucho azúcar?", "azúcar", "Nutrición", false),
        q("reading_in_bed", "¿Leíste en papel antes de dormir?", "lectura", "Sueño", false),
        q("nap", "¿Echaste la siesta?", "siesta", "Sueño", false),
        q("shared_bed", "¿Dormiste acompañado?", "cama compartida", "Sueño", false),
        q("dark_room", "¿Dormiste a oscuras?", "habitación a oscuras", "Sueño", false),
        q("outdoor_light", "¿Tomaste luz natural por la mañana?", "luz natural", "Estilo de vida", false),
        q("social", "¿Tuviste un plan social?", "plan social", "Salud mental", false),
        q("sex", "¿Tuviste relaciones sexuales?", "relaciones", "Estilo de vida", false),
        q("injury", "¿Tienes alguna molestia o lesión?", "molestia", "Salud", false),
        q("medication", "¿Tomaste medicación?", "medicación", "Salud", false),
        q("late_workout", "¿Entrenaste menos de 2 h antes de acostarte?", "entreno tardío", "Entrenamiento", false),
        q("strength_training", "¿Hiciste fuerza?", "fuerza", "Entrenamiento", false),
        q("big_meal", "¿Comiste mucho?", "comida copiosa", "Nutrición", false),
        q("fasting", "¿Hiciste ayuno?", "ayuno", "Nutrición", false),
        q("nicotine", "¿Consumiste nicotina?", "nicotina", "Estilo de vida", false),
        q("cannabis", "¿Consumiste cannabis?", "cannabis", "Estilo de vida", false),
        JournalQuestion(key: "energy", text: "¿Cómo de recuperado te sientes? (1–5)", shortLabel: "autoevaluación",
                        category: "Autoevaluación", answerType: .scale, enabledByDefault: true),
    ]

    static func q(_ key: String, _ text: String, _ label: String, _ cat: String, _ on: Bool) -> JournalQuestion {
        JournalQuestion(key: key, text: text, shortLabel: label, category: cat, answerType: .yesNo, enabledByDefault: on)
    }

    public static var labels: [String: String] { Dictionary(questions.map { ($0.key, $0.shortLabel) }, uniquingKeysWith: { a, _ in a }) }
}
