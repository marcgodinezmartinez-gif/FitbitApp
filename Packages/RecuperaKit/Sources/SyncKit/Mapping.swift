import Foundation
import HealthAPI
import MetricsKit
import Store

/// Traduce los recursos de la Google Health API al modelo interno (doc. 09).
public enum GoogleMapping {
    static func offset(_ s: String?) -> Int { Int(GoogleTime.seconds(s) ?? 0) }

    static func localDate(_ d: APIDate?) -> LocalDate? {
        guard let d, let y = d.year, let m = d.month, let day = d.day, y > 0, m > 0, day > 0 else { return nil }
        return LocalDate(year: y, month: m, day: day)
    }

    /// Solo se aceptan datos que no vengan de HealthKit (ALG-FUS-08).
    static func accepted(_ p: APIDataPoint) -> Bool { Fusion.acceptsGooglePlatform(p.dataSource?.platform) }

    public static func hrMinutes(_ points: [RollupDataPoint]) -> [HRMinute] {
        points.compactMap { p in
            guard let start = GoogleTime.date(p.startTime), let avg = p.heartRate?.beatsPerMinuteAvg, avg > 0 else { return nil }
            return HRMinute(minute: start.minuteEpoch, bpmAvg: avg, bpmMin: p.heartRate?.beatsPerMinuteMin,
                            bpmMax: p.heartRate?.beatsPerMinuteMax, samples: 0, source: .googleHealth)
        }
    }

    public static func activityMinutes(steps: [RollupDataPoint], distance: [RollupDataPoint]) -> [ActivityMinute] {
        var byMinute: [Int: ActivityMinute] = [:]
        for p in steps {
            guard let start = GoogleTime.date(p.startTime) else { continue }
            let m = start.minuteEpoch
            byMinute[m, default: ActivityMinute(minute: m, steps: 0, source: .googleHealth)].steps = Int(p.steps?.countSum?.value ?? 0)
        }
        for p in distance {
            guard let start = GoogleTime.date(p.startTime) else { continue }
            let m = start.minuteEpoch
            byMinute[m, default: ActivityMinute(minute: m, steps: 0, source: .googleHealth)].distanceM = Double(p.distance?.millimetersSum?.value ?? 0) / 1000
        }
        return byMinute.values.filter { $0.steps > 0 || $0.distanceM > 0 }.sorted { $0.minute < $1.minute }
    }

    static func stage(_ type: String?) -> SleepStageKind? {
        switch type {
        case "AWAKE", "RESTLESS": return .wake
        case "LIGHT": return .light
        case "DEEP": return .deep
        case "REM": return .rem
        case "ASLEEP": return .asleep
        default: return nil
        }
    }

    public static func sleepSessions(_ points: [APIDataPoint]) -> [SleepSession] {
        points.filter(accepted).compactMap { p in
            guard let s = p.sleep, let start = GoogleTime.date(s.interval?.startTime), let end = GoogleTime.date(s.interval?.endTime) else { return nil }
            let off = offset(s.interval?.startUtcOffset ?? s.interval?.endUtcOffset)
            let stages: [SleepStageSegment] = (s.stages ?? []).compactMap { st in
                guard let k = stage(st.type), let a = GoogleTime.date(st.startTime), let b = GoogleTime.date(st.endTime), b > a else { return nil }
                return SleepStageSegment(start: a, end: b, stage: k)
            }
            let id = "gh:" + (p.identifier ?? s.metadata?.externalId ?? "\(Int(start.timeIntervalSince1970))")
            return SleepSession(id: id, source: .googleHealth, start: start, end: end, utcOffsetSeconds: off,
                                isMainFromSource: s.metadata?.mainSleep, isNapFromSource: s.metadata?.nap, stages: stages,
                                minutesAsleepFromSource: s.summary?.minutesAsleep.map { Int($0.value) },
                                minutesAwakeFromSource: s.summary?.minutesAwake.map { Int($0.value) },
                                latencyFromSource: s.summary?.minutesToFallAsleep.map { Int($0.value) })
        }
    }

