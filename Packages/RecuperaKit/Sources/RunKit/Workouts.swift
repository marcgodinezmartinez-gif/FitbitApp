import Foundation
import MetricsKit

/// Intensidad objetivo de un paso: un rango de ritmo (s/km), una zona de FC o ninguna.
public struct WorkoutTarget: Codable, Sendable, Hashable {
    public var paceFast: Double?
    public var paceSlow: Double?
    public var heartRateZone: Int?

    public init(paceFast: Double? = nil, paceSlow: Double? = nil, heartRateZone: Int? = nil) {
        self.paceFast = paceFast
        self.paceSlow = paceSlow
        self.heartRateZone = heartRateZone
    }

    public static let none = WorkoutTarget()
    /// Ritmo con ± `margin` segundos por km.
    public static func pace(_ center: Double, margin: Double = 5) -> WorkoutTarget {
        WorkoutTarget(paceFast: center - margin, paceSlow: center + margin)
    }
    public static func range(fast: Double, slow: Double) -> WorkoutTarget { WorkoutTarget(paceFast: fast, paceSlow: slow) }
    public static func zone(_ z: Int) -> WorkoutTarget { WorkoutTarget(heartRateZone: z) }

    /// Ritmo medio del rango (para estimar tiempos y distancias).
    public var paceMid: Double? {
        guard let f = paceFast, let s = paceSlow else { return paceFast ?? paceSlow }
        return (f + s) / 2
    }
}

public enum StepGoal: Codable, Sendable, Hashable {
    /// Metros.
    case distance(Double)
    /// Segundos.
    case time(Double)
    case open
}

public struct WorkoutStepPlan: Codable, Sendable, Hashable {
    public enum Purpose: String, Codable, Sendable { case warmup, work, recovery, cooldown, steady }

    public var purpose: Purpose
    public var goal: StepGoal
    public var target: WorkoutTarget
    public var label: String
    /// Ritmo con el que se estima el paso si no lleva objetivo de ritmo (trote, cuestas…).
    public var expectedPace: Double

    public init(_ purpose: Purpose, _ goal: StepGoal, _ target: WorkoutTarget = .none, label: String, expectedPace: Double) {
        self.purpose = purpose
        self.goal = goal
        self.target = target
        self.label = label
        self.expectedPace = expectedPace
    }

    var pace: Double { target.paceMid ?? expectedPace }

    public var seconds: Double {
        switch goal {
        case .distance(let m): return m / 1000 * pace
        case .time(let s): return s
        case .open: return 0
        }
    }

    public var meters: Double {
        switch goal {
        case .distance(let m): return m
        case .time(let s): return pace > 0 ? s / pace * 1000 : 0
        case .open: return 0
        }
    }
}

public struct WorkoutBlockPlan: Codable, Sendable, Hashable {
    public var steps: [WorkoutStepPlan]
    public var iterations: Int

    public init(steps: [WorkoutStepPlan], iterations: Int = 1) {
        self.steps = steps
        self.iterations = iterations
    }
}

public enum SessionKind: String, Codable, Sendable, CaseIterable {
    case easy, long, recovery, tempo, threshold, intervals, repetitions, hills, fartlek, progression, marathonPace, racePace, strides, race

    public var label: String {
        switch self {
        case .easy: return "Rodaje suave"
        case .long: return "Tirada larga"
        case .recovery: return "Recuperación"
        case .tempo: return "Tempo"
        case .threshold: return "Umbral"
        case .intervals: return "Series"
        case .repetitions: return "Repeticiones"
        case .hills: return "Cuestas"
        case .fartlek: return "Fartlek"
        case .progression: return "Progresivo"
        case .marathonPace: return "Ritmo maratón"
        case .racePace: return "Ritmo de carrera"
        case .strides: return "Rodaje con progresiones"
        case .race: return "Carrera"
        }
    }

    public var isQuality: Bool {
        switch self {
        case .easy, .long, .recovery, .strides: return false
        default: return true
        }
    }
}

