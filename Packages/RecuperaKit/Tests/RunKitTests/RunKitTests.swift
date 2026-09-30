import Foundation
import Testing
@testable import MetricsKit
@testable import RunKit
@testable import Store

/// Carrera sintética con resultados conocidos: 30 min a 5:00/km hacia el este, subida de 40 m entre los minutos 10 y 15,
/// pausa de 1 min en el minuto 20, FC del Watch de 140 a 150 lpm (deriva) y la de la Fitbit 2 lpm por debajo.
enum SyntheticRun {
    static let start = ISO8601DateFormatter().date(from: "2026-09-27T07:00:00Z")!
    static let speed = 1000.0 / 300   // 5:00/km
    static let pause = (1200.0, 1260.0)

    static func meters(at t: Double) -> Double {
        if t <= pause.0 { return t * speed }
        if t <= pause.1 { return pause.0 * speed }
        return (t - (pause.1 - pause.0)) * speed
    }

    static func altitude(at t: Double) -> Double {
        if t < 600 { return 600 }
        if t < 900 { return 600 + 40 * (t - 600) / 300 }
        return 640
    }

    static func input(fitbit: Bool = true, laps: Bool = true) -> RunInput {
        let end = start.addingTimeInterval(1800)
        let metersPerDegree = 111_320 * cos(40.0 * .pi / 180)
        var route: [RoutePoint] = []
        for t in stride(from: 0.0, through: 1800, by: 1) where !(t > pause.0 && t < pause.1) {
            route.append(RoutePoint(time: start.addingTimeInterval(t), latitude: 40, longitude: -3.7 + meters(at: t) / metersPerDegree,
                                    altitude: altitude(at: t), speed: speed, horizontalAccuracy: 5))
        }
        var samples: [MetricSample] = []
        for t in stride(from: 5.0, through: 1795, by: 10) where !(t > pause.0 && t < pause.1) {
            let time = start.addingTimeInterval(t)
            samples += [MetricSample(metric: "cadence_spm", time: time, value: 172), MetricSample(metric: "power_w", time: time, value: 250),
                        MetricSample(metric: "stride_m", time: time, value: 1.16), MetricSample(metric: "vertical_osc_cm", time: time, value: 8),
                        MetricSample(metric: "ground_contact_ms", time: time, value: 245)]
        }
        let hrWatch = stride(from: 0.0, through: 1800, by: 5).map { t in
            HRSample(time: start.addingTimeInterval(t), bpm: t < 900 ? 140 : 150, source: .appleHealth)
        }
        let hrFitbit = fitbit ? stride(from: 0.0, through: 1800, by: 1).map { t in
            HRSample(time: start.addingTimeInterval(t), bpm: (t < 900 ? 140 : 150) - 2, source: .googleHealth)
        } : []
        let distance = meters(at: 1800)
        let watch = ActivitySession(source: .appleHealth, sourceRecordID: "w1", kind: .running, start: start, end: end, utcOffsetSeconds: 7200,
                                    avgHR: 145, maxHR: 150, caloriesKcal: 420, distanceM: distance, steps: 5000, hasRoute: true,
                                    dynamics: RunningDynamics(avgCadenceSpm: 172))
        var members = [watch]
        if fitbit {
            members.append(ActivitySession(source: .googleHealth, sourceRecordID: "f1", kind: .running, start: start, end: end,
                                           utcOffsetSeconds: 7200, avgHR: 143, caloriesKcal: 400, distanceM: distance * 0.98))
        }
        let activity = FusedActivity(id: watch.id, members: members, start: start, end: end, kind: .running, isLeftover: false,
                                     hrSource: .appleHealth, sourcesDisagree: false, agreement: nil)
        var events = [WorkoutEvent(kind: .pause, start: start.addingTimeInterval(pause.0), end: start.addingTimeInterval(pause.1))]
        if laps {
            events += [WorkoutEvent(kind: .lap, start: start, end: start.addingTimeInterval(900)),
                       WorkoutEvent(kind: .lap, start: start.addingTimeInterval(900), end: end)]
        }
        let watchDetail = ActivityDetail(activityID: watch.id, events: events, weather: WeatherInfo(temperatureC: 18, humidityPct: 60))
        let fitbitDetail = fitbit ? ActivityDetail(activityID: "google_health:f1", mobility: RunningDynamics(avgCadenceSpm: 170), vo2max: 50) : nil
        return RunInput(activity: activity, route: route, samples: samples, hrWatch: hrWatch, hrFitbit: hrFitbit, watchDetail: watchDetail,
                        fitbitDetail: fitbitDetail, zones: StrainCalculator.zones(hrMax: 190, restingRef: 55), sex: .male, weightKg: 70)
    }
}