    public static func activityKind(_ type: String?) -> ActivityKind {
        switch type ?? "" {
        case "RUNNING", "INCLINE_RUN", "WATER_JOGGING": return .running
        case "TRAIL_RUN": return .trailRunning
        case "TREADMILL": return .treadmill
        case "WALKING", "POWER_WALKING", "TREADMILL_WALK", "NORDIC_WALKING", "INCLINE_WALK", "STROLLER_WALK", "WALK_WITH_WEIGHTS", "RUCKING":
            return .walking
        case "HIKING", "BACKPACKING", "SNOWSHOEING": return .hiking
        case "BIKING", "OUTDOOR_BIKE", "MOUNTAIN_BIKE", "ELECTRIC_BIKE", "HAND_CYCLING": return .cycling
        case "SPINNING", "STATIONARY_BIKE", "ASSAULT_BIKE": return .indoorCycling
        case "SWIMMING", "SWIMMING_OPEN_WATER", "SWIMMING_POOL": return .swimming
        case "STRENGTH_TRAINING", "WEIGHTLIFTING", "WEIGHTS", "FREE_WEIGHTS", "POWERLIFTING", "WEIGHT_MACHINES",
             "FUNCTIONAL_STRENGTH_TRAINING", "BODY_WEIGHT", "CALISTHENICS", "RESISTANCE_BANDS", "CROSSFIT", "TRX", "CORE_TRAINING":
            return .strength
        case "HIIT", "TABATA_WORKOUT", "INTERVAL_WORKOUT", "CIRCUIT_TRAINING", "BOOTCAMP": return .hiit
        case "ELLIPTICAL", "STAIRCLIMBER", "STEP_TRAINING": return .elliptical
        case "ROWING", "ROWING_MACHINE", "CANOEING", "KAYAKING": return .rowing
        case "YOGA", "YOGA_BIKRAM", "YOGA_HATHA", "YOGA_POWER", "YOGA_VINYASA": return .yoga
        case "PILATES", "BARRE_CLASS": return .pilates
        case "DANCING", "ZUMBA", "BALLET", "BALLROOM_DANCE", "HIP_HOP", "JAZZ_DANCE", "MODERN_DANCE", "TANGO", "BREAKDANCING": return .dance
        case "SOCCER", "TENNIS", "PADEL", "BASKETBALL", "VOLLEYBALL", "HANDBALL", "SQUASH", "BADMINTON", "RUGBY", "HOCKEY",
             "TABLE_TENNIS", "PICKELBALL", "GOLF", "SPORT", "RACKET_SPORTS", "MARTIAL_ARTS", "BOXING", "KICKBOXING":
            return .sports
        default: return .other
        }
    }

    public static func activities(_ points: [APIDataPoint]) -> [ActivitySession] {
        points.filter(accepted).compactMap { p in
            guard let e = p.exercise, let start = GoogleTime.date(e.interval?.startTime), let end = GoogleTime.date(e.interval?.endTime) else { return nil }
            let m = e.metricsSummary
            let rid = p.identifier ?? "ex-\(Int(start.timeIntervalSince1970))"
            return ActivitySession(source: .googleHealth, sourceRecordID: rid, kind: activityKind(e.exerciseType), name: e.displayName,
                                   start: start, end: end, utcOffsetSeconds: offset(e.interval?.startUtcOffset),
                                   avgHR: m?.averageHeartRateBeatsPerMinute.map { Double($0.value) }, caloriesKcal: m?.caloriesKcal,
                                   distanceM: m?.distanceMillimeters.map { $0 / 1000 }, steps: m?.steps.map { Int($0.value) },
                                   elevationGainM: m?.elevationGainMillimeters.map { $0 / 1000 }, hasRoute: e.exerciseMetadata?.hasGps ?? false,
                                   isManual: p.dataSource?.recordingMethod == "MANUAL", notes: e.notes)
        }
    }