/// Entreno estructurado (calentamiento, bloques que se repiten y vuelta a la calma), listo para el Apple Watch.
public struct StructuredWorkout: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: SessionKind
    public var title: String
    public var purpose: String
    public var warmup: WorkoutStepPlan?
    public var blocks: [WorkoutBlockPlan]
    public var cooldown: WorkoutStepPlan?

    public init(id: String, kind: SessionKind, title: String, purpose: String, warmup: WorkoutStepPlan? = nil,
                blocks: [WorkoutBlockPlan], cooldown: WorkoutStepPlan? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.purpose = purpose
        self.warmup = warmup
        self.blocks = blocks
        self.cooldown = cooldown
    }

    private var allSteps: [(WorkoutStepPlan, Int)] {
        [warmup.map { ($0, 1) }, cooldown.map { ($0, 1) }].compactMap { $0 } + blocks.flatMap { b in b.steps.map { ($0, b.iterations) } }
    }

    public var estimatedSeconds: Double { allSteps.reduce(0) { $0 + $1.0.seconds * Double($1.1) } }
    public var estimatedMeters: Double { allSteps.reduce(0) { $0 + $1.0.meters * Double($1.1) } }
}

/// Ritmos de entrenamiento (s/km) de un VDOT, más el de la carrera objetivo.
public struct PaceSet: Sendable, Hashable {
    public var easyFast: Double
    public var easySlow: Double
    public var marathon: Double
    public var threshold: Double
    public var interval: Double
    public var repetition: Double
    public var race: Double

    public init(vdot: Double, racePace: Double? = nil) {
        func pace(_ speed: Double) -> Double { speed > 0 ? 1000 / speed : 0 }
        let paces = RunPhysiology.trainingPaces(vdot: vdot)
        func zone(_ z: TrainingPace.Zone) -> TrainingPace? { paces.first { $0.zone == z } }
        easyFast = pace(zone(.easy)?.fastSpeed ?? 3)
        easySlow = pace(zone(.easy)?.slowSpeed ?? 2.7)
        marathon = pace(zone(.marathon)?.fastSpeed ?? 3.3)
        threshold = pace(zone(.threshold)?.fastSpeed ?? 3.6)
        interval = pace(zone(.interval)?.fastSpeed ?? 4)
        repetition = pace(zone(.repetition)?.fastSpeed ?? 4.3)
        race = racePace ?? threshold
    }

    public var easy: Double { (easyFast + easySlow) / 2 }
    /// Trote de recuperación entre series.
    public var jog: Double { easySlow + 20 }
}

/// Entrenos con tus ritmos: rodajes, tirada larga, tempo, umbral, series, repeticiones, cuestas, fartlek…
public enum WorkoutLibrary {
    static func km(_ m: Double) -> String {
        m >= 1000 ? (m.truncatingRemainder(dividingBy: 1000) == 0 ? "\(Int(m / 1000)) km"
                                                                  : String(format: "%.1f km", m / 1000).replacingOccurrences(of: ".", with: ","))
            : "\(Int(m)) m"
    }

    static func minutes(_ s: Double) -> String {
        s >= 60 ? (s.truncatingRemainder(dividingBy: 60) == 0 ? "\(Int(s / 60)) min" : "\(Int(s / 60)) min \(Int(s.truncatingRemainder(dividingBy: 60))) s")
            : "\(Int(s)) s"
    }

    static func warmup(_ p: PaceSet, meters: Double = 2000) -> WorkoutStepPlan {
        WorkoutStepPlan(.warmup, .distance(meters), .range(fast: p.easyFast, slow: p.easySlow), label: "Calentamiento suave", expectedPace: p.easy)
    }

    static func cooldown(_ p: PaceSet, meters: Double = 1500) -> WorkoutStepPlan {
        WorkoutStepPlan(.cooldown, .distance(meters), .range(fast: p.easyFast, slow: p.easySlow + 15), label: "Vuelta a la calma",
                        expectedPace: p.easySlow)
    }

    static func id(_ kind: SessionKind, _ detail: String) -> String { "\(kind.rawValue)-\(detail)" }

