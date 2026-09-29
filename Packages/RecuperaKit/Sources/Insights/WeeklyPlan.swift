import Foundation
import MetricsKit

// MARK: - Plan semanal (RF-PLA-01 … 03)

/// Plan de lunes a domingo. Se guarda en `app_state` con la clave `weekly_plan`; sin objetivos = sin plan.
public struct WeeklyPlan: Codable, Sendable, Hashable {
    public enum Template: String, Codable, Sendable, CaseIterable, Identifiable {
        case fitness, feelBetter, deeperSleep, custom

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .fitness: return "Mejorar forma"
            case .feelBetter: return "Sentirme mejor"
            case .deeperSleep: return "Dormir más profundo"
            case .custom: return "A mi manera"
            }
        }

        public var summary: String {
            switch self {
            case .fitness: return "Minutos en zonas, días de entreno, fuerza y tu carga objetivo."
            case .feelBetter: return "Dormir lo suficiente, moverte a diario y menos alcohol."
            case .deeperSleep: return "Más horas de sueño y hábitos que lo protegen."
            case .custom: return "Elige tú los objetivos."
            }
        }
    }

    public struct Goal: Codable, Sendable, Hashable, Identifiable {
        public enum Kind: String, Codable, Sendable, CaseIterable, Identifiable {
            case sleepNights, strainTargetDays, moderateZoneMinutes, vigorousZoneMinutes, activeDays, habitDays, stepDays, strengthMinutes

            public var id: String { rawValue }

            public var label: String {
                switch self {
                case .sleepNights: return "Horas de sueño"
                case .strainTargetDays: return "Carga objetivo"
                case .moderateZoneMinutes: return "Minutos en zonas 1–3"
                case .vigorousZoneMinutes: return "Minutos en zonas 4–5"
                case .activeDays: return "Días de actividad"
                case .habitDays: return "Hábito del diario"
                case .stepDays: return "Pasos"
                case .strengthMinutes: return "Tiempo de fuerza"
                }
            }

            public var symbolName: String {
                switch self {
                case .sleepNights: return "bed.double.fill"
                case .strainTargetDays: return "flame.fill"
                case .moderateZoneMinutes, .vigorousZoneMinutes: return "heart.circle.fill"
                case .activeDays: return "figure.run"
                case .habitDays: return "book.closed.fill"
                case .stepDays: return "figure.walk"
                case .strengthMinutes: return "dumbbell.fill"
                }
            }

            /// El objetivo se cuenta en días (o noches) y no en minutos.
            public var countsDays: Bool { self != .moderateZoneMinutes && self != .vigorousZoneMinutes && self != .strengthMinutes }

            /// Valores por defecto al añadirlo: objetivo semanal y umbral diario.
            public var defaults: (target: Double, threshold: Double?) {
                switch self {
                case .sleepNights: return (5, 7)
                case .strainTargetDays: return (4, nil)
                case .moderateZoneMinutes: return (150, nil)
                case .vigorousZoneMinutes: return (30, nil)
                case .activeDays: return (4, nil)
                case .habitDays: return (5, nil)
                case .stepDays: return (5, 8000)
                case .strengthMinutes: return (60, nil)
                }
            }
        }

        public var id: String
        public var kind: Kind
        /// Días (o noches) por semana, o minutos por semana.
        public var target: Double
        /// Horas de sueño por noche o pasos por día.
        public var threshold: Double?
        public var habitKey: String?
        /// `true` = hacerlo (p. ej. estirar); `false` = evitarlo (p. ej. alcohol).
        public var habitDesired: Bool?

        public init(id: String = UUID().uuidString, kind: Kind, target: Double? = nil, threshold: Double? = nil, habitKey: String? = nil,
                    habitDesired: Bool? = nil) {
            self.id = id
            self.kind = kind
            self.target = target ?? kind.defaults.target
            self.threshold = threshold ?? kind.defaults.threshold
            self.habitKey = habitKey
            self.habitDesired = habitDesired
        }

        /// Título legible, p. ej. «Dormir 7 h o más · 5 noches».
        public func title(habitLabels: [String: String] = JournalCatalog.labels) -> String {
            let n = Int(target.rounded())
            switch kind {
            case .sleepNights:
                return "Dormir \(Format.decimal(threshold ?? 7, digits: (threshold ?? 7).truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)) h o más · \(n) noches"
            case .strainTargetDays: return "Llegar a tu carga objetivo · \(n) días"
            case .moderateZoneMinutes: return "\(n) min en zonas 1–3"
            case .vigorousZoneMinutes: return "\(n) min en zonas 4–5"
            case .activeDays: return "Entrenar \(n) días"
            case .habitDays:
                let label = habitKey.flatMap { habitLabels[$0] } ?? "hábito"
                return (habitDesired ?? true ? "Hacer: \(label)" : "Sin \(label)") + " · \(n) días"
            case .stepDays: return "\(Format.decimal(threshold ?? 8000, digits: 0)) pasos · \(n) días"
            case .strengthMinutes: return "\(n) min de fuerza"
            }
        }
    }

    public var goals: [Goal]
    public var template: Template
    public var createdAt: Date

    public init(goals: [Goal] = [], template: Template = .custom, createdAt: Date = Date(timeIntervalSince1970: 0)) {
        self.goals = goals
        self.template = template
        self.createdAt = createdAt
    }

    public var isActive: Bool { !goals.isEmpty }

    /// Objetivos de cada plantilla (se pueden editar después).
    public static func goals(for template: Template) -> [Goal] {
        switch template {
        case .fitness:
            return [Goal(kind: .moderateZoneMinutes, target: 150), Goal(kind: .vigorousZoneMinutes, target: 30),
                    Goal(kind: .activeDays, target: 4), Goal(kind: .strengthMinutes, target: 60)]
        case .feelBetter:
            return [Goal(kind: .sleepNights, target: 5, threshold: 7), Goal(kind: .stepDays, target: 5, threshold: 8000),
                    Goal(kind: .activeDays, target: 3), Goal(kind: .habitDays, target: 5, habitKey: "alcohol", habitDesired: false)]
        case .deeperSleep:
            return [Goal(kind: .sleepNights, target: 5, threshold: 7.5),
                    Goal(kind: .habitDays, target: 5, habitKey: "late_caffeine", habitDesired: false),
                    Goal(kind: .habitDays, target: 5, habitKey: "screens_in_bed", habitDesired: false),
                    Goal(kind: .habitDays, target: 5, habitKey: "alcohol", habitDesired: false)]
        case .custom:
            return []
        }
    }
}

