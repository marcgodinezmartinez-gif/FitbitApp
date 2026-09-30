import Foundation
import MetricsKit

public enum PlanPhase: String, Codable, Sendable {
    case base, build, peak, taper, race

    public var label: String {
        switch self {
        case .base: return "Base"
        case .build: return "Desarrollo"
        case .peak: return "Específica"
        case .taper: return "Afinamiento"
        case .race: return "Semana de la carrera"
        }
    }

    public var purpose: String {
        switch self {
        case .base: return "Volumen suave, cuestas y progresiones: construir el motor."
        case .build: return "Umbral y series: subir el nivel."
        case .peak: return "Lo más específico para tu carrera."
        case .taper: return "Menos volumen, algo de ritmo: llegar fresco."
        case .race: return "Poco y suave; el domingo, a disfrutar."
        }
    }
}

public struct PlannedSession: Codable, Sendable, Hashable, Identifiable {
    public var date: LocalDate
    public var workout: StructuredWorkout
    public var id: String { "\(date.isoString)-\(workout.id)" }
}

public struct PlanWeek: Codable, Sendable, Hashable, Identifiable {
    public var index: Int
    public var start: LocalDate
    public var phase: PlanPhase
    public var targetKm: Double
    public var isCutback: Bool
    public var sessions: [PlannedSession]
    public var id: Int { index }
}

/// Plan de entrenamiento hacia la carrera objetivo (doc. 18 §7), con entrenos estructurados y tus ritmos del VDOT.
public struct TrainingPlan: Codable, Sendable, Hashable {
    public var goal: GoalRace
    public var createdAt: Date
    public var daysPerWeek: Int
    /// 1 = lunes … 7 = domingo.
    public var longRunWeekday: Int
    public var vdot: Double
    public var weeks: [PlanWeek]

    public var sessions: [PlannedSession] { weeks.flatMap(\.sessions) }

    public func week(containing date: LocalDate) -> PlanWeek? {
        weeks.first { date >= $0.start && date < $0.start.adding(days: 7) }
    }

    public func sessions(on date: LocalDate) -> [PlannedSession] { sessions.filter { $0.date == date } }

    /// Próxima sesión desde hoy (incluida).
    public func next(from today: LocalDate) -> PlannedSession? { sessions.filter { $0.date >= today }.min { $0.date < $1.date } }
}

public enum SessionStatus: Hashable, Sendable {
    case done(runID: String)
    case partial(runID: String)
    case missed
    case today
    case upcoming
}

public enum PlanBuilder {
    /// Volumen de la semana punta según la distancia (km) y la tirada más larga del plan.
    static func minPeak(_ d: RaceDistance) -> Double {
        switch d {
        case .k5: return 25
        case .k10: return 32
        case .half: return 40
        default: return 55
        }
    }

    static func maxLong(_ d: RaceDistance) -> Double {
        switch d {
        case .k5: return 14
        case .k10: return 18
        case .half: return 21
        default: return 32
        }
    }

    static func growth(_ d: RaceDistance) -> Double {
        switch d {
        case .k5: return 1.2
        case .k10: return 1.25
        case .half: return 1.3
        default: return 1.35
        }
    }

    /// Días de la semana (desplazamientos respecto a la tirada larga) de las sesiones, de la primera a la tirada.
    static func offsets(days: Int) -> [(kind: String, offset: Int)] {
        switch days {
        case ...3: return [("q1", -5), ("easy", -3), ("long", 0)]
        case 4: return [("q1", -5), ("q2", -3), ("easy", -1), ("long", 0)]
        case 5: return [("q1", -5), ("easy", -4), ("q2", -3), ("easy", -1), ("long", 0)]
        default: return [("easy", -6), ("q1", -5), ("easy", -4), ("q2", -3), ("easy", -1), ("long", 0)]
        }
    }