    public static func easy(meters: Double, _ p: PaceSet) -> StructuredWorkout {
        StructuredWorkout(id: id(.easy, "\(Int(meters))"), kind: .easy, title: "Rodaje suave de \(km(meters))",
                          purpose: "Base aeróbica: cómodo, pudiendo hablar.",
                          blocks: [WorkoutBlockPlan(steps: [WorkoutStepPlan(.steady, .distance(meters), .range(fast: p.easyFast, slow: p.easySlow),
                                                                            label: "Suave", expectedPace: p.easy)])])
    }

    public static func recovery(minutes: Double, _ p: PaceSet) -> StructuredWorkout {
        StructuredWorkout(id: id(.recovery, "\(Int(minutes))"), kind: .recovery, title: "Trote de \(Int(minutes)) min",
                          purpose: "Soltar piernas: muy suave, en zona 1–2.",
                          blocks: [WorkoutBlockPlan(steps: [WorkoutStepPlan(.steady, .time(minutes * 60), .zone(2), label: "Muy suave",
                                                                            expectedPace: p.easySlow + 10)])])
    }

    /// Tirada larga; con `finishAtMarathonPace` metros finales a ritmo de maratón.
    public static func long(meters: Double, finishAtMarathonPace mp: Double = 0, _ p: PaceSet) -> StructuredWorkout {
        var steps = [WorkoutStepPlan(.steady, .distance(meters - mp), .range(fast: p.easyFast, slow: p.easySlow), label: "Suave",
                                     expectedPace: p.easy)]
        if mp > 0 { steps.append(WorkoutStepPlan(.work, .distance(mp), .pace(p.marathon), label: "Ritmo maratón", expectedPace: p.marathon)) }
        return StructuredWorkout(id: id(.long, "\(Int(meters))-\(Int(mp))"), kind: .long,
                                 title: mp > 0 ? "Tirada larga de \(km(meters)) (últimos \(km(mp)) a ritmo M)" : "Tirada larga de \(km(meters))",
                                 purpose: "Resistencia: suave y constante; bebe y come como el día de la carrera.",
                                 blocks: [WorkoutBlockPlan(steps: steps)])
    }

    public static func tempo(minutes: Double, _ p: PaceSet) -> StructuredWorkout {
        StructuredWorkout(id: id(.tempo, "\(Int(minutes))"), kind: .tempo, title: "Tempo de \(Int(minutes)) min a ritmo umbral",
                          purpose: "Sube el umbral: «cómodamente duro», sin llegar a sufrir.", warmup: warmup(p),
                          blocks: [WorkoutBlockPlan(steps: [WorkoutStepPlan(.work, .time(minutes * 60), .pace(p.threshold), label: "Umbral",
                                                                            expectedPace: p.threshold)])],
                          cooldown: cooldown(p))
    }

    /// Series a ritmo umbral con 1 min de trote.
    public static func threshold(reps: Int, meters: Double, _ p: PaceSet) -> StructuredWorkout {
        StructuredWorkout(id: id(.threshold, "\(reps)x\(Int(meters))"), kind: .threshold, title: "\(reps) × \(km(meters)) a ritmo umbral",
                          purpose: "Umbral en tramos: mucho trabajo de calidad con poca fatiga.", warmup: warmup(p),
                          blocks: [WorkoutBlockPlan(steps: [
                              WorkoutStepPlan(.work, .distance(meters), .pace(p.threshold), label: "Umbral", expectedPace: p.threshold),
                              WorkoutStepPlan(.recovery, .time(60), .none, label: "Trote", expectedPace: p.jog),
                          ], iterations: reps)],
                          cooldown: cooldown(p))
    }

    /// Series a ritmo de VO₂ máx. con trote del mismo tiempo que la serie.
    public static func intervals(reps: Int, meters: Double, _ p: PaceSet) -> StructuredWorkout {
        let rest = (meters / 1000 * p.interval).rounded()
        return StructuredWorkout(id: id(.intervals, "\(reps)x\(Int(meters))"), kind: .intervals, title: "\(reps) × \(km(meters)) a ritmo I",
                                 purpose: "VO₂ máx.: duro pero sostenible hasta la última; recupera trotando.", warmup: warmup(p),
                                 blocks: [WorkoutBlockPlan(steps: [
                                     WorkoutStepPlan(.work, .distance(meters), .pace(p.interval), label: "Ritmo I", expectedPace: p.interval),
                                     WorkoutStepPlan(.recovery, .time(rest), .none, label: "Trote", expectedPace: p.jog),
                                 ], iterations: reps)],
                                 cooldown: cooldown(p))
    }

