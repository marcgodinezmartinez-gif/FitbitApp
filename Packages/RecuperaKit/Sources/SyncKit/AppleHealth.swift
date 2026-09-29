import Foundation
import MetricsKit
import Store

/// Lo que llega de Salud (Apple Watch) en una importación incremental (doc. 16 §6).
public struct AppleHealthImport: Sendable {
    public var workouts: [ActivitySession]
    public var deletedWorkoutIDs: [String]
    public var workoutHeartRate: [String: [HRSample]]     // muestras por entrenamiento (id de origen)
    public var heartRateMinutes: [HRMinute]                // FC del Watch agregada por minuto
    public var routes: [String: [RoutePoint]]
    public var metricSamples: [String: [MetricSample]]
    public var vo2max: [VO2MaxValue]
    public var earliestAuthorized: Date?

    public init(workouts: [ActivitySession] = [], deletedWorkoutIDs: [String] = [], workoutHeartRate: [String: [HRSample]] = [:],
                heartRateMinutes: [HRMinute] = [], routes: [String: [RoutePoint]] = [:], metricSamples: [String: [MetricSample]] = [:],
                vo2max: [VO2MaxValue] = [], earliestAuthorized: Date? = nil) {
        self.workouts = workouts
        self.deletedWorkoutIDs = deletedWorkoutIDs
        self.workoutHeartRate = workoutHeartRate
        self.heartRateMinutes = heartRateMinutes
        self.routes = routes
        self.metricSamples = metricSamples
        self.vo2max = vo2max
        self.earliestAuthorized = earliestAuthorized
    }

    public var isEmpty: Bool { workouts.isEmpty && deletedWorkoutIDs.isEmpty && heartRateMinutes.isEmpty && vo2max.isEmpty }
}

/// Anclas de las consultas incrementales de HealthKit, guardadas en la BD.
public protocol AnchorStore: Sendable {
    func anchor(for sampleType: String) throws -> Data?
    func setAnchor(_ data: Data?, for sampleType: String) throws
}

extension AppDatabase: AnchorStore {}

/// Implementación en la app (HealthKit); en los tests, un simulador.
public protocol AppleHealthProvider: Sendable {
    var isAvailable: Bool { get }
    func requestAuthorization() async throws
    /// Importa lo nuevo desde las anclas guardadas (o `backfillDays` si no hay ancla).
    func importChanges(anchors: AnchorStore, backfillDays: Int) async throws -> AppleHealthImport
}
