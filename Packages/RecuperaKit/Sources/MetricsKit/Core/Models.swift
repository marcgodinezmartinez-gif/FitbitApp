import Foundation

// MARK: - Frecuencia cardiaca y actividad por minuto

/// FC agregada por minuto (Fitbit: `rollUp` de 60 s; Watch: media de sus muestras).
public struct HRMinute: Hashable, Codable, Sendable {
    public var minute: Int            // segundos desde la época, múltiplo de 60 (UTC)
    public var bpmAvg: Double
    public var bpmMin: Double?
    public var bpmMax: Double?
    public var samples: Int            // nº de muestras (Fitbit: 0 = desconocido)
    public var source: DataSourceKind

    public init(minute: Int, bpmAvg: Double, bpmMin: Double? = nil, bpmMax: Double? = nil, samples: Int = 0, source: DataSourceKind) {
        self.minute = minute
        self.bpmAvg = bpmAvg
        self.bpmMin = bpmMin
        self.bpmMax = bpmMax
        self.samples = samples
        self.source = source
    }

    public var date: Date { Date(timeIntervalSince1970: TimeInterval(minute)) }
}

/// Muestra de FC de alta resolución (entrenamientos).
public struct HRSample: Hashable, Codable, Sendable {
    public var time: Date
    public var bpm: Double
    public var source: DataSourceKind

    public init(time: Date, bpm: Double, source: DataSourceKind) {
        self.time = time
        self.bpm = bpm
        self.source = source
    }
}

/// Pasos y distancia por minuto.
public struct ActivityMinute: Hashable, Codable, Sendable {
    public var minute: Int
    public var steps: Int
    public var distanceM: Double
    public var source: DataSourceKind

    public init(minute: Int, steps: Int, distanceM: Double = 0, source: DataSourceKind) {
        self.minute = minute
        self.steps = steps
        self.distanceM = distanceM
        self.source = source
    }
}

// MARK: - Sueño

public enum SleepStageKind: String, Codable, Sendable, CaseIterable {
    case wake, light, deep, rem, asleep

    public var isAsleep: Bool { self != .wake }
}

public struct SleepStageSegment: Hashable, Codable, Sendable {
    public var start: Date
    public var end: Date
    public var stage: SleepStageKind

    public init(start: Date, end: Date, stage: SleepStageKind) {
        self.start = start
        self.end = end
        self.stage = stage
    }

    public var minutes: Double { end.timeIntervalSince(start) / 60 }
}

public struct SleepSession: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var source: DataSourceKind
    public var start: Date
    public var end: Date
    public var utcOffsetSeconds: Int
    /// Indicadores de la API (`metadata.mainSleep`, `metadata.nap`), si existen.
    public var isMainFromSource: Bool?
    public var isNapFromSource: Bool?
    public var stages: [SleepStageSegment]
    public var minutesAsleepFromSource: Int?
    public var minutesAwakeFromSource: Int?
    public var latencyFromSource: Int?

    public init(id: String, source: DataSourceKind = .googleHealth, start: Date, end: Date, utcOffsetSeconds: Int,
                isMainFromSource: Bool? = nil, isNapFromSource: Bool? = nil, stages: [SleepStageSegment] = [],
                minutesAsleepFromSource: Int? = nil, minutesAwakeFromSource: Int? = nil, latencyFromSource: Int? = nil) {
        self.id = id
        self.source = source
        self.start = start
        self.end = end
        self.utcOffsetSeconds = utcOffsetSeconds
        self.isMainFromSource = isMainFromSource
        self.isNapFromSource = isNapFromSource
        self.stages = stages.sorted { $0.start < $1.start }
        self.minutesAsleepFromSource = minutesAsleepFromSource
        self.minutesAwakeFromSource = minutesAwakeFromSource
        self.latencyFromSource = latencyFromSource
    }

    public var range: TimeRange { TimeRange(start: start, end: end) }
    public var timeInBedMinutes: Double { end.timeIntervalSince(start) / 60 }

    /// Minutos dormidos = ligero + profundo + REM (o «dormido» sin fases).
    public var minutesAsleep: Double {
        if !stages.isEmpty {
            return stages.filter { $0.stage.isAsleep }.reduce(0) { $0 + $1.minutes }
        }
        if let m = minutesAsleepFromSource { return Double(m) }
        return timeInBedMinutes
    }

    public func minutes(in stage: SleepStageKind) -> Double {
        stages.filter { $0.stage == stage }.reduce(0) { $0 + $1.minutes }
    }

    public var hasStages: Bool { stages.contains { $0.stage == .deep || $0.stage == .rem || $0.stage == .light } }

    /// Fecha local en la que termina (la del despertar).
    public var wakeDate: LocalDate { LocalDate(end, utcOffsetSeconds: utcOffsetSeconds) }
}