    /// Repeticiones rápidas con recuperación completa (la misma distancia trotando).
    public static func repetitions(reps: Int, meters: Double, _ p: PaceSet) -> StructuredWorkout {
        StructuredWorkout(id: id(.repetitions, "\(reps)x\(Int(meters))"), kind: .repetitions, title: "\(reps) × \(km(meters)) a ritmo R",
                          purpose: "Velocidad y economía: rápido y suelto, recuperando del todo.", warmup: warmup(p),
                          blocks: [WorkoutBlockPlan(steps: [
                              WorkoutStepPlan(.work, .distance(meters), .pace(p.repetition, margin: 4), label: "Ritmo R", expectedPace: p.repetition),
                              WorkoutStepPlan(.recovery, .distance(meters), .none, label: "Trote", expectedPace: p.jog),
                          ], iterations: reps)],
                          cooldown: cooldown(p))
    }

    public static func hills(reps: Int, seconds: Double, _ p: PaceSet) -> StructuredWorkout {
        StructuredWorkout(id: id(.hills, "\(reps)x\(Int(seconds))"), kind: .hills, title: "\(reps) × \(minutes(seconds)) en cuesta",
                          purpose: "Fuerza y técnica: cuesta del 4–6 %, fuerte y con buena postura; baja trotando.", warmup: warmup(p),
                          blocks: [WorkoutBlockPlan(steps: [
                              WorkoutStepPlan(.work, .time(seconds), .zone(4), label: "Cuesta arriba, fuerte", expectedPace: p.threshold + 30),
                              WorkoutStepPlan(.recovery, .time(seconds * 1.5), .none, label: "Bajada trotando", expectedPace: p.jog),
                          ], iterations: reps)],
                          cooldown: cooldown(p))
    }

    public static func fartlek(reps: Int, on: Double, off: Double, _ p: PaceSet) -> StructuredWorkout {
        StructuredWorkout(id: id(.fartlek, "\(reps)x\(Int(on))-\(Int(off))"), kind: .fartlek,
                          title: "Fartlek: \(reps) × \(minutes(on)) rápido / \(minutes(off)) suave",
                          purpose: "Cambios de ritmo por sensaciones, sin mirar el reloj en exceso.", warmup: warmup(p, meters: 1500),
                          blocks: [WorkoutBlockPlan(steps: [
                              WorkoutStepPlan(.work, .time(on), .range(fast: p.interval, slow: p.threshold), label: "Rápido",
                                              expectedPace: (p.interval + p.threshold) / 2),
                              WorkoutStepPlan(.recovery, .time(off), .none, label: "Suave", expectedPace: p.easy),
                          ], iterations: reps)],
                          cooldown: cooldown(p, meters: 1000))
    }

    /// Un tercio suave, otro a ritmo de maratón y el último a umbral.
    public static func progression(meters: Double, _ p: PaceSet) -> StructuredWorkout {
        let third = (meters / 3 / 100).rounded() * 100
        return StructuredWorkout(id: id(.progression, "\(Int(meters))"), kind: .progression, title: "Progresivo de \(km(meters))",
                                 purpose: "De menos a más: acabar fuerte sin haberse vaciado.",
                                 blocks: [WorkoutBlockPlan(steps: [
                                     WorkoutStepPlan(.steady, .distance(meters - 2 * third), .range(fast: p.easyFast, slow: p.easySlow),
                                                     label: "Suave", expectedPace: p.easy),
                                     WorkoutStepPlan(.work, .distance(third), .pace(p.marathon), label: "Ritmo M", expectedPace: p.marathon),
                                     WorkoutStepPlan(.work, .distance(third), .pace(p.threshold), label: "Umbral", expectedPace: p.threshold),
                                 ])])
    }

