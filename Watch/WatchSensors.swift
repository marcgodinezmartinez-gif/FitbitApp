import Foundation
import HealthKit
import CoreLocation
import WatchKit
import FaceKit

/// Lo que mide el propio reloj para las esferas: pulso de la última hora, pasos, anillos, batería, rumbo y el tiempo.
/// Solo se pide permiso (Salud, ubicación) si alguna de tus esferas lo enseña.
@MainActor
final class WatchSensors: NSObject, CLLocationManagerDelegate {
    static let shared = WatchSensors()

    private let health = HKHealthStore()
    private let location = CLLocationManager()
    private var askedHealth = false
    private var headingOn = false
    private var wantsWeather = false
    private var wantsHeading = false
    private var lastWeatherRequest: Date?

    override init() {
        super.init()
        location.delegate = self
        location.headingFilter = 2
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
    }

    /// Una pasada con lo que necesiten las esferas.
    func refresh(designs: [FaceDesign]) async {
        let store = FaceStore.shared
        let level = WKInterfaceDevice.current().batteryLevel
        store.sensors.battery = level >= 0 ? Double(level) : nil
        if designs.contains(where: { $0.needsHealth }), HKHealthStore.isHealthDataAvailable() {
            await authorizeHealth()
            if let hr = await heartRate() {
                store.sensors.heartRate = hr.last
                store.sensors.heartRateAt = hr.at
                store.sensors.heartRateTrend = hr.trend
            }
            if let steps = await steps() { store.sensors.steps = steps }
            if let rings = await rings() { store.sensors.rings = rings }
        }
        let all = designs.reduce(into: Set<FaceComplication>()) { $0.formUnion($1.complications) }
        wantsWeather = all.contains(.weather)
        wantsHeading = all.contains(.compass)
        startLocation()
    }

    /// Con la muñeca bajada no hace falta la brújula.
    func pause() {
        if headingOn {
            location.stopUpdatingHeading()
            headingOn = false
        }
    }

    // MARK: Salud

    private func authorizeHealth() async {
        guard !askedHealth else { return }
        askedHealth = true
        let types: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.stepCount), HKObjectType.activitySummaryType()]
        try? await health.requestAuthorization(toShare: [], read: types)
    }

    /// Último pulso y la línea de la última hora (medias de 5 minutos).
    private func heartRate() async -> (last: Double, at: Date, trend: [Double])? {
        let now = Date()
        let predicate = HKQuery.predicateForSamples(withStart: now.addingTimeInterval(-3600), end: nil)
        let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(.heartRate), predicate: predicate)],
                                                 sortDescriptors: [SortDescriptor(\.endDate)])
        guard let samples = try? await descriptor.result(for: health), let last = samples.last else { return nil }
        let unit = HKUnit.count().unitDivided(by: .minute())
        var buckets = [[Double]](repeating: [], count: 12)
        for s in samples {
            let k = Int(s.endDate.timeIntervalSince(now.addingTimeInterval(-3600)) / 300)
            if buckets.indices.contains(k) { buckets[k].append(s.quantity.doubleValue(for: unit)) }
        }
        var trend: [Double] = []
        for b in buckets where !b.isEmpty { trend.append(b.reduce(0, +) / Double(b.count)) }
        return (last.quantity.doubleValue(for: unit), last.endDate, trend)
    }

    private func steps() async -> Int? {
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: Date()), end: nil)
        let descriptor = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: HKQuantityType(.stepCount), predicate: predicate),
                                                     options: .cumulativeSum)
        guard let stats = try? await descriptor.result(for: health), let sum = stats.sumQuantity() else { return nil }
        return Int(sum.doubleValue(for: .count()))
    }

    private func rings() async -> FaceRings? {
        var day = Calendar.current.dateComponents([.era, .year, .month, .day], from: Date())
        day.calendar = Calendar.current
        let descriptor = HKActivitySummaryQueryDescriptor(predicate: HKQuery.predicate(forActivitySummariesBetweenStart: day, end: day))
        guard let summaries = try? await descriptor.result(for: health), let s = summaries.first else { return nil }
        let moveGoal = s.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())
        let exerciseGoal = s.exerciseTimeGoal?.doubleValue(for: .minute()) ?? 30
        let standGoal = s.standHoursGoal?.doubleValue(for: .count()) ?? 12
        return FaceRings(move: s.activeEnergyBurned.doubleValue(for: .kilocalorie()) / max(1, moveGoal),
                         exercise: s.appleExerciseTime.doubleValue(for: .minute()) / max(1, exerciseGoal),
                         stand: s.appleStandHours.doubleValue(for: .count()) / max(1, standGoal))
    }

    // MARK: Brújula y el tiempo

    private func startLocation() {
        guard wantsWeather || wantsHeading else { return pause() }
        switch location.authorizationStatus {
        case .notDetermined:
            location.requestWhenInUseAuthorization()
            return
        case .authorizedWhenInUse, .authorizedAlways:
            break
        default:
            return
        }
        if wantsHeading, CLLocationManager.headingAvailable(), !headingOn {
            location.startUpdatingHeading()
            headingOn = true
        }
        if wantsWeather, Date().timeIntervalSince(lastWeatherRequest ?? .distantPast) > FaceWeatherService.refreshInterval {
            lastWeatherRequest = Date()
            location.requestLocation()
        }
    }

    private func fetchWeather(latitude: Double, longitude: Double) async {
        guard let url = FaceWeatherService.currentURL(latitude: latitude, longitude: longitude),
              let response = try? await URLSession.shared.data(from: url),
              let weather = FaceWeatherService.parseCurrent(response.0, now: Date()) else { return }
        FaceStore.shared.sensors.weather = weather
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in FaceStore.shared.sensors.heading = heading }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let latitude = last.coordinate.latitude, longitude = last.coordinate.longitude
        Task { @MainActor in await self.fetchWeather(latitude: latitude, longitude: longitude) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.lastWeatherRequest = nil
            self.startLocation()
        }
    }
}