/// Progreso de una semana.
public struct WeeklyPlanProgress: Sendable, Hashable {
    public struct Item: Sendable, Hashable, Identifiable {
        public var goal: WeeklyPlan.Goal
        public var title: String
        public var current: Double
        /// 0–1 (se limita a 1 al cumplirse).
        public var fraction: Double
        public var id: String { goal.id }

        public var isDone: Bool { fraction >= 1 }

        /// «3 de 5 noches», «95 de 150 min»…
        public var detail: String {
            let unit: String
            switch goal.kind {
            case .sleepNights: unit = "noches"
            case .moderateZoneMinutes, .vigorousZoneMinutes, .strengthMinutes: unit = "min"
            default: unit = "días"
            }
            return "\(Int(current.rounded())) de \(Int(goal.target.rounded())) \(unit)"
        }
    }

    public var weekStart: LocalDate
    public var items: [Item]
    /// Media de las fracciones: todos los objetivos pesan igual (RF-PLA-02).
    public var overall: Double
    /// Días de la semana ya transcurridos (1 = lunes … 7 = domingo).
    public var daysElapsed: Int

    /// Fracción esperada a estas alturas si se reparte por igual.
    public var expected: Double { Double(daysElapsed) / 7 }

    public var percent: Int { Int((overall * 100).rounded()) }