@Suite struct PhysiologyTests {
    /// Tablas de Daniels para VDOT 50: 5 km 19:57, 10 km 41:21, maratón 3:10:49; T 4:15/km, I 3:55/km.
    @Test func danielsTables() throws {
        let vdot = try #require(RunPhysiology.vdot(meters: 5000, seconds: 19 * 60 + 57))
        #expect(abs(vdot - 50) < 0.3)
        let tenK = try #require(RunPhysiology.predictedSeconds(meters: 10000, vdot: 50))
        #expect(abs(tenK - (41 * 60 + 21)) < 20)
        let marathon = try #require(RunPhysiology.predictedSeconds(meters: 42195, vdot: 50))
        #expect(abs(marathon - (3 * 3600 + 10 * 60 + 49)) < 120)
        let paces = RunPhysiology.trainingPaces(vdot: 50)
        let t = try #require(paces.first { $0.zone == .threshold })
        let i = try #require(paces.first { $0.zone == .interval })
        #expect(abs(1000 / t.fastSpeed - 255) < 3)
        #expect(abs(1000 / i.fastSpeed - 235) < 3)
        let e = try #require(paces.first { $0.zone == .easy })
        #expect(e.slowSpeed < e.fastSpeed && 1000 / e.slowSpeed > 1000 / t.fastSpeed)
    }

    @Test func riegelMinettiAndVO2() throws {
        #expect(abs(RunPhysiology.riegel(seconds: 1200, fromMeters: 5000, toMeters: 10000) - 1200 * pow(2, 1.06)) < 0.001)
        #expect(RunPhysiology.minettiCost(grade: 0) == 3.6)
        #expect(RunPhysiology.gradeAdjusted(speed: 3, grade: 0.1) > 3)
        #expect(RunPhysiology.gradeAdjusted(speed: 3, grade: -0.05) < 3)
        // 5:00/km a 150 lpm con FC máx. 190: ≈ 55 ml/kg/min.
        let vo2 = try #require(RunPhysiology.estimatedVO2max(avgSpeed: 1000.0 / 300, avgHR: 150, hrMax: 190))
        #expect(abs(vo2 - 55) < 1)
        #expect(RunPhysiology.estimatedVO2max(avgSpeed: 3, avgHR: 100, hrMax: 190) == nil)
    }
}