    public static func build(goal: GoalRace, vdot: Double, history: RunHistory, today: LocalDate, utcOffsetSeconds: Int,
                             daysPerWeek: Int, longRunWeekday: Int, createdAt: Date = Date()) -> TrainingPlan {
        let days = min(6, max(3, daysPerWeek))
        let d = goal.standardDistance
        let raceDay = LocalDate(goal.date, utcOffsetSeconds: utcOffsetSeconds)
        let racePace = goal.targetSeconds.map { $0 / goal.distanceM * 1000 }
            ?? RacePredictor.predict(race: goal, vdot: vdot).map { $0.totalSeconds / goal.distanceM * 1000 }
        let p = PaceSet(vdot: vdot, racePace: racePace)

        // Semanas (lunes a domingo) desde esta hasta la de la carrera, como mucho 24.
        let raceMonday = RunHistory.weekStart(raceDay)
        var firstMonday = RunHistory.weekStart(today)
        var count = max(1, raceMonday.days(since: firstMonday) / 7 + 1)
        if count > 24 {
            firstMonday = raceMonday.adding(days: -7 * 23)
            count = 24
        }
        // Afinamiento antes de la semana de la carrera: dos semanas para el maratón, una para lo demás.
        let taper = min(max(0, count - 1), d == .marathon ? 2 : 1)
        let buildWeeks = max(0, count - 1 - taper)

        // Punto de partida: tu volumen de las 4 últimas semanas completas (la de hoy va a medias) y tu tirada más larga del mes.
        let recent = history.weeks(count: 5, today: today).dropLast().map { $0.distanceM / 1000 }
        let current = max(10, recent.reduce(0, +) / Double(max(1, recent.count)))
        let longest30 = max(5, (history.summaries.filter { today.days(since: $0.date) <= 30 }.map(\.distanceM).max() ?? 5000) / 1000)
        let peak = min(max(current * growth(d), minPeak(d)), current * 1.8, Double(days) * 14)

        var volumes: [Double] = []
        var cutbacks: [Bool] = []
        var lastFull = current
        for w in 0..<buildWeeks {
            let cut = w > 0 && (w + 1) % 4 == 0 && w < buildWeeks - 1
            if cut {
                volumes.append(lastFull * 0.8)
            } else {
                lastFull = min(peak, w == 0 ? current * 1.05 : lastFull * 1.08)
                volumes.append(lastFull)
            }
            cutbacks.append(cut)
        }
        let top = volumes.max() ?? current
        let taperShares: [Double] = d == .marathon ? [0.75, 0.6] : [0.7]
        for k in 0..<taper {
            volumes.append(top * taperShares[min(k, taperShares.count - 1)])
            cutbacks.append(false)
        }
        if count > buildWeeks + taper {
            volumes.append(top * (d == .marathon ? 0.45 : 0.5))
            cutbacks.append(false)
        }

        var weeks: [PlanWeek] = []
        var longSoFar = longest30
        for w in 0..<count {
            let start = firstMonday.adding(days: 7 * w)
            let isRaceWeek = w == count - 1
            let phase: PlanPhase
            if isRaceWeek { phase = .race } else if w >= buildWeeks { phase = .taper } else {
                let f = Double(w) / Double(max(1, buildWeeks))
                phase = f < 0.4 ? .base : (f < 0.8 ? .build : .peak)
            }
            let target = volumes[w]
            // Tirada larga: una parte del volumen, con techo por distancia y sin subir más de un 10 % sobre la más larga reciente.
            let share = days == 3 ? 0.35 : (days == 4 ? 0.3 : 0.28)
            var longKm = min(maxLong(d), max(6, target * share), longSoFar * 1.1)
            if cutbacks[w] || phase == .taper { longKm = min(longKm, longSoFar * 0.8) }
            longKm = (longKm * 2).rounded() / 2
            if !cutbacks[w] && phase != .taper && !isRaceWeek { longSoFar = max(longSoFar, longKm) }

            let k = weeks.filter { $0.phase == phase }.count   // semana dentro de la fase
            let (q1, q2) = quality(d, phase: phase, k: k, p: p, goal: goal)
            var sessions: [PlannedSession] = []
            let slots = offsets(days: days)
            let qualityKm = [q1, days >= 4 ? q2 : nil].compactMap { $0?.estimatedMeters }.reduce(0, +) / 1000
            let easyCount = slots.filter { $0.kind == "easy" }.count
            let easyKm = max(4, ((target - longKm - qualityKm) / Double(max(1, easyCount)) * 2).rounded() / 2)
            for slot in slots {
                let weekday = ((longRunWeekday - 1 + slot.offset) % 7 + 7) % 7
                let date = start.adding(days: weekday)
                if date < today { continue }
                if isRaceWeek && date > raceDay { continue }
                var workout: StructuredWorkout?
                switch slot.kind {
                case "long":
                    workout = isRaceWeek ? nil : (phase == .peak && d == .marathon && k >= 1
                        ? WorkoutLibrary.long(meters: longKm * 1000, finishAtMarathonPace: min(10, 4 + 2 * Double(k)) * 1000, p)
                        : WorkoutLibrary.long(meters: longKm * 1000, p))
                case "q1": workout = q1
                case "q2": workout = days >= 4 ? q2 : nil
                default:
                    workout = phase == .base && slot.offset == -1 && days >= 5
                        ? WorkoutLibrary.strides(meters: easyKm * 1000, reps: 6, p)
                        : WorkoutLibrary.easy(meters: (isRaceWeek ? min(easyKm, 6) : easyKm) * 1000, p)
                }
                if isRaceWeek {
                    // Semana de la carrera: nada en los dos días anteriores salvo un trote corto la víspera.
                    let before = raceDay.days(since: date)
                    if before == 1 { workout = WorkoutLibrary.recovery(minutes: 20, p) } else if before == 2 { workout = nil }
                }
                if let workout { sessions.append(PlannedSession(date: date, workout: workout)) }
            }
            if isRaceWeek && raceDay >= today {
                sessions.append(PlannedSession(date: raceDay, workout: WorkoutLibrary.race(goal, p)))
            }
            sessions.sort { $0.date < $1.date }
            weeks.append(PlanWeek(index: w + 1, start: start, phase: phase, targetKm: (target * 10).rounded() / 10,
                                  isCutback: cutbacks[w], sessions: sessions))
        }
        return TrainingPlan(goal: goal, createdAt: createdAt, daysPerWeek: days, longRunWeekday: longRunWeekday, vdot: vdot, weeks: weeks)
    }