// MARK: - Actividades

public enum ActivityKind: String, Codable, Sendable, CaseIterable {
    case running, trailRunning, treadmill, walking, hiking, cycling, indoorCycling, swimming
    case strength, hiit, elliptical, rowing, yoga, pilates, sports, dance, other

    public var isRun: Bool { self == .running || self == .trailRunning || self == .treadmill }
    public var isStrength: Bool { self == .strength }

    public var displayName: String {
        switch self {
        case .running: return "Carrera"
        case .trailRunning: return "Carrera por montaña"
        case .treadmill: return "Cinta"
        case .walking: return "Caminata"
        case .hiking: return "Senderismo"
        case .cycling: return "Bici"
        case .indoorCycling: return "Bici estática"
        case .swimming: return "Natación"
        case .strength: return "Fuerza"
        case .hiit: return "HIIT"
        case .elliptical: return "Elíptica"
        case .rowing: return "Remo"
        case .yoga: return "Yoga"
        case .pilates: return "Pilates"
        case .sports: return "Deporte"
        case .dance: return "Baile"
        case .other: return "Actividad"
        }
    }

    public var symbolName: String {
        switch self {
        case .running, .trailRunning, .treadmill: return "figure.run"
        case .walking: return "figure.walk"
        case .hiking: return "figure.hiking"
        case .cycling, .indoorCycling: return "figure.outdoor.cycle"
        case .swimming: return "figure.pool.swim"
        case .strength: return "dumbbell.fill"
        case .hiit: return "flame.fill"
        case .elliptical: return "figure.elliptical"
        case .rowing: return "figure.rower"
        case .yoga: return "figure.yoga"
        case .pilates: return "figure.pilates"
        case .sports: return "sportscourt.fill"
        case .dance: return "figure.dance"
        case .other: return "figure.mixed.cardio"
        }
    }
}

public struct RunningDynamics: Hashable, Codable, Sendable {
    public var avgPowerW: Double?
    public var avgSpeedMps: Double?
    public var avgStrideM: Double?
    public var avgVerticalOscillationCm: Double?
    public var avgGroundContactMs: Double?
    public var avgCadenceSpm: Double?

    public init(avgPowerW: Double? = nil, avgSpeedMps: Double? = nil, avgStrideM: Double? = nil,
                avgVerticalOscillationCm: Double? = nil, avgGroundContactMs: Double? = nil, avgCadenceSpm: Double? = nil) {
        self.avgPowerW = avgPowerW
        self.avgSpeedMps = avgSpeedMps
        self.avgStrideM = avgStrideM
        self.avgVerticalOscillationCm = avgVerticalOscillationCm
        self.avgGroundContactMs = avgGroundContactMs
        self.avgCadenceSpm = avgCadenceSpm
    }

    public var isEmpty: Bool {
        avgPowerW == nil && avgSpeedMps == nil && avgStrideM == nil && avgVerticalOscillationCm == nil
            && avgGroundContactMs == nil && avgCadenceSpm == nil
    }
}

/// Actividad de una fuente (una fila por fuente, doc. 09).
public struct ActivitySession: Hashable, Codable, Sendable, Identifiable {
    public var id: String                  // único entre fuentes: "<source>:<sourceRecordID>"
    public var source: DataSourceKind
    public var sourceRecordID: String
    public var kind: ActivityKind
    public var name: String?
    public var start: Date
    public var end: Date
    public var utcOffsetSeconds: Int
    public var avgHR: Double?
    public var maxHR: Double?
    public var caloriesKcal: Double?
    public var distanceM: Double?
    public var steps: Int?
    public var elevationGainM: Double?
    public var hasRoute: Bool
    public var dynamics: RunningDynamics?
    public var hrRecovery1Min: Double?
    public var effortScore: Double?
    public var isManual: Bool
    public var rpe: Double?
    public var notes: String?