    /// Lo que da la Fitbit de cada entreno además del resumen: parciales por km, vueltas, pausas, dinámica de carrera,
    /// zonas de FC y VO₂ máx. de la carrera (doc. 18).
    public static func activityDetails(_ points: [APIDataPoint]) -> [ActivityDetail] {
        points.filter(accepted).compactMap { p in
            guard let e = p.exercise, let start = GoogleTime.date(e.interval?.startTime) else { return nil }
            let rid = p.identifier ?? "ex-\(Int(start.timeIntervalSince1970))"
            let m = e.metricsSummary
            var detail = ActivityDetail(activityID: "\(DataSourceKind.googleHealth.rawValue):\(rid)")
            detail.splits = (e.splits ?? []).compactMap { split($0, kind: "km") }
            detail.laps = (e.splitSummaries ?? []).compactMap { split($0, kind: ($0.splitType ?? "manual").lowercased()) }
            detail.events = pauses(e.exerciseEvents ?? [])
            detail.activeSeconds = GoogleTime.seconds(e.activeDuration)
            detail.activeZoneMinutes = m?.activeZoneMinutes.map { Double($0.value) }
            if let z = m?.heartRateZoneDurations {
                var zones: [String: Double] = [:]
                for (key, value) in [("light", z.lightTime), ("moderate", z.moderateTime), ("vigorous", z.vigorousTime), ("peak", z.peakTime)] {
                    if let secs = GoogleTime.seconds(value) { zones[key] = secs }
                }
                if !zones.isEmpty { detail.zoneSeconds = zones }
            }
            if let mob = m?.mobilityMetrics {
                let dyn = RunningDynamics(avgStrideM: mob.avgStrideLengthMillimeters.map { Double($0.value) / 1000 },
                                          avgVerticalOscillationCm: mob.avgVerticalOscillationMillimeters.map { Double($0.value) / 10 },
                                          avgGroundContactMs: GoogleTime.seconds(mob.avgGroundContactTimeDuration).map { $0 * 1000 },
                                          avgCadenceSpm: mob.avgCadenceStepsPerMinute)
                if !dyn.isEmpty { detail.mobility = dyn }
                detail.verticalRatioPct = mob.avgVerticalRatio
            }
            detail.vo2max = m?.runVo2Max.flatMap { $0 > 0 ? $0 : nil }
            return detail
        }
    }

    static func split(_ s: ExercisePoint.Split, kind: String) -> SourceSplit? {
        guard let start = GoogleTime.date(s.startTime), let end = GoogleTime.date(s.endTime) else { return nil }
        let m = s.metricsSummary
        return SourceSplit(start: start, end: end, kind: kind, distanceM: m?.distanceMillimeters.map { $0 / 1000 },
                           activeSeconds: GoogleTime.seconds(s.activeDuration),
                           avgHR: m?.averageHeartRateBeatsPerMinute.map { Double($0.value) },
                           avgCadence: m?.mobilityMetrics?.avgCadenceStepsPerMinute,
                           elevationGainM: m?.elevationGainMillimeters.map { $0 / 1000 }, caloriesKcal: m?.caloriesKcal,
                           steps: m?.steps.map { Int($0.value) })
    }

    /// Empareja cada pausa con la reanudación siguiente.
    static func pauses(_ events: [ExercisePoint.Event]) -> [WorkoutEvent] {
        let sorted = events.compactMap { e -> (Date, String)? in
            guard let t = GoogleTime.date(e.eventTime), let type = e.exerciseEventType else { return nil }
            return (t, type)
        }.sorted { $0.0 < $1.0 }
        var out: [WorkoutEvent] = []
        var open: (Date, Bool)?
        for (t, type) in sorted {
            switch type {
            case "PAUSE", "AUTO_PAUSE":
                if open == nil { open = (t, type == "AUTO_PAUSE") }
            case "RESUME", "AUTO_RESUME", "STOP":
                if let (start, auto) = open, t > start { out.append(WorkoutEvent(kind: .pause, start: start, end: t, automatic: auto)) }
                open = nil
            default: break
            }
        }
        return out
    }