@Suite struct RunAnalysisTests {
    @Test func steadyRunWithClimbPauseAndDrift() throws {
        let r = RunAnalyzer.analyze(SyntheticRun.input(), context: RunContext(vdot: 50, thresholdSpeed: 1000.0 / 255, criticalPower: 280))
        #expect(r.distanceSource == .gps && r.hrSource == .appleHealth)
        #expect(abs(r.distanceM - SyntheticRun.meters(at: 1800)) < 5)
        #expect(abs(r.pausedS - 60) <= 2 && r.pauses == 1)
        #expect(abs(r.movingS - 1740) <= 5)
        #expect(abs((r.avgPace ?? 0) - 300) < 4)
        // Parciales: 5 km completos a 5:00 y un último tramo; el km de la subida tiene un GAP más rápido.
        #expect(r.splits.count == 6)
        for s in r.splits.prefix(5) { #expect(abs(s.pace - 300) < 6) }
        let climbKm = try #require(r.splits.first { $0.elevationGainM > 10 })
        #expect((climbKm.gapPace ?? 999) < climbKm.pace - 5)
        // Mejores marcas sin contar la pausa.
        let k1 = try #require(r.bestEfforts.first { $0.distance == .k1 })
        let k5 = try #require(r.bestEfforts.first { $0.distance == .k5 })
        #expect(abs(k1.seconds - 300) < 5 && abs(k5.seconds - 1500) < 10)
        // Desnivel y subida.
        #expect(abs((r.elevationGainM ?? 0) - 40) < 5)
        #expect(r.climbs.count == 1 && abs(r.climbs[0].avgGradePct - 4) < 1)
        // Deriva cardiaca y desacoplamiento.
        #expect((r.hrDriftPct ?? 0) > 5 && (r.decouplingPct ?? 0) > 3)
        #expect(r.vo2maxEstimate != nil && r.efficiencyFactor != nil && (r.trimp ?? 0) > 20)
        #expect(abs((r.intensityFactor ?? 0) - 255.0 / 300) < 0.05 && r.stressScore != nil)
        // Zonas: toda la carrera en Z3–Z4 de FC y con potencia en zona 1 (250 W con PC 280).
        #expect(abs(r.hrZoneSeconds.reduce(0, +) - 1740) < 10)
        #expect((r.paceZoneSeconds?.reduce(0, +) ?? 0) > 1700 && (r.powerZoneSeconds?[1] ?? 0) > 1700)
        // Vueltas del reloj, técnica, comparación y gráficas.
        #expect(r.laps.count == 2 && abs((r.laps[0].distanceM ?? 0) - 3000) < 10)
        #expect(r.form.first { $0.metric == .cadence }?.rating == .good)
        #expect(r.form.first { $0.metric == .power }?.note.contains(",") == true)
        #expect(abs((r.verticalRatioPct ?? 0) - 8 / 1.16) < 0.1)
        let c = try #require(r.comparison)
        #expect(abs((c.hrBias ?? 0) - 2) < 0.5 && c.fitbitVO2max == 50 && c.fitbitCadence == 170)
        #expect(r.chart.count <= 400 && r.chart.count > 300)
        #expect(r.chart.filter { $0.pace != nil }.allSatisfy { abs($0.pace! - 300) < 40 || $0.altitude != nil })
        #expect(r.weather?.temperatureC == 18)
        #expect(r.paceCurve.first { $0.seconds == 600 }.map { abs($0.value - SyntheticRun.speed) < 0.1 } == true)
        #expect(r.hrCurve.first { $0.seconds == 300 }?.value == 150)
    }

    /// Carrera solo con la Fitbit y sin GPS: distancia y cadencia salen de sus parciales.
    @Test func fitbitOnlyRunUsesItsSplits() throws {
        let start = SyntheticRun.start
        let end = start.addingTimeInterval(1500)
        let session = ActivitySession(source: .googleHealth, sourceRecordID: "f2", kind: .running, start: start, end: end,
                                      utcOffsetSeconds: 7200, distanceM: 5000)
        let activity = FusedActivity(id: session.id, members: [session], start: start, end: end, kind: .running, isLeftover: false,
                                     hrSource: nil, sourcesDisagree: false, agreement: nil)
        var splits: [SourceSplit] = []
        for k in 0..<5 {
            let from = start.addingTimeInterval(Double(k) * 300)
            let seconds: Double = k == 4 ? 280 : 300
            splits.append(SourceSplit(start: from, end: from.addingTimeInterval(seconds), kind: "km", distanceM: 1000, avgHR: 150, avgCadence: 168))
        }
        let hr = stride(from: 0.0, through: 1500, by: 2).map { HRSample(time: start.addingTimeInterval($0), bpm: 150, source: .googleHealth) }
        let input = RunInput(activity: activity, hrFitbit: hr, fitbitDetail: ActivityDetail(activityID: session.id, splits: splits),
                             zones: StrainCalculator.zones(hrMax: 190, restingRef: 55))
        let r = RunAnalyzer.analyze(input)
        #expect(r.distanceSource == .fitbitSplits && r.hrSource == .googleHealth)
        #expect(abs(r.distanceM - 5000) < 1 && r.splits.count == 5)
        #expect(abs(r.splits[0].pace - 300) < 3 && r.splits[4].pace < r.splits[0].pace)
        #expect(r.avgCadence == 168 && r.comparison == nil)
    }

    /// En cinta la distancia viene de las muestras del reloj, no del GPS.
    @Test func treadmillUsesWatchDistanceSamples() {
        let start = SyntheticRun.start
        let end = start.addingTimeInterval(1200)
        let session = ActivitySession(source: .appleHealth, sourceRecordID: "t1", kind: .treadmill, start: start, end: end,
                                      utcOffsetSeconds: 7200, distanceM: 4000)
        let activity = FusedActivity(id: session.id, members: [session], start: start, end: end, kind: .treadmill, isLeftover: false,
                                     hrSource: nil, sourcesDisagree: false, agreement: nil)
        let samples = stride(from: 10.0, through: 1200, by: 10).map { MetricSample(metric: "distance_m", time: start.addingTimeInterval($0), value: 1000.0 / 30) }
        let r = RunAnalyzer.analyze(RunInput(activity: activity, samples: samples, zones: StrainCalculator.zones(hrMax: 190, restingRef: 55)))
        #expect(r.distanceSource == .watchSamples)
        #expect(abs(r.distanceM - 4000) < 1 && r.splits.count == 4 && abs(r.splits[1].pace - 300) < 3)
        #expect(r.climbs.isEmpty && r.elevationGainM == nil)
    }

    @Test func resamplingAndSmoothing() {
        let v = RunSeriesBuilder.resample([(0, 0), (10, 10), (100, 100)], grid: [0, 5, 10, 50, 100], maxGap: 20)
        #expect(v[1] == 5 && v[2] == 10 && v[3] == nil && v[4] == 100)
        let s = RunSeriesBuilder.smooth([1, nil, 3, 5, nil], window: 3)
        #expect(s[0] == 1 && s[1] == nil && s[2] == 4 && s[3] == 4 && s[4] == nil)
        #expect(abs(Geo.distance(40, -3.7, 40, -3.7 + 1000 / (111_320 * cos(40.0 * .pi / 180))) - 1000) < 5)
    }
}

@Suite struct RunLibraryTests {
    func output(runs: [FusedActivity]) -> MetricsOutput {
        MetricsOutput(algorithmVersion: "t", cycles: [], fusedHR: [], fusedActivities: runs, nights: [], hrMax: 190, observedHRMax: nil,
                      acuteLoad: nil, chronicLoad: nil, habitImpacts: [], physioAge: nil, primaryVO2: nil, estimatedVO2: nil,
                      agreementSummary: nil, tonightNeed: nil, usualEfficiency: nil, usualLatency: nil)
    }