    public init(source: DataSourceKind, sourceRecordID: String, kind: ActivityKind, name: String? = nil,
                start: Date, end: Date, utcOffsetSeconds: Int, avgHR: Double? = nil, maxHR: Double? = nil,
                caloriesKcal: Double? = nil, distanceM: Double? = nil, steps: Int? = nil, elevationGainM: Double? = nil,
                hasRoute: Bool = false, dynamics: RunningDynamics? = nil, hrRecovery1Min: Double? = nil,
                effortScore: Double? = nil, isManual: Bool = false, rpe: Double? = nil, notes: String? = nil) {
        self.id = "\(source.rawValue):\(sourceRecordID)"
        self.source = source
        self.sourceRecordID = sourceRecordID
        self.kind = kind
        self.name = name
        self.start = start
        self.end = max(start, end)
        self.utcOffsetSeconds = utcOffsetSeconds
        self.avgHR = avgHR
        self.maxHR = maxHR
        self.caloriesKcal = caloriesKcal
        self.distanceM = distanceM
        self.steps = steps
        self.elevationGainM = elevationGainM
        self.hasRoute = hasRoute
        self.dynamics = dynamics
        self.hrRecovery1Min = hrRecovery1Min
        self.effortScore = effortScore
        self.isManual = isManual
        self.rpe = rpe
        self.notes = notes
    }

    public var range: TimeRange { TimeRange(start: start, end: end) }
    public var durationMinutes: Double { end.timeIntervalSince(start) / 60 }
}

// MARK: - Vitales nocturnos y datos diarios

/// Valores diarios de la Fitbit Air (tipos diarios de la Google Health API).
public struct NightlyVitals: Hashable, Codable, Sendable {
    public var date: LocalDate
    public var restingHR: Double?
    public var hrvRmssdAvg: Double?
    public var hrvRmssdDeep: Double?
    public var nremHR: Double?
    public var respiratoryRate: Double?
    public var skinTempC: Double?
    public var spo2Avg: Double?

    public init(date: LocalDate, restingHR: Double? = nil, hrvRmssdAvg: Double? = nil, hrvRmssdDeep: Double? = nil,
                nremHR: Double? = nil, respiratoryRate: Double? = nil, skinTempC: Double? = nil, spo2Avg: Double? = nil) {
        self.date = date
        self.restingHR = restingHR
        self.hrvRmssdAvg = hrvRmssdAvg
        self.hrvRmssdDeep = hrvRmssdDeep
        self.nremHR = nremHR
        self.respiratoryRate = respiratoryRate
        self.skinTempC = skinTempC
        self.spo2Avg = spo2Avg
    }
}

public struct VO2MaxValue: Hashable, Codable, Sendable {
    public var date: LocalDate
    public var value: Double
    public var source: DataSourceKind

    public init(date: LocalDate, value: Double, source: DataSourceKind) {
        self.date = date
        self.value = value
        self.source = source
    }
}

// MARK: - Perfil

public struct UserProfile: Hashable, Codable, Sendable {
    public var birthDate: LocalDate?
    public var sex: Sex
    public var heightCm: Double?
    public var weightKg: Double?
    public var hrMaxOverride: Double?
    public var observedHRMaxConfirmed: Double?
    public var sleepBaseOverrideMin: Double?
    public var waistCm: Double?
    public var sports: [String]
    public var usualWakeMinutes: Int           // minutos desde medianoche (p. ej. 7:00 = 420)

    public init(birthDate: LocalDate? = nil, sex: Sex = .unspecified, heightCm: Double? = nil, weightKg: Double? = nil,
                hrMaxOverride: Double? = nil, observedHRMaxConfirmed: Double? = nil, sleepBaseOverrideMin: Double? = nil,
                waistCm: Double? = nil, sports: [String] = ["Carrera"], usualWakeMinutes: Int = 7 * 60) {
        self.birthDate = birthDate
        self.sex = sex
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.hrMaxOverride = hrMaxOverride
        self.observedHRMaxConfirmed = observedHRMaxConfirmed
        self.sleepBaseOverrideMin = sleepBaseOverrideMin
        self.waistCm = waistCm
        self.sports = sports
        self.usualWakeMinutes = usualWakeMinutes
    }

    public func age(on date: LocalDate) -> Double? {
        guard let b = birthDate else { return nil }
        return Double(date.days(since: b)) / 365.25
    }
}

// MARK: - Diario

public struct JournalAnswer: Hashable, Codable, Sendable {
    public var date: LocalDate
    public var questionKey: String
    public var yes: Bool?
    public var number: Double?

    public init(date: LocalDate, questionKey: String, yes: Bool? = nil, number: Double? = nil) {
        self.date = date
        self.questionKey = questionKey
        self.yes = yes
        self.number = number
    }
}