    /// Las dos sesiones de calidad de la semana según la distancia, la fase y la semana dentro de ella (se van alargando).
    static func quality(_ d: RaceDistance, phase: PlanPhase, k: Int, p: PaceSet, goal: GoalRace) -> (StructuredWorkout?, StructuredWorkout?) {
        let step = min(k, 3)
        switch phase {
        case .base:
            let hills = WorkoutLibrary.hills(reps: 6 + step, seconds: 60, p)
            let second = d == .half || d == .marathon ? WorkoutLibrary.tempo(minutes: Double(15 + 3 * step), p)
                : WorkoutLibrary.fartlek(reps: 6 + step, on: 60, off: 60, p)
            return (hills, second)
        case .build:
            switch d {
            case .k5: return (WorkoutLibrary.intervals(reps: 5 + min(step, 1), meters: 1000, p),
                              WorkoutLibrary.threshold(reps: 3 + min(step, 1), meters: 1600, p))
            case .k10: return (WorkoutLibrary.intervals(reps: 5 + min(step, 1), meters: 1000, p),
                               WorkoutLibrary.threshold(reps: 3 + min(step, 2), meters: 1600, p))
            case .half: return (WorkoutLibrary.threshold(reps: 4 + min(step, 1), meters: 1600, p),
                                WorkoutLibrary.intervals(reps: 5, meters: 1000, p))
            default: return (WorkoutLibrary.threshold(reps: 3 + min(step, 1), meters: 2000, p),
                             WorkoutLibrary.marathonPace(meters: Double(8 + 2 * step) * 1000, p))
            }
        case .peak:
            switch d {
            case .k5: return (WorkoutLibrary.repetitions(reps: 10, meters: 400, p), WorkoutLibrary.racePace(reps: 4 + min(step, 1), meters: 1000, p))
            case .k10: return (WorkoutLibrary.intervals(reps: 6, meters: 1000, p), WorkoutLibrary.racePace(reps: 3, meters: 2000, p))
            case .half: return (WorkoutLibrary.threshold(reps: 3, meters: 3000, p), WorkoutLibrary.racePace(reps: 3, meters: 4000, p))
            default: return (WorkoutLibrary.threshold(reps: 4, meters: 2000, p), WorkoutLibrary.marathonPace(meters: Double(14 + 2 * step) * 1000, p))
            }
        case .taper:
            return (WorkoutLibrary.threshold(reps: 3, meters: 1000, p), WorkoutLibrary.racePace(reps: 3, meters: d == .marathon || d == .half ? 2000 : 1000, p))
        case .race:
            return (WorkoutLibrary.racePace(reps: 3, meters: d == .k5 ? 400 : 1000, p), nil)
        }
    }

    /// Cómo va una sesión: hecha (≥ 70 % de la distancia prevista), a medias, saltada, hoy o por hacer.
    public static func status(of session: PlannedSession, runs: [RunSummary], today: LocalDate) -> SessionStatus {
        let sameDay = runs.filter { $0.date == session.date }
        if let best = sameDay.max(by: { $0.distanceM < $1.distanceM }) {
            let planned = session.workout.estimatedMeters
            return planned <= 0 || best.distanceM >= 0.7 * planned ? .done(runID: best.id) : .partial(runID: best.id)
        }
        if session.date < today { return .missed }
        return session.date == today ? .today : .upcoming
    }

    /// Sesiones hechas de las que ya han pasado (0–1).
    public static func adherence(_ plan: TrainingPlan, runs: [RunSummary], today: LocalDate) -> Double? {
        let past = plan.sessions.filter { $0.date < today }
        guard !past.isEmpty else { return nil }
        let done = past.filter { if case .done = status(of: $0, runs: runs, today: today) { return true } else { return false } }
        return Double(done.count) / Double(past.count)
    }
}