    public static func hrSamples(_ points: [APIDataPoint]) -> [HRSample] {
        points.filter(accepted).compactMap { p in
            guard let h = p.heartRate, let t = GoogleTime.date(h.sampleTime?.physicalTime), let bpm = h.beatsPerMinute?.value else { return nil }
            return HRSample(time: t, bpm: Double(bpm), source: .googleHealth)
        }
    }

    /// Vitales diarios; si hay varios puntos para una fecha se prefiere el de la plataforma FITBIT.
    public static func vitals(hrv: [APIDataPoint], rhr: [APIDataPoint], spo2: [APIDataPoint], rr: [APIDataPoint],
                              temp: [APIDataPoint]) -> [NightlyVitals] {
        var byDate: [LocalDate: NightlyVitals] = [:]
        func upd(_ date: LocalDate?, _ f: (inout NightlyVitals) -> Void) {
            guard let date else { return }
            var v = byDate[date] ?? NightlyVitals(date: date)
            f(&v)
            byDate[date] = v
        }
        for p in preferFitbit(hrv) { let x = p.dailyHeartRateVariability
            upd(localDate(x?.date)) {
                $0.hrvRmssdAvg = x?.averageHeartRateVariabilityMilliseconds
                $0.hrvRmssdDeep = x?.deepSleepRootMeanSquareOfSuccessiveDifferencesMilliseconds
                $0.nremHR = x?.nonRemHeartRateBeatsPerMinute.map { Double($0.value) }
            }
        }
        for p in preferFitbit(rhr) { let x = p.dailyRestingHeartRate
            upd(localDate(x?.date)) { $0.restingHR = x?.beatsPerMinute.map { Double($0.value) } }
        }
        for p in preferFitbit(spo2) { let x = p.dailyOxygenSaturation; upd(localDate(x?.date)) { $0.spo2Avg = x?.averagePercentage } }
        for p in preferFitbit(rr) { let x = p.dailyRespiratoryRate; upd(localDate(x?.date)) { $0.respiratoryRate = x?.breathsPerMinute } }
        for p in preferFitbit(temp) {
            let x = p.dailySleepTemperatureDerivations
            upd(localDate(x?.date)) { $0.skinTempC = x?.nightlyTemperatureCelsius }
        }
        return byDate.values.sorted { $0.date < $1.date }
    }

    /// Ordena para que, en fechas repetidas, el último (el que prevalece) sea el de la Fitbit.
    static func preferFitbit(_ points: [APIDataPoint]) -> [APIDataPoint] {
        let ok = points.filter(accepted)
        return ok.filter { $0.dataSource?.platform != "FITBIT" } + ok.filter { $0.dataSource?.platform == "FITBIT" }
    }

    public static func vo2(_ points: [APIDataPoint]) -> [VO2MaxValue] {
        points.filter(accepted).compactMap { p in
            guard let x = p.dailyVo2Max, let d = localDate(x.date), let v = x.vo2Max, v > 0 else { return nil }
            return VO2MaxValue(date: d, value: v, source: .googleHealth)
        }
    }

    public static func dailyTotals(steps: [RollupDataPoint], distance: [RollupDataPoint], calories: [RollupDataPoint]) -> [LocalDate: DailySourceTotals] {
        var out: [LocalDate: DailySourceTotals] = [:]
        func date(_ p: RollupDataPoint) -> LocalDate? { localDate(p.civilStartTime?.date) }
        for p in steps { if let d = date(p) { out[d, default: DailySourceTotals()].steps = Int(p.steps?.countSum?.value ?? 0) } }
        for p in distance { if let d = date(p) { out[d, default: DailySourceTotals()].distanceM = Double(p.distance?.millimetersSum?.value ?? 0) / 1000 } }
        for p in calories { if let d = date(p) { out[d, default: DailySourceTotals()].caloriesKcal = p.totalCalories?.kcalSum } }
        return out
    }
    // MARK: Datos ampliados (doc. 03 §4)