    func store(_ input: RunInput, in db: AppDatabase) throws {
        try db.upsertActivities(input.activity.members)
        let watchID = input.activity.watchMember!.id
        try db.saveRoute(input.route, activityID: watchID)
        try db.saveMetricSamples(input.samples, activityID: watchID)
        try db.upsertHRSamples(input.hrWatch, activityID: watchID)
        try db.upsertHRSamples(input.hrFitbit, activityID: input.activity.fitbitMember?.id)
        try db.saveActivityDetails([input.watchDetail, input.fitbitDetail].compactMap { $0 })
    }

    @Test func refreshCachesAndRecomputesWhenTheRunChanges() throws {
        let db = try AppDatabase.inMemory()
        let input = SyntheticRun.input()
        try store(input, in: db)
        let first = try RunLibrary.refresh(db: db, output: output(runs: [input.activity]), profile: UserProfile(sex: .male, weightKg: 70))
        let s = try #require(first.first)
        #expect(first.count == 1 && abs((s.best(.k5) ?? 0) - 1500) < 10 && s.sources == [.appleHealth, .googleHealth])
        #expect(s.startLat == 40 && s.fitbitVO2max == 50 && (s.trimp ?? 0) > 0)
        // Sin cambios, sale de la caché (aunque ya no esté la ruta).
        try db.saveRoute([], activityID: input.activity.watchMember!.id)
        #expect(try RunLibrary.refresh(db: db, output: output(runs: [input.activity]), profile: UserProfile()).first?.best(.k5) == s.best(.k5))
        // Si cambia la fusión (sin la Fitbit), se recalcula.
        var watchOnly = input.activity
        watchOnly.members = [input.activity.watchMember!]
        let again = try RunLibrary.refresh(db: db, output: output(runs: [watchOnly]), profile: UserProfile())
        #expect(again.first?.sources == [.appleHealth] && again.first?.startLat == nil)
        // Una carrera del historial (anterior a la ventana del motor, solo en la BD) también está, fusionada aquí.
        var old = input.activity.members
        for i in old.indices {
            old[i].sourceRecordID += "-old"
            old[i].id = "\(old[i].source.rawValue):\(old[i].sourceRecordID)"
            old[i].start = old[i].start.addingTimeInterval(-400 * 86_400)
            old[i].end = old[i].end.addingTimeInterval(-400 * 86_400)
        }
        try db.upsertActivities(old)
        let all = try RunLibrary.allRuns(db: db, output: output(runs: [watchOnly]))
        #expect(all.count == 2 && all[0].members.count == 2 && all[0].start < input.activity.start)
        #expect(try RunLibrary.refresh(db: db, output: output(runs: [watchOnly]), profile: UserProfile()).count == 2)
        // Una carrera borrada (en Salud y en Google) deja de estar.
        for m in input.activity.members + old { try db.deleteActivities(source: m.source, sourceRecordIDs: [m.sourceRecordID]) }
        #expect(try RunLibrary.refresh(db: db, output: output(runs: []), profile: UserProfile()).isEmpty)
    }

