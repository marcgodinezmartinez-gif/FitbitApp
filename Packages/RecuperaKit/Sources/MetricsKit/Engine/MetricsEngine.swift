import Foundation

/// Totales diarios de la Fitbit tal como los da Google (`dailyRollUp`).
public struct DailySourceTotals: Hashable, Codable, Sendable {
    public var steps: Int?
    public var distanceM: Double?
    public var caloriesKcal: Double?

    public init(steps: Int? = nil, distanceM: Double? = nil, caloriesKcal: Double? = nil) {
        self.steps = steps
        self.distanceM = distanceM
        self.caloriesKcal = caloriesKcal
    }
}

/// Todo lo que necesita el motor. Se construye desde la BD local (SyncKit).
public struct MetricsInput: Sendable {
    public var profile: UserProfile
    public var params: AlgorithmParams
    public var now: Date
    public var utcOffsetSeconds: Int
    public var sleepSessions: [SleepSession]
    public var vitals: [NightlyVitals]
    public var hrFitbit: [HRMinute]
    public var hrWatch: [HRMinute]
    public var fitbitMinutes: [ActivityMinute]
    public var activities: [ActivitySession]
    public var dailyFitbitTotals: [LocalDate: DailySourceTotals]
    public var vo2max: [VO2MaxValue]
    public var journal: [JournalAnswer]
    public var strainModes: [LocalDate: StrainMode]
    public var workoutSamples: [String: [HRSample]]

    public init(profile: UserProfile, params: AlgorithmParams = .default, now: Date, utcOffsetSeconds: Int,
                sleepSessions: [SleepSession] = [], vitals: [NightlyVitals] = [], hrFitbit: [HRMinute] = [],
                hrWatch: [HRMinute] = [], fitbitMinutes: [ActivityMinute] = [], activities: [ActivitySession] = [],
                dailyFitbitTotals: [LocalDate: DailySourceTotals] = [:], vo2max: [VO2MaxValue] = [],
                journal: [JournalAnswer] = [], strainModes: [LocalDate: StrainMode] = [:],
                workoutSamples: [String: [HRSample]] = [:]) {
        self.profile = profile
        self.params = params
        self.now = now
        self.utcOffsetSeconds = utcOffsetSeconds
        self.sleepSessions = sleepSessions
        self.vitals = vitals
        self.hrFitbit = hrFitbit
        self.hrWatch = hrWatch
        self.fitbitMinutes = fitbitMinutes
        self.activities = activities
        self.dailyFitbitTotals = dailyFitbitTotals
        self.vo2max = vo2max
        self.journal = journal
        self.strainModes = strainModes
        self.workoutSamples = workoutSamples
    }
}

public struct ActivityMetrics: Hashable, Codable, Sendable, Identifiable {
    public var activity: FusedActivity
    public var strain: StrainResult
    public var id: String { activity.id }
}

public struct CycleMetrics: Hashable, Codable, Sendable, Identifiable {
    public var cycle: Cycle
    public var sleepSession: SleepSession?
    public var sleep: SleepResult?
    public var naps: [SleepSession]
    public var vitals: NightlyVitals?
    public var night: NightValues?
    public var recovery: RecoveryResult
    public var strain: StrainResult
    public var target: TargetBand?
    public var strainMode: StrainMode
    public var stress: StressDay
    public var health: HealthCheck?
    public var activities: [ActivityMetrics]
    public var totals: DailyTotals?
    public var zones: HRZones
    public var isOpen: Bool

    public var id: String { cycle.id }
    public var date: LocalDate { cycle.date }
}

public struct MetricsOutput: Sendable {
    public var algorithmVersion: String
    public var cycles: [CycleMetrics]
    public var fusedHR: [FusedHRMinute]
    public var fusedActivities: [FusedActivity]
    public var nights: [NightValues]
    public var hrMax: Double
    public var observedHRMax: Double?
    public var acuteLoad: Double?
    public var chronicLoad: Double?
    public var habitImpacts: [HabitImpact]
    public var physioAge: PhysioAgeResult?
    public var primaryVO2: VO2MaxValue?
    public var agreementSummary: HRAgreement?
    /// Necesidad de sueño estimada para esta noche (según la carga y la deuda actuales).
    public var tonightNeed: SleepNeedBreakdown?
    public var usualEfficiency: Double?
    public var usualLatency: Double?

