import Foundation
import MetricsKit

/// Ajustes de la app (tabla `app_state`, clave `settings`). Las claves de IA NO están aquí (Llavero).
public struct AppSettings: Codable, Sendable, Hashable {
    public enum Theme: String, Codable, Sendable, CaseIterable { case system, dark, light }
    public enum Units: String, Codable, Sendable, CaseIterable { case metric, imperial }
    public enum CoachProvider: String, Codable, Sendable, CaseIterable { case anthropic, gemini }
    public enum CoachMode: String, Codable, Sendable, CaseIterable { case personal, educational }

    public var onboardingCompleted: Bool = false
    public var disclaimerVersionAccepted: Int = 0
    public var demoMode: Bool = false
    public var units: Units = .metric
    public var theme: Theme = .dark
    public var appLock: Bool = false
    public var lockscreenShowsValues: Bool = false
    public var quietHoursStart: Int = 22 * 60 + 30
    public var quietHoursEnd: Int = 7 * 60
    public var notifications: [String: Bool] = [
        "NOT-01": true, "NOT-02": true, "NOT-03": false, "NOT-04": true, "NOT-05": true, "NOT-06": true,
        "NOT-07": true, "NOT-08": false, "NOT-09": false, "NOT-10": false, "NOT-11": true, "NOT-12": true,
    ]
    public var hrWorkoutPriority: String = "apple_watch"
    public var healthKitEnabled: Bool = false
    public var excludeFromICloudBackup: Bool = true
    public var journalEnabled: [String: Bool] = [:]
    public var plannerGoal: Int = 0
    public var bedtimeReminder: Bool = true
    public var coachEnabled: Bool = false
    public var coachMode: CoachMode = .personal
    public var coachProvider: CoachProvider = .anthropic
    public var coachModel: [String: String] = ["anthropic": "claude-opus-5-5", "gemini": "gemini-3.8-flash"]
    public var coachEffort: String = "medium"
    public var coachDailyLimit: Int = 20
    public var coachMonthlyBudgetUSD: Double = 5
    public var geminiPaidTierConfirmed: Bool = false
    public var coachConsentVersion: Int = 0
    public var eveningAnalysis: Bool = false

    public init() {}

    public func isOn(_ notification: String) -> Bool { notifications[notification] ?? false }
}

/// Estado de las conexiones (tabla `app_state`, clave `connection`). Sin *tokens*.
public struct ConnectionState: Codable, Sendable, Hashable {
    public enum Status: String, Codable, Sendable { case disconnected, active, needsReauth, revoked }

    public var googleStatus: Status = .disconnected
    public var healthUserId: String?
    public var grantedScopes: [String] = []
    public var connectedAt: Date?
    public var lastSuccessSyncAt: Date?
    public var deviceLastSyncAt: Date?
    public var deviceName: String?
    public var deviceBattery: Int?
    public var timeZone: String?
    public var lastError: String?
    public var healthKitConnectedAt: Date?
    public var healthKitLastImportAt: Date?
    public var healthKitEarliestAuthorized: Date?
    public var backfillCompleted: Bool = false

    public init() {}
}

/// Resumen global del motor (lo que no es de un ciclo concreto).
public struct EngineSummary: Codable, Sendable, Hashable {
    public var algorithmVersion: String
    public var computedAt: Date
    public var hrMax: Double
    public var observedHRMax: Double?
    public var acuteLoad: Double?
    public var chronicLoad: Double?
    public var habitImpacts: [HabitImpact]
    public var physioAge: PhysioAgeResult?
    public var primaryVO2: VO2MaxValue?
    public var agreementSummary: HRAgreement?
    public var tonightNeed: SleepNeedBreakdown?
    public var usualEfficiency: Double?
    public var usualLatency: Double?

    public init(output: MetricsOutput, computedAt: Date) {
        algorithmVersion = output.algorithmVersion
        self.computedAt = computedAt
        hrMax = output.hrMax
        observedHRMax = output.observedHRMax
        acuteLoad = output.acuteLoad
        chronicLoad = output.chronicLoad
        habitImpacts = output.habitImpacts
        physioAge = output.physioAge
        primaryVO2 = output.primaryVO2
        agreementSummary = output.agreementSummary
        tonightNeed = output.tonightNeed
        usualEfficiency = output.usualEfficiency
        usualLatency = output.usualLatency
    }
}