    public static func marathonPace(meters: Double, _ p: PaceSet) -> StructuredWorkout {
        StructuredWorkout(id: id(.marathonPace, "\(Int(meters))"), kind: .marathonPace, title: "\(km(meters)) a ritmo de maratón",
                          purpose: "Ritmo específico: automatiza la sensación del ritmo de la carrera.", warmup: warmup(p),
                          blocks: [WorkoutBlockPlan(steps: [WorkoutStepPlan(.work, .distance(meters), .pace(p.marathon), label: "Ritmo M",
                                                                            expectedPace: p.marathon)])],
                          cooldown: cooldown(p, meters: 1000))
    }

    /// Tramos a ritmo de la carrera objetivo.
    public static func racePace(reps: Int, meters: Double, _ p: PaceSet) -> StructuredWorkout {
        StructuredWorkout(id: id(.racePace, "\(reps)x\(Int(meters))"), kind: .racePace, title: "\(reps) × \(km(meters)) a ritmo de carrera",
                          purpose: "Ensaya el ritmo del día D con las piernas algo cansadas.", warmup: warmup(p),
                          blocks: [WorkoutBlockPlan(steps: [
                              WorkoutStepPlan(.work, .distance(meters), .pace(p.race, margin: 4), label: "Ritmo de carrera", expectedPace: p.race),
                              WorkoutStepPlan(.recovery, .time(90), .none, label: "Trote", expectedPace: p.jog),
                          ], iterations: reps)],
                          cooldown: cooldown(p, meters: 1000))
    }

    public static func strides(meters: Double, reps: Int, _ p: PaceSet) -> StructuredWorkout {
        StructuredWorkout(id: id(.strides, "\(Int(meters))-\(reps)"), kind: .strides, title: "Rodaje de \(km(meters)) + \(reps) progresiones",
                          purpose: "Suave y, al final, aceleraciones cortas y sueltas para la técnica.",
                          blocks: [
                              WorkoutBlockPlan(steps: [WorkoutStepPlan(.steady, .distance(meters), .range(fast: p.easyFast, slow: p.easySlow),
                                                                       label: "Suave", expectedPace: p.easy)]),
                              WorkoutBlockPlan(steps: [
                                  WorkoutStepPlan(.work, .time(20), .pace(p.repetition, margin: 8), label: "Progresión", expectedPace: p.repetition),
                                  WorkoutStepPlan(.recovery, .time(60), .none, label: "Andar o trotar", expectedPace: p.jog + 60),
                              ], iterations: reps),
                          ])
    }

    public static func race(_ goal: GoalRace, _ p: PaceSet) -> StructuredWorkout {
        StructuredWorkout(id: id(.race, "\(Int(goal.distanceM))"), kind: .race, title: goal.name.isEmpty ? "Carrera" : goal.name,
                          purpose: "El día D: sal a tu ritmo y no te dejes llevar en el primer km.",
                          warmup: WorkoutStepPlan(.warmup, .time(600), .none, label: "Calentamiento", expectedPace: p.easySlow),
                          blocks: [WorkoutBlockPlan(steps: [WorkoutStepPlan(.work, .distance(goal.distanceM), .pace(p.race, margin: 4),
                                                                            label: "Ritmo de carrera", expectedPace: p.race)])])
    }

    /// Entrenos sueltos con tus ritmos actuales.
    public static func templates(vdot: Double) -> [StructuredWorkout] {
        let p = PaceSet(vdot: vdot)
        return [easy(meters: 8000, p), recovery(minutes: 30, p), long(meters: 16_000, p), strides(meters: 6000, reps: 6, p),
                tempo(minutes: 20, p), threshold(reps: 4, meters: 1600, p), intervals(reps: 5, meters: 1000, p),
                intervals(reps: 6, meters: 800, p), repetitions(reps: 10, meters: 400, p), hills(reps: 8, seconds: 60, p),
                fartlek(reps: 8, on: 60, off: 60, p), progression(meters: 12_000, p), marathonPace(meters: 10_000, p)]
    }
}