    /// El objetivo que más se ha quedado atrás respecto a lo esperado.
    public var mostBehind: Item? {
        items.filter { !$0.isDone }.min { ($0.fraction - expected) < ($1.fraction - expected) }
    }
}

public enum WeeklyPlanner {
    /// Noches con datos necesarias para ofrecer el plan (RF-PLA-01).
    public static let requiredNights = 7

    /// Lunes de la semana de una fecha.
    public static func weekStart(of date: LocalDate) -> LocalDate { date.adding(days: -(date.isoWeekday - 1)) }

    public static func isAvailable(cycles: [CycleMetrics]) -> Bool {
        cycles.filter { $0.sleep != nil }.count >= requiredNights
    }

    public static func progress(plan: WeeklyPlan, cycles: [CycleMetrics], journal: [JournalAnswer], weekStart: LocalDate,
                                today: LocalDate) -> WeeklyPlanProgress {
        let weekEnd = weekStart.adding(days: 6)
        let last = min(today, weekEnd)
        let week = cycles.filter { $0.date >= weekStart && $0.date <= last }
        let answers = journal.filter { $0.date >= weekStart && $0.date <= last }
        let items = plan.goals.map { goal -> WeeklyPlanProgress.Item in
            let current = value(goal, week: week, journal: answers)
            let fraction = goal.target > 0 ? min(1, current / goal.target) : 0
            return WeeklyPlanProgress.Item(goal: goal, title: goal.title(), current: current, fraction: fraction)
        }
        let overall = items.isEmpty ? 0 : items.reduce(0) { $0 + $1.fraction } / Double(items.count)
        let elapsed = max(1, min(7, last.days(since: weekStart) + 1))
        return WeeklyPlanProgress(weekStart: weekStart, items: items, overall: overall, daysElapsed: elapsed)
    }

    static func value(_ goal: WeeklyPlan.Goal, week: [CycleMetrics], journal: [JournalAnswer]) -> Double {
        switch goal.kind {
        case .sleepNights:
            let hours = goal.threshold ?? 7
            return Double(week.filter { ($0.sleep?.asleepMin ?? 0) >= hours * 60 - 0.5 }.count)
        case .strainTargetDays:
            return Double(week.filter { c in c.target.map { c.strain.strain >= $0.low } ?? false }.count)
        case .moderateZoneMinutes:
            return Double(week.reduce(0) { $0 + $1.strain.zoneMinutes[1] + $1.strain.zoneMinutes[2] + $1.strain.zoneMinutes[3] })
        case .vigorousZoneMinutes:
            return Double(week.reduce(0) { $0 + $1.strain.zoneMinutes[4] + $1.strain.zoneMinutes[5] })
        case .activeDays:
            return Double(week.filter { c in c.activities.contains { $0.activity.durationMinutes >= 15 && $0.activity.kind != .walking } }.count)
        case .habitDays:
            guard let key = goal.habitKey else { return 0 }
            let desired = goal.habitDesired ?? true
            let days = Set(journal.filter { $0.questionKey == key && $0.yes == desired }.map(\.date))
            return Double(days.count)
        case .stepDays:
            let steps = goal.threshold ?? 8000
            return Double(week.filter { Double($0.totals?.steps ?? 0) >= steps }.count)
        case .strengthMinutes:
            return week.flatMap(\.activities).filter { $0.activity.kind.isStrength }.reduce(0) { $0 + $1.activity.durationMinutes }
        }
    }

    /// Texto de la revisión del viernes (NOT-11, RF-PLA-03).
    public static func fridayReview(_ p: WeeklyPlanProgress) -> String {
        var text = "Vas al \(p.percent) % de tu plan semanal."
        if let behind = p.mostBehind, behind.fraction < p.expected {
            text += " Lo que más falta: \(behind.title) (\(behind.detail))."
        } else if p.overall >= 1 {
            text = "¡Plan semanal cumplido! Vas al 100 %."
        }
        return text
    }
}