    public var current: CycleMetrics? { cycles.last }
    public func cycle(on date: LocalDate) -> CycleMetrics? { cycles.last { $0.date == date } }
}

public enum MetricsEngine {
    public static func run(_ input: MetricsInput) -> MetricsOutput {
        let p = input.params
        let profile = input.profile

        // Sueño principal y siestas (ALG-SUE-00).
        let mainIDs = SleepClassifier.mainSessions(input.sleepSessions)
        let mainSleeps = input.sleepSessions.filter { mainIDs.contains($0.id) }.sorted { $0.end < $1.end }
        let naps = SleepClassifier.naps(input.sleepSessions, mainIDs: mainIDs)

        // Fusión (ALG-FUS).
        var fused = Fusion.fuseActivities(input.activities, params: p)
        let watchRanges = input.activities.filter { $0.source == .appleHealth }.map(\.range)
        let fusedHR = Fusion.fuseHeartRate(fitbit: input.hrFitbit, watch: input.hrWatch, watchWorkouts: watchRanges, params: p)
        let hr = Dictionary(fusedHR.map { ($0.minute, $0.bpm) }, uniquingKeysWith: { a, _ in a })
        let hrSourceByMinute = Dictionary(fusedHR.map { ($0.minute, $0.source) }, uniquingKeysWith: { a, _ in a })
        let fitbitHR = Dictionary(input.hrFitbit.map { ($0.minute, $0.bpmAvg) }, uniquingKeysWith: { a, _ in a })
        let watchHR = Dictionary(input.hrWatch.map { ($0.minute, $0.bpmAvg) }, uniquingKeysWith: { a, _ in a })
        let fitbitMinutes = Dictionary(input.fitbitMinutes.map { ($0.minute, $0) }, uniquingKeysWith: { a, _ in a })
        let steps = fitbitMinutes.mapValues(\.steps)
        for i in fused.indices where fused[i].watchMember != nil && fused[i].fitbitMember != nil {
            fused[i].sourcesDisagree = Fusion.sourcesDisagree(fitbit: fitbitHR, watch: watchHR, range: fused[i].range, params: p)
            fused[i].agreement = Fusion.agreement(fitbit: fitbitHR, watch: watchHR, range: fused[i].range)
        }
        for i in fused.indices {
            var counts: [DataSourceKind: Int] = [:]
            for m in Fusion.minuteSet([fused[i].range]) { if let s = hrSourceByMinute[m] { counts[s, default: 0] += 1 } }
            fused[i].hrSource = counts.max { $0.value < $1.value }?.key
        }

        // Noches (ALG-BAS-01).
        let vitalsByDate = Dictionary(input.vitals.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        var nights: [NightValues] = []
        for s in mainSleeps {
            let v = vitalsByDate[s.wakeDate]
            let rmssd = v.flatMap { Baselines.nightlyRMSSD(vitals: $0, deepMinutes: s.minutes(in: .deep), params: p) }
            nights.append(NightValues(date: s.wakeDate, lnRmssd: rmssd.map { log($0) }, restingHR: v?.restingHR,
                                      respiratoryRate: v?.respiratoryRate, skinTemp: v?.skinTempC, spo2: v?.spo2Avg,
                                      valid: Validity.isValidNight(sleep: s, vitals: v)))
        }
        let nightByDate = Dictionary(nights.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })

        // Ciclos (ALG-CIC-01).
        let firstDay = (mainSleeps.first?.wakeDate ?? LocalDate(input.now, utcOffsetSeconds: input.utcOffsetSeconds))
        let cycles = CycleBuilder.cycles(mainSleeps: mainSleeps, firstDay: firstDay, now: input.now,
                                         utcOffsetSeconds: input.utcOffsetSeconds)

        // FC máxima (ALG-CAR-06, ALG-FUS-07).
        let today = LocalDate(input.now, utcOffsetSeconds: input.utcOffsetSeconds)
        let hrMax = StrainCalculator.hrMax(profile: profile, on: today)
        let observed = StrainCalculator.observedHRMax(workoutSamples: Array(input.workoutSamples.values))

        // Conjunto de minutos dormidos para el SRI.
        var asleepMinutes = Set<Int>()
        var sleepDays = Set<LocalDate>()
        for s in input.sleepSessions {
            sleepDays.insert(s.wakeDate)
            let segments = s.stages.isEmpty ? [SleepStageSegment(start: s.start, end: s.end, stage: .asleep)] : s.stages
            for seg in segments where seg.stage.isAsleep {
                var m = seg.start.minuteEpoch
                while TimeInterval(m) < seg.end.timeIntervalSince1970 { asleepMinutes.insert(m); m += 60 }
            }
        }
        let sleepRanges = input.sleepSessions.map(\.range)
        let workoutRanges = fused.map(\.range)

        var results: [CycleMetrics] = []
        var debt = 0.0
        var zHistory: [RecoveryHistoryPoint] = []
        var closedStrains: [Double] = []
        var dailyLoads: [Double] = []
        var eligibleHistory: [(day: LocalDate, medians: [Double])] = []
        var sleepResults: [SleepResult] = []

        for (idx, cycle) in cycles.enumerated() {
            let isOpen = cycle.end == nil
            let range = cycle.range(now: input.now)
            let date = cycle.date
            let prev = results.last
            let recentRHR = input.vitals.filter { $0.date <= date && $0.date > date.adding(days: -7) }.compactMap(\.restingHR)
            let restingRef = Stats.mean(recentRHR) ?? 60
            let zones = StrainCalculator.zones(hrMax: hrMax, restingRef: restingRef)

            // Sueño que inicia el ciclo.
            let session = cycle.sleepSessionID.flatMap { id in mainSleeps.first { $0.id == id } }
            var sleepResult: SleepResult?
            if let session {
                let prevNaps = prev.map { $0.naps.reduce(0) { $0 + $1.minutesAsleep } } ?? 0
                let mean28 = Stats.mean(Array(closedStrains.suffix(28)))
                let need = SleepCalculator.need(base: SleepCalculator.baseNeed(profile: profile, date: date, params: p),
                                                previousCycleStrain: prev?.strain.strain, strainMean28: closedStrains.count >= 7 ? mean28 : nil,
                                                currentDebt: debt, napMinutes: prevNaps, params: p)
                let sri = SleepCalculator.sri(asleepMinutes: asleepMinutes, coveredDays: Array(sleepDays), until: date,
                                              utcOffset: session.utcOffsetSeconds)
                debt = SleepCalculator.debt(previous: debt, needWithoutDebt: need.withoutDebtMin, asleep: session.minutesAsleep, params: p)
                sleepResult = SleepCalculator.evaluate(session: session, need: need, debt: debt, consistency: sri, params: p)
                if let r = sleepResult { sleepResults.append(r) }
            }

            // Recuperación.
            let v = vitalsByDate[date]
            let night = session != nil ? nightByDate[date] : nil
            var recovery: RecoveryResult
            if let session, let v {
                let rmssd = Baselines.nightlyRMSSD(vitals: v, deepMinutes: session.minutes(in: .deep), params: p)
                let input = RecoveryInput(date: date, rmssd: rmssd, restingHR: v.restingHR, sleepSufficiency: sleepResult?.sufficiency,
                                          respiratoryRate: v.respiratoryRate, skinTemp: v.skinTempC, spo2: v.spo2Avg,
                                          nightCoverage: Validity.nightCoverage(sleep: session, hr: hr), minutesAsleep: session.minutesAsleep)
                recovery = RecoveryCalculator.compute(input, nights: nights, history: zHistory, params: p)
                if recovery.status == .ok {
                    let z = { (k: RecoveryComponent.Kind) in recovery.components.first { $0.kind == k }?.z ?? 0 }
                    zHistory.append(RecoveryHistoryPoint(date: date, zHRV: z(.hrv), zRHR: z(.restingHR), zSleep: z(.sleep)))
                }
            } else if session == nil {
                recovery = .insufficient(cycle.isFallback ? "No se detectó sueño principal" : "Sin sueño", nights: nights.filter { $0.valid && $0.date < date }.count)
            } else {
                recovery = .insufficient("Aún no han llegado los datos de la noche", nights: nights.filter { $0.valid && $0.date < date }.count)
            }

            // Actividades del ciclo y su carga.
            let cycleActivities = fused.filter { range.contains($0.start) }
            var activityMetrics: [ActivityMetrics] = []
            var extraLoad = 0.0
            for a in cycleActivities {
                let minutes = minutesIn(a.range, hr: hr)
                let s = StrainCalculator.compute(minutes: minutes, zones: zones, sex: profile.sex, params: p)
                if a.kind.isStrength {
                    extraLoad += StrainCalculator.strengthExtraLoad(cardioLoad: s.loadRaw, rpe: a.rpe, minutes: a.durationMinutes, params: p)
                }
                activityMetrics.append(ActivityMetrics(activity: a, strain: s))
            }

            // Carga del ciclo.
            let awakeHours = max(0, range.duration / 3600 - (sleepRanges.filter { $0.intersects(range) }.reduce(0) { $0 + $1.overlap(with: range) } / 3600))
            let strain = StrainCalculator.compute(minutes: minutesIn(range, hr: hr), zones: zones, sex: profile.sex, params: p,
                                                  expectedHours: isOpen ? nil : max(awakeHours, 10), extraLoad: extraLoad)
            let mode = input.strainModes[date] ?? .maintain
            let target = StrainCalculator.target(recovery: recovery.score, recentStrains: closedStrains, mode: mode, params: p)

            // Estrés (ventanas de la vigilia del ciclo).
            let windows = StressCalculator.eligibleWindows(range: range, hr: hr, steps: steps, sleep: sleepRanges,
                                                           workouts: workoutRanges, params: p)
            let recentMedians = eligibleHistory.filter { date.days(since: $0.day) <= p.stress.baselineDays && $0.day < date }
                .flatMap(\.medians)
            let calm = StressCalculator.calmHR(eligibleMedians: recentMedians, params: p)
            let stress = StressCalculator.day(windows: windows, calmHR: calm, hrMax: hrMax, restingRef: restingRef, params: p)
            eligibleHistory.append((date, windows.compactMap(\.median)))

            // Monitor de salud.
            let health = night.flatMap { HealthMonitor.check(date: date, tonight: $0, nights: nights, params: p) }

            // Totales del día (ALG-FUS-04).
            let dayTotals = input.dailyFitbitTotals[date]
            let totals = Fusion.dailyTotals(date: date, fitbitSteps: dayTotals?.steps, fitbitDistanceM: dayTotals?.distanceM,
                                            fitbitCaloriesKcal: dayTotals?.caloriesKcal, fitbitMinutes: fitbitMinutes,
                                            fitbitHR: fitbitHR, activities: cycleActivities, params: p)

            let cycleNaps = naps.filter { range.contains($0.start) }
            results.append(CycleMetrics(cycle: cycle, sleepSession: session, sleep: sleepResult, naps: cycleNaps, vitals: v,
                                        night: night, recovery: recovery, strain: strain, target: target, strainMode: mode,
                                        stress: stress, health: health, activities: activityMetrics, totals: totals,
                                        zones: zones, isOpen: isOpen))
            if !isOpen {
                closedStrains.append(strain.strain)
                dailyLoads.append(strain.loadRaw)
            }
            _ = idx
        }

        // Carga aguda y crónica (ALG-CAR-04).
        let acute = StrainCalculator.ewma(dailyLoads, days: p.strain.ewmaAcuteDays)
        let chronic = dailyLoads.count >= 28 ? StrainCalculator.ewma(dailyLoads, days: p.strain.ewmaChronicDays) : nil

        // Impacto de hábitos (ALG-DIA-01).
        let recoveryByDate = Dictionary(results.compactMap { r in r.recovery.score.map { (r.date, Double($0)) } }, uniquingKeysWith: { a, _ in a })
        let strainByDate = Dictionary(results.map { ($0.date, $0.strain.strain) }, uniquingKeysWith: { a, _ in a })
        var impacts: [HabitImpact] = []
        let byQuestion = Dictionary(grouping: input.journal.filter { $0.yes != nil }, by: \.questionKey)
        for (key, answers) in byQuestion {
            let days: [HabitDay] = answers.compactMap { a in
                guard let next = recoveryByDate[a.date.adding(days: 1)], today.days(since: a.date) <= 180 else { return nil }
                return HabitDay(date: a.date, habit: a.yes ?? false, strain: strainByDate[a.date] ?? 0, nextDayRecovery: next)
            }
            impacts.append(HabitImpactCalculator.impact(questionKey: key, days: days))
        }

        // VO₂ máx. principal y edad fisiológica.
        let primaryVO2 = Fusion.primaryVO2(input.vo2max, today: today, params: p)
        let physio = physioAge(input: input, results: results, today: today, fused: fused)

        // Necesidad de sueño para esta noche.
        var tonight: SleepNeedBreakdown?
        if let cur = results.last {
            let mean28 = closedStrains.count >= 7 ? Stats.mean(Array(closedStrains.suffix(28))) : nil
            tonight = SleepCalculator.need(base: SleepCalculator.baseNeed(profile: profile, date: today, params: p),
                                           previousCycleStrain: cur.strain.strain, strainMean28: mean28, currentDebt: debt,
                                           napMinutes: cur.naps.reduce(0) { $0 + $1.minutesAsleep }, params: p)
        }
        let last30 = sleepResults.suffix(30)
        return MetricsOutput(algorithmVersion: AlgorithmParams.currentVersion, cycles: results, fusedHR: fusedHR,
                             fusedActivities: fused, nights: nights, hrMax: hrMax, observedHRMax: observed,
                             acuteLoad: acute, chronicLoad: chronic, habitImpacts: impacts.sorted { $0.questionKey < $1.questionKey },
                             physioAge: physio, primaryVO2: primaryVO2,
                             agreementSummary: Fusion.agreementSummary(fused, params: p), tonightNeed: tonight,
                             usualEfficiency: Stats.median(last30.map(\.efficiency)),
                             usualLatency: Stats.median(last30.compactMap(\.latencyMin)))
    }

