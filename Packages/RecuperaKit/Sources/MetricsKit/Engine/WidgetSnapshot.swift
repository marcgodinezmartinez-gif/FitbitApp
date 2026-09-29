import Foundation

/// Instantánea ligera para los *widgets* y la pantalla de bloqueo (App Group, doc. 08 §3).
public struct WidgetSnapshot: Codable, Sendable, Hashable {
    public var date: String
    public var updatedAt: Date
    public var sleepPerformance: Int?
    public var recovery: Int?
    public var recoveryZone: String?
    public var strain: Double
    public var targetLow: Double?
    public var targetHigh: Double?
    public var recommendation: String
    public var bedtime: String?
    /// Mostrar cifras en la pantalla de bloqueo (RF-WID-04); si no, los *widgets* de bloqueo las ocultan.
    public var showValuesOnLockScreen: Bool?

    public init(date: String, updatedAt: Date, sleepPerformance: Int?, recovery: Int?, recoveryZone: String?, strain: Double,
                targetLow: Double?, targetHigh: Double?, recommendation: String, bedtime: String?, showValuesOnLockScreen: Bool? = nil) {
        self.date = date
        self.updatedAt = updatedAt
        self.sleepPerformance = sleepPerformance
        self.recovery = recovery
        self.recoveryZone = recoveryZone
        self.strain = strain
        self.targetLow = targetLow
        self.targetHigh = targetHigh
        self.recommendation = recommendation
        self.bedtime = bedtime
        self.showValuesOnLockScreen = showValuesOnLockScreen
    }

    public static let placeholder = WidgetSnapshot(date: "2026-09-29", updatedAt: Date(timeIntervalSince1970: 1_790_000_000),
                                                   sleepPerformance: 92, recovery: 72, recoveryZone: "high", strain: 8.4,
                                                   targetLow: 12, targetHigh: 15, recommendation: "Buen día para apretar.", bedtime: "23:10")
}