    /// La noche a la que pertenece una muestra: la que termina el día local en que cae la muestra más 9 horas
    /// (lo dormido desde las 15:00 cuenta para el día siguiente).
    static func nightDate(_ t: SampleTime?) -> (date: LocalDate, time: Date)? {
        guard let time = GoogleTime.date(t?.physicalTime) else { return nil }
        return (LocalDate(time.addingTimeInterval(9 * 3600), utcOffsetSeconds: offset(t?.utcOffset)), time)
    }

    /// Como mucho `limit` muestras por noche, repartidas (la curva se ve igual y ocupa poco).
    static func thinned(_ samples: [DayExtras.Sample], limit: Int = 400) -> [DayExtras.Sample] {
        let sorted = samples.sorted { $0.t < $1.t }
        guard sorted.count > limit else { return sorted }
        let step = Double(sorted.count) / Double(limit)
        return (0..<limit).map { sorted[Int(Double($0) * step)] }
    }

    /// Junta por día todo lo que la pulsera mide además de las puntuaciones. `rollups` son totales diarios (`dailyRollUp`).
    public static func dayExtras(hrv: [APIDataPoint] = [], spo2: [APIDataPoint] = [], temp: [APIDataPoint] = [],
                                 respSummary: [APIDataPoint] = [], hrvSamples: [APIDataPoint] = [], spo2Samples: [APIDataPoint] = [],
                                 zones: [APIDataPoint] = [], rollups: [RollupDataPoint] = []) -> [DayExtras] {
        var byDate: [LocalDate: DayExtras] = [:]
        func upd(_ date: LocalDate?, _ f: (inout DayExtras) -> Void) {
            guard let date else { return }
            var x = byDate[date] ?? DayExtras(date: date)
            f(&x)
            byDate[date] = x
        }
        func minutes(_ duration: String?) -> Double? { GoogleTime.seconds(duration).map { $0 / 60 } }

        for p in preferFitbit(hrv) { let x = p.dailyHeartRateVariability
            if let e = x?.entropy { upd(localDate(x?.date)) { $0.hrvEntropy = e } }
        }
        for p in preferFitbit(spo2) { let x = p.dailyOxygenSaturation
            guard x?.lowerBoundPercentage != nil || x?.upperBoundPercentage != nil || x?.standardDeviationPercentage != nil else { continue }
            upd(localDate(x?.date)) {
                $0.spo2Lower = x?.lowerBoundPercentage
                $0.spo2Upper = x?.upperBoundPercentage
                $0.spo2Stddev = x?.standardDeviationPercentage
            }
        }
        for p in preferFitbit(temp) { let x = p.dailySleepTemperatureDerivations
            guard x?.baselineTemperatureCelsius != nil || x?.relativeNightlyStddev30dCelsius != nil else { continue }
            upd(localDate(x?.date)) {
                $0.tempBaselineC = x?.baselineTemperatureCelsius
                $0.tempStddevC = x?.relativeNightlyStddev30dCelsius
            }
        }
        for p in preferFitbit(respSummary) {
            guard let x = p.respiratoryRateSleepSummary, let night = nightDate(x.sampleTime) else { continue }
            func rate(_ s: RespiratorySummaryPoint.Stats?) -> Double? { s?.breathsPerMinute.flatMap { $0 > 0 ? $0 : nil } }
            guard rate(x.lightSleepStats) != nil || rate(x.deepSleepStats) != nil || rate(x.remSleepStats) != nil else { continue }
            upd(night.date) {
                $0.respLight = rate(x.lightSleepStats)
                $0.respDeep = rate(x.deepSleepStats)
                $0.respRem = rate(x.remSleepStats)
            }
        }
        var hrvByNight: [LocalDate: [DayExtras.Sample]] = [:]
        for p in hrvSamples where accepted(p) {
            guard let x = p.heartRateVariability, let night = nightDate(x.sampleTime),
                  let v = x.rootMeanSquareOfSuccessiveDifferencesMilliseconds, v > 0 else { continue }
            hrvByNight[night.date, default: []].append(DayExtras.Sample(t: night.time, v: v))
        }
        for (d, list) in hrvByNight { upd(d) { $0.hrvSamples = thinned(list) } }
        var spo2ByNight: [LocalDate: [DayExtras.Sample]] = [:]
        for p in spo2Samples where accepted(p) {
            guard let x = p.oxygenSaturation, let night = nightDate(x.sampleTime), let v = x.percentage, v > 50 else { continue }
            spo2ByNight[night.date, default: []].append(DayExtras.Sample(t: night.time, v: v))
        }
        for (d, list) in spo2ByNight { upd(d) { $0.spo2Samples = thinned(list) } }
        for p in preferFitbit(zones) {
            guard let x = p.dailyHeartRateZones, let list = x.heartRateZones, !list.isEmpty else { continue }
            let mapped = list.compactMap { z -> DayExtras.Zone? in
                guard let name = z.heartRateZoneType, let lo = z.minBeatsPerMinute?.value else { return nil }
                return DayExtras.Zone(name: name, min: Int(lo), max: Int(z.maxBeatsPerMinute?.value ?? 220))
            }
            if !mapped.isEmpty { upd(localDate(x.date)) { $0.hrZones = mapped.sorted { $0.min < $1.min } } }
        }

        for p in rollups {
            let date = localDate(p.civilStartTime?.date)
            if let a = p.activeMinutes?.activeMinutesRollupByActivityLevel {
                func level(_ name: String) -> Int? { a.first { $0.activityLevel == name }?.activeMinutesSum.map { Int($0.value) } }
                upd(date) {
                    $0.activeMinLight = level("LIGHT") ?? 0
                    $0.activeMinModerate = level("MODERATE") ?? 0
                    $0.activeMinVigorous = level("VIGOROUS") ?? 0
                }
            }
            if let z = p.activeZoneMinutes {
                upd(date) {
                    $0.azmFatBurn = Int(z.sumInFatBurnHeartZone?.value ?? 0)
                    $0.azmCardio = Int(z.sumInCardioHeartZone?.value ?? 0)
                    $0.azmPeak = Int(z.sumInPeakHeartZone?.value ?? 0)
                }
            }
            if let z = p.timeInHeartRateZone?.timeInHeartRateZones {
                var out: [String: Double] = [:]
                for item in z { if let k = item.heartRateZone, let m = minutes(item.duration) { out[k, default: 0] += m } }
                if !out.isEmpty { upd(date) { $0.zoneMinutes = out } }
            }
            if let z = p.caloriesInHeartRateZone?.caloriesInHeartRateZones {
                var out: [String: Double] = [:]
                for item in z { if let k = item.heartRateZone, let kcal = item.kcal { out[k, default: 0] += kcal } }
                if !out.isEmpty { upd(date) { $0.zoneKcal = out } }
            }
            if let m = minutes(p.sedentaryPeriod?.durationSum) { upd(date) { $0.sedentaryMin = m } }
            if let l = p.activityLevel?.activityLevelRollupsByActivityLevelType {
                var out: [String: Double] = [:]
                for item in l { if let k = item.activityLevelType, let m = minutes(item.totalDuration) { out[k, default: 0] += m } }
                if !out.isEmpty { upd(date) { $0.levelMinutes = out } }
            }
            if let kcal = p.activeEnergyBurned?.kcalSum { upd(date) { $0.activeKcal = kcal } }
            if let f = p.floors?.countSum?.value, f > 0 { upd(date) { $0.floors = Int(f) } }
            if let g = p.altitude?.gainMillimetersSum?.value, g > 0 { upd(date) { $0.elevationGainM = Double(g) / 1000 } }
            if let hr = p.heartRate, let avg = hr.beatsPerMinuteAvg, avg > 0 {
                upd(date) {
                    $0.hrAvg = avg
                    $0.hrMin = hr.beatsPerMinuteMin
                    $0.hrMax = hr.beatsPerMinuteMax
                }
            }
        }
        return byDate.values.sorted { $0.date < $1.date }
    }
}