    func summary(_ day: String, km: Double, pace: Double = 300, trimp: Double = 50, efforts: [RaceDistance: Double] = [:],
                 power20: Double? = nil, lat: Double? = nil) -> RunSummary {
        let start = ISO8601DateFormatter().date(from: "\(day)T07:00:00Z")!
        var best: [String: Double] = [:]
        for (d, s) in efforts { best[d.key] = s }
        return RunSummary(id: "run-\(day)", start: start, utcOffsetSeconds: 0, kind: .running, name: "Carrera", distanceM: km * 1000,
                          movingS: km * pace, elapsedS: km * pace, avgSpeed: 1000 / pace, avgGAPSpeed: 1000 / pace, avgHR: 150, maxHR: 170,
                          elevationGainM: 20, cadence: 170, power: 240, stride: 1.1, verticalOsc: 8, groundContact: 250, trimp: trimp,
                          vo2maxEstimate: nil, efficiency: 1.4, decoupling: 3, bestEfforts: best, paceCurve: [],
                          powerCurve: power20.map { [CurvePoint(seconds: 1200, value: $0)] } ?? [], startLat: lat, startLon: lat.map { _ in -3.7 },
                          temperatureC: nil, sources: [.appleHealth], fitbitVO2max: nil, signature: "")
    }

    @Test func volumeStreakRecordsFitnessAndPredictions() throws {
        let today = LocalDate(year: 2026, month: 9, day: 30)   // miércoles
        let h = RunHistory(summaries: [
            summary("2026-09-14", km: 8), summary("2026-09-22", km: 10, efforts: [.k5: 19 * 60 + 57, .k10: 42 * 60]),
            summary("2026-09-29", km: 5, efforts: [.k5: 21 * 60], power20: 300, lat: 40.001),
            summary("2026-09-30", km: 5.2, lat: 40.0015),
        ])
        let weeks = h.weeks(count: 3, today: today)
        #expect(weeks.map(\.distanceM) == [8000, 10000, 10200] && weeks.last?.runs == 2)
        #expect(weeks.last?.start == LocalDate(year: 2026, month: 9, day: 28))
        #expect(h.weekStreak(today: today) == 3)
        #expect(h.months(count: 2, today: today).last?.runs == 4)
        let k5 = try #require(h.records().first { $0.distance == .k5 })
        #expect(k5.seconds == 19 * 60 + 57 && k5.runID == "run-2026-09-22")
        #expect(h.personalRecords(in: h.summaries[1]) == [.k5, .k10] && h.personalRecords(in: h.summaries[2]).isEmpty)
        #expect(h.recordRunIDs() == Set(h.summaries.filter { !h.personalRecords(in: $0).isEmpty }.map(\.id)))
        #expect(h.years(count: 2, today: today).map(\.runs) == [0, 4])
        let vdot = try #require(h.vdot(today: today))
        #expect(abs(vdot.value - 50) < 0.5 && vdot.distance == .k5 && !vdot.fromEstimates)
        let tenK = try #require(h.predictions(vdot: vdot.value).first { $0.distance == .k10 })
        #expect(abs(tenK.seconds - (41 * 60 + 21)) < 30)
        #expect(h.criticalPower(today: today) == 285)
        let ctx = h.context(today: today)
        #expect(ctx.criticalPower == 285 && ctx.thresholdSpeed != nil)
        #expect(h.similar(to: h.summaries[3]).map(\.id) == ["run-2026-09-29"])
        // Forma: con carga diaria constante la forma (CTL) sube más despacio que la fatiga (ATL).
        let steady = RunHistory(summaries: (0..<60).map { k in summary(LocalDate(year: 2026, month: 8, day: 1).adding(days: k).isoString, km: 5) })
        let points = steady.fitness(days: 30, today: LocalDate(year: 2026, month: 9, day: 29))
        #expect(points.count == 30 && points.last!.fatigue > points.last!.fitness && points.last!.fitness > 30)
    }

