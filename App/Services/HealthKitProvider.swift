import Foundation
import HealthKit
import CoreLocation
import MetricsKit
import Store
import SyncKit

/// Lectura de Salud (Apple Watch) con consultas incrementales por ancla (doc. 16 §6). Solo lectura: nunca escribe en Salud.
final class HealthKitProvider: AppleHealthProvider, @unchecked Sendable {
    let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static let quantityTypes: [HKQuantityTypeIdentifier] = [
        .heartRate, .distanceWalkingRunning, .distanceCycling, .activeEnergyBurned, .stepCount, .vo2Max,
        .runningPower, .runningSpeed, .runningStrideLength, .runningVerticalOscillation, .runningGroundContactTime,
        .heartRateRecoveryOneMinute, .workoutEffortScore, .estimatedWorkoutEffortScore,
    ]

    static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        for id in quantityTypes { types.insert(HKQuantityType(id)) }
        return types
    }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    // MARK: Importación incremental

    func importChanges(anchors: AnchorStore, backfillDays: Int) async throws -> AppleHealthImport {
        var result = AppleHealthImport()
        let since = Date().addingTimeInterval(-Double(backfillDays) * 86_400)

        // Entrenamientos (solo los grabados en un Apple Watch y que no vengan de apps de Google).
        let workoutAnchor = try anchors.anchor(for: "workouts").flatMap(Self.decodeAnchor)
        let workoutPredicate = workoutAnchor == nil ? HKQuery.predicateForSamples(withStart: since, end: nil) : nil
        let workouts = HKAnchoredObjectQueryDescriptor(predicates: [.workout(workoutPredicate)], anchor: workoutAnchor)
        let changes = try await workouts.result(for: store)
        result.deletedWorkoutIDs = changes.deletedObjects.map { $0.uuid.uuidString }
        for workout in changes.addedSamples where Self.accepts(workout) {
            let d = try await details(for: workout)
            let rid = d.session.sourceRecordID
            result.workouts.append(d.session)
            result.workoutHeartRate[rid] = d.heartRate
            if !d.route.isEmpty { result.routes[rid] = d.route }
            if !d.metrics.isEmpty { result.metricSamples[rid] = d.metrics }
            result.details[rid] = d.detail
            result.heartRateMinutes += Self.minutes(d.heartRate)
        }
        try anchors.setAnchor(Self.encodeAnchor(changes.newAnchor), for: "workouts")

        // VO₂máx estimado por el reloj.
        let vo2Anchor = try anchors.anchor(for: "vo2max").flatMap(Self.decodeAnchor)
        let vo2Predicate = vo2Anchor == nil ? HKQuery.predicateForSamples(withStart: since, end: nil) : nil
        let vo2 = HKAnchoredObjectQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(.vo2Max), predicate: vo2Predicate)],
                                                  anchor: vo2Anchor)
        let vo2Changes = try await vo2.result(for: store)
        let vo2Unit = HKUnit(from: "ml/kg*min")
        result.vo2max = vo2Changes.addedSamples.filter(Self.accepts).map {
            VO2MaxValue(date: LocalDate($0.startDate, timeZone: .current), value: $0.quantity.doubleValue(for: vo2Unit), source: .appleHealth)
        }
        try anchors.setAnchor(Self.encodeAnchor(vo2Changes.newAnchor), for: "vo2max")
        return result
    }

    static func accepts(_ sample: HKSample) -> Bool {
        Fusion.acceptsHealthKitSample(bundleIdentifier: sample.sourceRevision.source.bundleIdentifier,
                                      productType: sample.sourceRevision.productType)
    }

    static func encodeAnchor(_ anchor: HKQueryAnchor) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
    }

    static func decodeAnchor(_ data: Data) -> HKQueryAnchor? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    /// FC del Watch agregada por minuto (se usa en la fusión durante sus entrenamientos).
    static func minutes(_ samples: [HRSample]) -> [HRMinute] {
        Dictionary(grouping: samples, by: { $0.time.minuteEpoch }).map { minute, group in
            let values = group.map(\.bpm)
            return HRMinute(minute: minute, bpmAvg: values.reduce(0, +) / Double(values.count), bpmMin: values.min(), bpmMax: values.max(),
                            samples: values.count, source: .appleHealth)
        }.sorted { $0.minute < $1.minute }
    }

    // MARK: Detalle de un entrenamiento

    struct WorkoutDetails {
        var session: ActivitySession
        var heartRate: [HRSample]
        var route: [RoutePoint]
        var metrics: [MetricSample]
        var detail: ActivityDetail
    }

    func details(for w: HKWorkout) async throws -> WorkoutDetails {
        let rid = w.uuid.uuidString
        let zone = (w.metadata?[HKMetadataKeyTimeZone] as? String).flatMap(TimeZone.init(identifier:)) ?? .current
        let offset = zone.secondsFromGMT(for: w.startDate)
        let indoor = (w.metadata?[HKMetadataKeyIndoorWorkout] as? NSNumber)?.boolValue ?? false
        let kind = Self.kind(w.workoutActivityType, indoor: indoor)
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let mps = HKUnit.meter().unitDivided(by: .second())

        func stat(_ id: HKQuantityTypeIdentifier) -> HKStatistics? { w.statistics(for: HKQuantityType(id)) }

        let steps = stat(.stepCount)?.sumQuantity()?.doubleValue(for: .count())
        let minutes = w.duration / 60
        let dynamics = RunningDynamics(
            avgPowerW: stat(.runningPower)?.averageQuantity()?.doubleValue(for: .watt()),
            avgSpeedMps: stat(.runningSpeed)?.averageQuantity()?.doubleValue(for: mps),
            avgStrideM: stat(.runningStrideLength)?.averageQuantity()?.doubleValue(for: .meter()),
            avgVerticalOscillationCm: stat(.runningVerticalOscillation)?.averageQuantity()?.doubleValue(for: .meterUnit(with: .centi)),
            avgGroundContactMs: stat(.runningGroundContactTime)?.averageQuantity()?.doubleValue(for: .secondUnit(with: .milli)),
            avgCadenceSpm: kind.isRun ? steps.flatMap { minutes > 1 ? $0 / minutes : nil } : nil)

        let heartRate = try await samples(.heartRate, from: w.startDate, to: w.endDate, unit: bpm)
            .map { HRSample(time: $0.time, bpm: $0.value, source: .appleHealth) }
        let recovery = try? await samples(.heartRateRecoveryOneMinute, from: w.endDate.addingTimeInterval(-60),
                                          to: w.endDate.addingTimeInterval(20 * 60), unit: bpm).first?.value
        let effort = await effortScore(for: w)
        let route = (try? await route(for: w)) ?? []
        var metrics: [MetricSample] = []
        if kind.isRun {
            // Series de la carrera para su análisis (doc. 18): potencia, velocidad y dinámica de carrera.
            let series: [(HKQuantityTypeIdentifier, String, HKUnit)] = [
                (.runningPower, "power_w", .watt()), (.runningSpeed, "speed_mps", mps), (.runningStrideLength, "stride_m", .meter()),
                (.runningVerticalOscillation, "vertical_osc_cm", .meterUnit(with: .centi)),
                (.runningGroundContactTime, "ground_contact_ms", .secondUnit(with: .milli)),
            ]
            for (id, key, unit) in series {
                let values = (try? await samples(id, from: w.startDate, to: w.endDate, unit: unit)) ?? []
                metrics += values.map { MetricSample(metric: key, time: $0.time, value: $0.value) }
            }
            // Cadencia (pasos por minuto de cada tramo) y distancia por tramos (ritmo en cinta o sin GPS).
            let stepSamples = (try? await intervalSamples(.stepCount, from: w.startDate, to: w.endDate, unit: .count())) ?? []
            metrics += stepSamples.compactMap { s in
                let minutes = s.end.timeIntervalSince(s.start) / 60
                guard minutes >= 1.0 / 60, s.value > 0 else { return nil }
                let spm = s.value / minutes
                return spm < 260 ? MetricSample(metric: "cadence_spm", time: s.start.addingTimeInterval(minutes * 30), value: spm) : nil
            }
            let distanceSamples = (try? await intervalSamples(.distanceWalkingRunning, from: w.startDate, to: w.endDate, unit: .meter())) ?? []
            metrics += distanceSamples.map { MetricSample(metric: "distance_m", time: $0.end, value: $0.value) }
        }
        let distance = (stat(.distanceWalkingRunning) ?? stat(.distanceCycling))?.sumQuantity()?.doubleValue(for: .meter())
        let session = ActivitySession(
            source: .appleHealth, sourceRecordID: rid, kind: kind, name: nil, start: w.startDate, end: w.endDate, utcOffsetSeconds: offset,
            avgHR: stat(.heartRate)?.averageQuantity()?.doubleValue(for: bpm),
            maxHR: stat(.heartRate)?.maximumQuantity()?.doubleValue(for: bpm),
            caloriesKcal: stat(.activeEnergyBurned)?.sumQuantity()?.doubleValue(for: .kilocalorie()),
            distanceM: distance, steps: steps.map { Int($0) },
            elevationGainM: (w.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?.doubleValue(for: .meter()),
            hasRoute: !route.isEmpty, dynamics: dynamics.isEmpty ? nil : dynamics, hrRecovery1Min: recovery,
            effortScore: effort)
        return WorkoutDetails(session: session, heartRate: heartRate, route: route, metrics: metrics,
                              detail: Self.detail(for: w, activityID: session.id, indoor: indoor))
    }

    /// Pausas, vueltas, segmentos, intervalos, meteo y desnivel negativo del entreno (doc. 18).
    static func detail(for w: HKWorkout, activityID: String, indoor: Bool) -> ActivityDetail {
        var d = ActivityDetail(activityID: activityID, indoor: indoor)
        let events = (w.workoutEvents ?? []).sorted { $0.dateInterval.start < $1.dateInterval.start }
        var manualPause: Date?
        var autoPause: Date?
        for e in events {
            let interval = e.dateInterval
            switch e.type {
            case .pause: manualPause = manualPause ?? interval.start
            case .resume:
                if let start = manualPause, interval.start > start { d.events.append(WorkoutEvent(kind: .pause, start: start, end: interval.start)) }
                manualPause = nil
            case .motionPaused: autoPause = autoPause ?? interval.start
            case .motionResumed:
                if let start = autoPause, interval.start > start {
                    d.events.append(WorkoutEvent(kind: .pause, start: start, end: interval.start, automatic: true))
                }
                autoPause = nil
            case .lap:
                if interval.duration > 0 { d.events.append(WorkoutEvent(kind: .lap, start: interval.start, end: interval.end)) }
            case .segment:
                if interval.duration > 0 { d.events.append(WorkoutEvent(kind: .segment, start: interval.start, end: interval.end)) }
            case .marker: d.events.append(WorkoutEvent(kind: .marker, start: interval.start, end: interval.start))
            default: break
            }
        }
        // Entrenos por intervalos o de varias partes: cada actividad es un tramo con sus propias estadísticas.
        let activities = w.workoutActivities
        if activities.count > 1 {
            let bpm = HKUnit.count().unitDivided(by: .minute())
            d.laps = activities.map { a in
                let end = a.endDate ?? a.startDate.addingTimeInterval(a.duration)
                let distance = a.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter())
                let hr = a.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: bpm)
                let kcal = a.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
                return SourceSplit(start: a.startDate, end: end, kind: "interval", distanceM: distance, activeSeconds: a.duration,
                                   avgHR: hr, caloriesKcal: kcal)
            }
        }
        let meta = w.metadata ?? [:]
        // Solo se convierte si la unidad es compatible: con una incompatible, HealthKit cierra la app.
        func value(_ key: String, _ unit: HKUnit) -> Double? {
            guard let q = meta[key] as? HKQuantity, q.is(compatibleWith: unit) else { return nil }
            return q.doubleValue(for: unit)
        }
        var weather = WeatherInfo()
        weather.temperatureC = value(HKMetadataKeyWeatherTemperature, .degreeCelsius())
        weather.humidityPct = value(HKMetadataKeyWeatherHumidity, .percent()).map { $0 <= 1.5 ? $0 * 100 : $0 }
        weather.condition = (meta[HKMetadataKeyWeatherCondition] as? NSNumber)
            .flatMap { HKWeatherCondition(rawValue: $0.intValue) }.flatMap(Self.conditionName)
        if !weather.isEmpty { d.weather = weather }
        d.elevationLossM = value(HKMetadataKeyElevationDescended, .meter())
        d.avgMETs = value(HKMetadataKeyAverageMETs,
                          HKUnit.kilocalorie().unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .hour())))
        let paused = d.events.filter { $0.kind == .pause }.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }
        d.activeSeconds = max(0, w.duration - paused)
        return d
    }

    static func conditionName(_ c: HKWeatherCondition) -> String? {
        switch c {
        case .clear, .fair: return "Despejado"
        case .partlyCloudy, .mostlyCloudy: return "Nubes y claros"
        case .cloudy: return "Nublado"
        case .foggy, .haze: return "Niebla"
        case .windy, .blustery: return "Viento"
        case .smoky, .dust: return "Calima"
        case .snow: return "Nieve"
        case .mixedRainAndSnow, .mixedSnowAndSleet, .mixedRainAndSleet, .mixedRainAndHail, .sleet, .freezingDrizzle, .freezingRain:
            return "Aguanieve"
        case .hail: return "Granizo"
        case .drizzle: return "Llovizna"
        case .showers, .scatteredShowers: return "Chubascos"
        case .thunderstorms: return "Tormenta"
        case .tropicalStorm, .hurricane, .tornado: return "Temporal"
        default: return nil
        }
    }

    /// Muestras de un tipo en un intervalo, solo del Apple Watch.
    func samples(_ id: HKQuantityTypeIdentifier, from: Date, to: Date, unit: HKUnit) async throws -> [(time: Date, value: Double)] {
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: [])
        let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(id), predicate: predicate)],
                                                 sortDescriptors: [SortDescriptor(\.startDate)], limit: 20_000)
        let results = try await descriptor.result(for: store)
        return results.filter(Self.accepts).map { (time: $0.startDate, value: $0.quantity.doubleValue(for: unit)) }
    }

    /// Muestras con su tramo (inicio y fin), solo del Apple Watch: pasos y distancia.
    func intervalSamples(_ id: HKQuantityTypeIdentifier, from: Date, to: Date, unit: HKUnit) async throws
        -> [(start: Date, end: Date, value: Double)] {
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: [])
        let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(id), predicate: predicate)],
                                                 sortDescriptors: [SortDescriptor(\.startDate)], limit: 20_000)
        let results = try await descriptor.result(for: store)
        return results.filter(Self.accepts).map { (start: $0.startDate, end: $0.endDate, value: $0.quantity.doubleValue(for: unit)) }
    }

    /// Esfuerzo del entrenamiento (valorado por ti en el reloj o estimado por Apple), escala 1–10.
    func effortScore(for w: HKWorkout) async -> Double? {
        let unit = HKUnit.appleEffortScore()
        for id in [HKQuantityTypeIdentifier.workoutEffortScore, .estimatedWorkoutEffortScore] {
            if let value = try? await samples(id, from: w.startDate.addingTimeInterval(-60), to: w.endDate.addingTimeInterval(3600), unit: unit).last?.value {
                return value
            }
        }
        return nil
    }

    func route(for w: HKWorkout) async throws -> [RoutePoint] {
        let store = self.store
        let routes: [HKWorkoutRoute] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKSeriesType.workoutRoute(), predicate: HKQuery.predicateForObjects(from: w),
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: (samples as? [HKWorkoutRoute]) ?? []) }
            }
            store.execute(query)
        }
        var points: [RoutePoint] = []
        for route in routes {
            let box = LocationBox()
            let locations: [CLLocation] = try await withCheckedThrowingContinuation { continuation in
                let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                    if let error {
                        if !box.finished { box.finished = true; continuation.resume(throwing: error) }
                        return
                    }
                    box.items += locations ?? []
                    if done && !box.finished {
                        box.finished = true
                        continuation.resume(returning: box.items)
                    }
                }
                store.execute(query)
            }
            points += locations.map {
                RoutePoint(time: $0.timestamp, latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude, altitude: $0.altitude,
                           speed: $0.speed >= 0 ? $0.speed : nil, horizontalAccuracy: $0.horizontalAccuracy)
            }
        }
        return points.sorted { $0.time < $1.time }
    }

    final class LocationBox: @unchecked Sendable {
        var items: [CLLocation] = []
        var finished = false
    }

    static func kind(_ t: HKWorkoutActivityType, indoor: Bool) -> ActivityKind {
        switch t {
        case .running: return indoor ? .treadmill : .running
        case .walking: return .walking
        case .hiking: return .hiking
        case .cycling: return indoor ? .indoorCycling : .cycling
        case .swimming: return .swimming
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining, .crossTraining: return .strength
        case .highIntensityIntervalTraining, .mixedCardio: return .hiit
        case .elliptical, .stairClimbing, .stairs, .stepTraining: return .elliptical
        case .rowing, .paddleSports: return .rowing
        case .yoga, .mindAndBody, .flexibility: return .yoga
        case .pilates, .barre: return .pilates
        case .cardioDance, .socialDance: return .dance
        case .soccer, .tennis, .basketball, .volleyball, .handball, .squash, .badminton, .rugby, .hockey, .tableTennis, .golf,
             .americanFootball, .baseball, .boxing, .kickboxing, .martialArts, .racquetball, .cricket, .pickleball:
            return .sports
        default: return .other
        }
    }

    // MARK: Entrega en segundo plano

    /// Cuando el Watch guarda un entrenamiento, iOS despierta la app para importarlo (RF-SYN-11).
    func startBackgroundDelivery(onUpdate: @escaping @Sendable () async -> Void) {
        let type = HKObjectType.workoutType()
        store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
        let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
            guard error == nil else { completion(); return }
            Task {
                await onUpdate()
                completion()
            }
        }
        store.execute(query)
    }
}