/// Anotaciones del usuario sobre una actividad de origen (no se pierden al volver a sincronizar).
public struct ActivityAnnotation: Codable, Sendable, Hashable {
    public var activityID: String
    public var rpe: Double?
    public var notes: String?
    public var kindOverride: ActivityKind?
    public var nameOverride: String?

    public init(activityID: String, rpe: Double? = nil, notes: String? = nil, kindOverride: ActivityKind? = nil, nameOverride: String? = nil) {
        self.activityID = activityID
        self.rpe = rpe
        self.notes = notes
        self.kindOverride = kindOverride
        self.nameOverride = nameOverride
    }
}

public struct RoutePoint: Codable, Sendable, Hashable {
    public var time: Date
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double?
    public var speed: Double?
    public var horizontalAccuracy: Double?

    public init(time: Date, latitude: Double, longitude: Double, altitude: Double? = nil, speed: Double? = nil, horizontalAccuracy: Double? = nil) {
        self.time = time
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.speed = speed
        self.horizontalAccuracy = horizontalAccuracy
    }
}

public struct MetricSample: Codable, Sendable, Hashable {
    public var metric: String      // power_w, speed_mps, stride_m, vertical_osc_cm, ground_contact_ms
    public var time: Date
    public var value: Double

    public init(metric: String, time: Date, value: Double) {
        self.metric = metric
        self.time = time
        self.value = value
    }
}

public struct CoachThread: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var provider: String
    public var model: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, title: String, provider: String, model: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.provider = provider
        self.model = model
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct CoachMessageRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var threadID: String
    public var role: String            // user | assistant | tool
    public var model: String?
    public var contentJSON: String     // bloques tal como los devolvió el proveedor
    public var displayText: String
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadTokens: Int
    public var cacheWriteTokens: Int
    public var costUSD: Double
    public var rating: Int?
    public var createdAt: Date

    public init(id: String = UUID().uuidString, threadID: String, role: String, model: String?, contentJSON: String, displayText: String,
                inputTokens: Int = 0, outputTokens: Int = 0, cacheReadTokens: Int = 0, cacheWriteTokens: Int = 0,
                costUSD: Double = 0, rating: Int? = nil, createdAt: Date = Date()) {
        self.id = id
        self.threadID = threadID
        self.role = role
        self.model = model
        self.contentJSON = contentJSON
        self.displayText = displayText
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.costUSD = costUSD
        self.rating = rating
        self.createdAt = createdAt
    }
}

public struct CoachMemoryItem: Codable, Sendable, Hashable, Identifiable {
    public var category: String
    public var key: String
    public var value: String
    public var updatedAt: Date
    public var id: String { "\(category)/\(key)" }

    public init(category: String, key: String, value: String, updatedAt: Date = Date()) {
        self.category = category
        self.key = key
        self.value = value
        self.updatedAt = updatedAt
    }
}

public struct StoredDayAnalysis: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var cycleID: String
    public var date: String
    public var createdAt: Date
    public var kind: String           // deterministic | ai
    public var json: String
    public var provider: String?
    public var model: String?

    public init(id: String = UUID().uuidString, cycleID: String, date: String, createdAt: Date = Date(), kind: String, json: String,
                provider: String? = nil, model: String? = nil) {
        self.id = id
        self.cycleID = cycleID
        self.date = date
        self.createdAt = createdAt
        self.kind = kind
        self.json = json
        self.provider = provider
        self.model = model
    }
}

public struct SyncLogEntry: Codable, Sendable, Hashable {
    public var startedAt: Date
    public var finishedAt: Date
    public var source: String
    public var kind: String
    public var status: String
    public var records: Int
    public var error: String?

    public init(startedAt: Date, finishedAt: Date, source: String, kind: String, status: String, records: Int, error: String? = nil) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.source = source
        self.kind = kind
        self.status = status
        self.records = records
        self.error = error
    }
}