    @Test func vdotBlendsTrainingEffortsWithEstimates() throws {
        let today = LocalDate(year: 2026, month: 9, day: 30)
        // Una marca floja de entrenamiento (5 km en 25:00, VDOT ≈ 38) y VO₂ estimados de 46: se queda a medio camino.
        var runs = [summary("2026-09-20", km: 6, efforts: [.k5: 25 * 60])]
        for day in ["2026-09-24", "2026-09-26", "2026-09-28"] {
            var s = summary(day, km: 8)
            s.vo2maxEstimate = 46
            runs.append(s)
        }
        let v = try #require(RunHistory(summaries: runs).vdot(today: today))
        let effort = try #require(RunPhysiology.vdot(meters: 5000, seconds: 25 * 60))
        #expect(v.blended && !v.fromEstimates && v.distance == .k5 && abs(v.value - (effort + 46) / 2) < 0.01)
        // Si la marca ya es mejor que lo estimado, manda la marca.
        let fast = try #require(RunHistory(summaries: [summary("2026-09-20", km: 6, efforts: [.k5: 19 * 60 + 57])] + runs.dropFirst())
            .vdot(today: today))
        #expect(!fast.blended && abs(fast.value - 50) < 0.5)
    }

    @Test func rollingMeanSmoothsPerRunValues() {
        #expect(RunHistory.rollingMean([1, 2, 3, 4, 5], radius: 1) == [1.5, 2, 3, 4, 4.5])
        #expect(RunHistory.rollingMean([1, 2, 3, 4, 5]) == [2, 2.5, 3, 3.5, 4])
        #expect(RunHistory.rollingMean([7, 9]) == [7, 9])
    }

    @Test func shoesCountTheirKilometers() {
        let h = RunHistory(summaries: [summary("2026-09-20", km: 10), summary("2026-09-25", km: 12), summary("2026-09-28", km: 8)])
        let old = Shoe(id: "a", name: "Pegasus", startKm: 400, isDefault: true, addedAt: ISO8601DateFormatter().date(from: "2026-09-01T00:00:00Z")!)
        let new = Shoe(id: "b", name: "Vaporfly", addedAt: ISO8601DateFormatter().date(from: "2026-09-24T00:00:00Z")!)
        let km = h.shoeKilometers(shoes: [old, new], assignments: ["run-2026-09-25": "b"])
        #expect(km["a"] == 418 && km["b"] == 12)
    }

    @Test func gpxHasTrackPointsWithHeartRateAndCadence() {
        let input = SyntheticRun.input()
        let series = RunSeriesBuilder.build(input)
        let gpx = GPXWriter.gpx(name: "Rodaje & series", route: Array(input.route.prefix(3)), series: series)
        #expect(gpx.components(separatedBy: "<trkpt").count - 1 == 3)
        #expect(gpx.contains("<gpxtpx:hr>140</gpxtpx:hr>") && gpx.contains("<gpxtpx:cad>86</gpxtpx:cad>"))
        #expect(gpx.contains("Rodaje &amp; series") && gpx.contains("<ele>600.0</ele>"))
    }
}

@Suite struct RunDemoTests {
    @Test func demoRunsHaveEverythingTheScreensShow() throws {
        let now = ISO8601DateFormatter().date(from: "2026-09-29T19:00:00Z")!
        let data = SyntheticData.generate(days: 40, endingAt: now, utcOffsetSeconds: 7200)
        let output = MetricsEngine.run(data)
        let runs = RunLibrary.runs(in: output)
        let run = try #require(runs.last { $0.fitbitMember != nil && $0.watchMember != nil })
        let input = RunDemo.input(for: run, zones: RunLibrary.zones(for: run, output: output), profile: data.profile)
        // Reproducible.
        #expect(RunDemo.input(for: run, zones: input.zones, profile: data.profile).route == input.route)
        let r = RunAnalyzer.analyze(input)
        #expect(r.distanceSource == .gps && abs(r.distanceM - (run.distanceM ?? 0)) < 0.2 * (run.distanceM ?? 1))
        #expect(!r.splits.isEmpty && !r.bestEfforts.isEmpty && r.avgCadence != nil && r.avgPower != nil && r.hasDynamics)
        #expect(r.comparison?.hrBias != nil && r.weather != nil && r.hasAltitude)
        let summaries = RunDemo.summaries(output: output, profile: data.profile)
        #expect(summaries.count == runs.count && RunHistory(summaries: summaries).vdot(today: LocalDate(now, utcOffsetSeconds: 7200)) != nil)
    }
}