    static func minutesIn(_ range: TimeRange, hr: [Int: Double]) -> [HRMinute] {
        var out: [HRMinute] = []
        var m = range.start.minuteEpoch
        while TimeInterval(m) < range.end.timeIntervalSince1970 {
            if let v = hr[m] { out.append(HRMinute(minute: m, bpmAvg: v, source: .googleHealth)) }
            m += 60
        }
        return out
    }

    static func physioAge(input: MetricsInput, results: [CycleMetrics], today: LocalDate, fused: [FusedActivity]) -> PhysioAgeResult? {
        let p = input.params
        guard let age = input.profile.age(on: today) else { return nil }
        let window = results.filter { today.days(since: $0.date) < p.physioAge.windowDays && !$0.isOpen }
        let last31 = window.filter { today.days(since: $0.date) <= 31 }
        let validDays = last31.filter { $0.strain.confidence >= .medium && $0.sleep != nil }.count
        let weeks = max(1, Double(window.count) / 7)
        let vo2Source = Fusion.vo2SourceForPhysioAge(input.vo2max, today: today, windowDays: p.physioAge.windowDays)
        let vo2Values = input.vo2max.filter { $0.source == vo2Source && today.days(since: $0.date) < p.physioAge.windowDays }.map(\.value)
        let moderate = window.reduce(0) { $0 + $1.strain.zoneMinutes[1] + $1.strain.zoneMinutes[2] + $1.strain.zoneMinutes[3] }
        let vigorous = window.reduce(0) { $0 + $1.strain.zoneMinutes[4] + $1.strain.zoneMinutes[5] }
        let strength = fused.filter { $0.kind.isStrength && today.days(since: LocalDate($0.start, utcOffsetSeconds: $0.primary.utcOffsetSeconds)) < p.physioAge.windowDays }
            .reduce(0) { $0 + $1.durationMinutes }
        let inputs = PhysioAgeInputs(
            chronologicalAge: age, sex: input.profile.sex, vo2max: Stats.mean(vo2Values), vo2maxSource: vo2Source,
            stepsPerDay: Stats.mean(window.compactMap { $0.totals.map { Double($0.steps) } }.filter { $0 > 0 }),
            restingHR: Stats.mean(window.compactMap { $0.vitals?.restingHR }),
            moderateMinPerWeek: window.isEmpty ? nil : Double(moderate) / weeks,
            vigorousMinPerWeek: window.isEmpty ? nil : Double(vigorous) / weeks,
            strengthMinPerWeek: strength > 0 ? strength / weeks : nil,
            sleepHours: Stats.mean(window.compactMap { $0.sleep.map { $0.asleepMin / 60 } }),
            sri: Stats.mean(window.compactMap { $0.sleep?.consistency }),
            validDays: validDays)
        return PhysioAgeCalculator.estimate(inputs, params: p)
    }
}
