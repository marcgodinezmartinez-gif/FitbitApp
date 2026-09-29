import Foundation
import MetricsKit
import Store

/// Resumen de una carrera que se guarda en caché: lo que usa el historial sin volver a leer sus series.
public struct RunSummary: Codable, Sendable, Hashable, Identifiable {
    /// Súbela cuando cambie el análisis para que se recalculen todos.
    public static let version = 1

    public var id: String
    public var start: Date
    public var utcOffsetSeconds: Int
    public var kind: ActivityKind
    public var name: String
    public var distanceM: Double
    public var movingS: Double
    public var elapsedS: Double
    public var avgSpeed: Double?
    public var avgGAPSpeed: Double?
    public var avgHR: Double?
    public var maxHR: Double?
    public var elevationGainM: Double?
    public var cadence: Double?
    public var power: Double?
    public var stride: Double?
    public var verticalOsc: Double?
    public var groundContact: Double?
    public var trimp: Double?
    public var vo2maxEstimate: Double?
    public var efficiency: Double?
    public var decoupling: Double?
    /// Mejores marcas de esta carrera: clave de `RaceDistance` → segundos.
    public var bestEfforts: [String: Double]
    public var paceCurve: [CurvePoint]
    public var powerCurve: [CurvePoint]
    /// Punto de salida redondeado (≈ 100 m) para encontrar carreras por la misma zona; nunca sale del iPhone.
    public var startLat: Double?
    public var startLon: Double?
    public var temperatureC: Double?
    public var sources: [DataSourceKind]
    public var fitbitVO2max: Double?
    /// Sesiones que la forman: si cambia la fusión, se recalcula.
    public var signature: String

    public var date: LocalDate { LocalDate(start, utcOffsetSeconds: utcOffsetSeconds) }
    public var avgPace: Double? { avgSpeed.flatMap { $0 > 0.3 ? 1000 / $0 : nil } }
    public func best(_ d: RaceDistance) -> Double? { bestEfforts[d.key] }
}

public enum RunLibrary {
    /// Carreras (ya fusionadas) de la salida del motor.
    public static func runs(in output: MetricsOutput) -> [FusedActivity] {
        output.fusedActivities.filter { $0.kind.isRun && !$0.isLeftover }
    }

    /// Zonas de FC vigentes el día de la carrera.
    public static func zones(for run: FusedActivity, output: MetricsOutput) -> HRZones {
        let now = Date()
        return output.cycles.last { $0.cycle.contains(run.start, now: now) }?.zones ?? output.cycles.last?.zones
            ?? StrainCalculator.zones(hrMax: output.hrMax, restingRef: 60)
    }

    /// Lee de la base de datos todo lo de una carrera.
    public static func input(for run: FusedActivity, db: AppDatabase, zones: HRZones, profile: UserProfile) throws -> RunInput {
        let watch = run.watchMember, fitbit = run.fitbitMember
        let from = run.start.addingTimeInterval(-30), to = run.end.addingTimeInterval(30)
        return RunInput(activity: run,
                        route: try watch.map { try db.route(activityID: $0.id) } ?? [],
                        samples: try watch.map { try db.metricSamples(activityID: $0.id) } ?? [],
                        hrWatch: watch == nil ? [] : try db.hrSamples(source: .appleHealth, from: from, to: to),
                        hrFitbit: try db.hrSamples(source: .googleHealth, from: from, to: to),
                        watchDetail: try watch.flatMap { try db.activityDetail(activityID: $0.id) },
                        fitbitDetail: try fitbit.flatMap { try db.activityDetail(activityID: $0.id) },
                        zones: zones, sex: profile.sex, weightKg: profile.weightKg)
    }

    static func signature(_ run: FusedActivity) -> String {
        run.members.map { "\($0.id)@\(Int($0.end.timeIntervalSince1970)):\(Int(($0.distanceM ?? 0).rounded()))" }.joined(separator: "|")
    }

    public static func summary(_ run: FusedActivity, analysis r: RunAnalysis, route: [RoutePoint]) -> RunSummary {
        var efforts: [String: Double] = [:]
        for e in r.bestEfforts { efforts[e.distance.key] = e.seconds }
        let first = route.first { ($0.horizontalAccuracy ?? 0) <= 50 }
        func rounded(_ x: Double?) -> Double? { x.map { ($0 * 1000).rounded() / 1000 } }
        return RunSummary(id: run.id, start: run.start, utcOffsetSeconds: run.primary.utcOffsetSeconds, kind: run.kind, name: run.name,
                          distanceM: r.distanceM, movingS: r.movingS, elapsedS: r.elapsedS, avgSpeed: r.avgSpeed, avgGAPSpeed: r.avgGAPSpeed,
                          avgHR: r.avgHR, maxHR: r.maxHR, elevationGainM: r.elevationGainM, cadence: r.avgCadence, power: r.avgPower,
                          stride: r.avgStride, verticalOsc: r.avgVerticalOsc, groundContact: r.avgGroundContact, trimp: r.trimp,
                          vo2maxEstimate: r.vo2maxEstimate, efficiency: r.efficiencyFactor, decoupling: r.decouplingPct,
                          bestEfforts: efforts, paceCurve: r.paceCurve, powerCurve: r.powerCurve,
                          startLat: rounded(first?.latitude), startLon: rounded(first?.longitude), temperatureC: r.weather?.temperatureC,
                          sources: run.sources, fitbitVO2max: r.comparison?.fitbitVO2max, signature: signature(run))
    }

    nonisolated(unsafe) static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    nonisolated(unsafe) static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    /// Calcula y guarda los resúmenes que falten o hayan cambiado; devuelve todos, del más antiguo al más reciente.
    /// Las carreras que ya se salen de la ventana del motor se conservan (el historial sigue teniendo sus marcas).
    @discardableResult
    public static func refresh(db: AppDatabase, output: MetricsOutput, profile: UserProfile) throws -> [RunSummary] {
        let runs = runs(in: output)
        var cached: [String: RunSummary] = [:]
        for row in try db.runSummaries() where row.version == RunSummary.version {
            if let s = try? decoder.decode(RunSummary.self, from: Data(row.json.utf8)) { cached[row.activityID] = s }
        }
        var current: [String: RunSummary] = [:]
        for run in runs {
            if let c = cached[run.id], c.signature == signature(run) { current[run.id] = c; continue }
            let input = try input(for: run, db: db, zones: zones(for: run, output: output), profile: profile)
            let summary = summary(run, analysis: RunAnalyzer.analyze(input), route: input.route)
            let json = String(decoding: try encoder.encode(summary), as: UTF8.self)
            try db.saveRunSummary(activityID: run.id, version: RunSummary.version, start: run.start, json: json)
            current[run.id] = summary
        }
        // Fuera de la ventana del motor: se quedan. Dentro y ya no están: se borraron o se fusionaron de otra forma.
        let windowStart = output.cycles.first?.cycle.start ?? .distantPast
        for (id, s) in cached where current[id] == nil && s.start < windowStart { current[id] = s }
        try db.deleteRunSummaries(keeping: Set(current.keys))
        return current.values.sorted { $0.start < $1.start }
    }
}

// MARK: - Historial

public struct RunPeriod: Sendable, Hashable, Identifiable {
    public var start: LocalDate
    public var distanceM: Double
    public var movingS: Double
    public var runs: Int
    public var elevationM: Double
    public var longestM: Double
    public var trimp: Double
    public var id: String { start.isoString }
}

public struct RunRecord: Sendable, Hashable, Identifiable {
    public var distance: RaceDistance
    public var seconds: Double
    public var runID: String
    public var date: LocalDate
    public var id: Double { distance.rawValue }
}

/// Forma física (CTL), fatiga (ATL) y frescura (TSB) con la carga de las carreras (TRIMP).
public struct FitnessPoint: Sendable, Hashable, Identifiable {
    public var date: LocalDate
    public var load: Double
    public var fitness: Double
    public var fatigue: Double
    public var form: Double { fitness - fatigue }
    public var id: String { date.isoString }
}

public struct VDOTEstimate: Sendable, Hashable {
    public var value: Double
    /// Qué marca lo sostiene, p. ej. «5 km en 22:10».
    public var distance: RaceDistance?
    public var seconds: Double?
    public var runID: String?
    public var date: LocalDate?
    /// true si sale de la media de VO₂ máx. estimados (no hay marcas buenas recientes).
    public var fromEstimates: Bool
}

public enum RunTrendMetric: String, CaseIterable, Sendable, Identifiable {
    case pace, efficiency, vo2max, heartRate, cadence, stride, groundContact, verticalOsc, power, decoupling

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .pace: return "Ritmo medio"
        case .efficiency: return "Eficiencia"
        case .vo2max: return "VO₂ máx. estimado"
        case .heartRate: return "FC media"
        case .cadence: return "Cadencia"
        case .stride: return "Zancada"
        case .groundContact: return "Contacto con el suelo"
        case .verticalOsc: return "Oscilación vertical"
        case .power: return "Potencia"
        case .decoupling: return "Desacoplamiento"
        }
    }

    /// Si un valor más alto es mejor (para colorear la tendencia).
    public var higherIsBetter: Bool {
        switch self {
        case .efficiency, .vo2max, .cadence, .stride, .power: return true
        case .pace, .heartRate, .groundContact, .verticalOsc, .decoupling: return false
        }
    }

    public func value(_ s: RunSummary) -> Double? {
        switch self {
        case .pace: return s.avgPace
        case .efficiency: return s.efficiency
        case .vo2max: return s.vo2maxEstimate
        case .heartRate: return s.avgHR
        case .cadence: return s.cadence
        case .stride: return s.stride
        case .groundContact: return s.groundContact
        case .verticalOsc: return s.verticalOsc
        case .power: return s.power
        case .decoupling: return s.decoupling
        }
    }
}

public struct RunHistory: Sendable {
    public var summaries: [RunSummary]

    public init(summaries: [RunSummary]) { self.summaries = summaries.sorted { $0.start < $1.start } }

    // MARK: Volumen

    static func weekStart(_ d: LocalDate) -> LocalDate { d.adding(days: -(d.isoWeekday - 1)) }

    static func monthStart(_ d: LocalDate) -> LocalDate { LocalDate(year: d.year, month: d.month, day: 1) }

    func period(start: LocalDate, runs: [RunSummary]) -> RunPeriod {
        RunPeriod(start: start, distanceM: runs.reduce(0) { $0 + $1.distanceM }, movingS: runs.reduce(0) { $0 + $1.movingS },
                  runs: runs.count, elevationM: runs.reduce(0) { $0 + ($1.elevationGainM ?? 0) },
                  longestM: runs.map(\.distanceM).max() ?? 0, trimp: runs.reduce(0) { $0 + ($1.trimp ?? 0) })
    }

    /// Últimas `count` semanas (lunes a domingo), de la más antigua a la actual.
    public func weeks(count: Int, today: LocalDate) -> [RunPeriod] {
        let current = Self.weekStart(today)
        let byWeek = Dictionary(grouping: summaries) { Self.weekStart($0.date) }
        return (0..<count).reversed().map { k in
            let start = current.adding(days: -7 * k)
            return period(start: start, runs: byWeek[start] ?? [])
        }
    }

    /// Últimos `count` meses, del más antiguo al actual.
    public func months(count: Int, today: LocalDate) -> [RunPeriod] {
        let byMonth = Dictionary(grouping: summaries) { Self.monthStart($0.date) }
        var starts: [LocalDate] = []
        var y = today.year, m = today.month
        for _ in 0..<count {
            starts.append(LocalDate(year: y, month: m, day: 1))
            m -= 1
            if m == 0 { m = 12; y -= 1 }
        }
        return starts.reversed().map { period(start: $0, runs: byMonth[$0] ?? []) }
    }

    public func totals(from: LocalDate, to: LocalDate) -> RunPeriod {
        period(start: from, runs: summaries.filter { $0.date >= from && $0.date <= to })
    }

    /// Semanas seguidas (hasta la actual) con al menos una carrera; la actual cuenta aunque aún no hayas corrido.
    public func weekStreak(today: LocalDate) -> Int {
        let weeks = Set(summaries.map { Self.weekStart($0.date) })
        var start = Self.weekStart(today)
        if !weeks.contains(start) { start = start.adding(days: -7) }
        var streak = 0
        while weeks.contains(start) { streak += 1; start = start.adding(days: -7) }
        return streak
    }

    // MARK: Récords

    /// Mejor marca en cada distancia (desde `since`, o de siempre).
    public func records(since: LocalDate? = nil) -> [RunRecord] {
        let pool = summaries.filter { since == nil || $0.date >= since! }
        return RaceDistance.allCases.compactMap { d in
            pool.compactMap { s in s.best(d).map { (s, $0) } }.min { $0.1 < $1.1 }
                .map { RunRecord(distance: d, seconds: $0.1, runID: $0.0.id, date: $0.0.date) }
        }
    }

    /// Distancias en las que esta carrera es tu mejor marca (de siempre, en el historial guardado).
    public func personalRecords(in run: RunSummary) -> [RaceDistance] {
        RaceDistance.allCases.filter { d in
            guard let mine = run.best(d) else { return false }
            return !summaries.contains { $0.id != run.id && $0.start < run.start && ($0.best(d) ?? .infinity) <= mine }
        }
    }

    public var longestRun: RunSummary? { summaries.max { $0.distanceM < $1.distanceM } }
    public var biggestClimb: RunSummary? { summaries.filter { ($0.elevationGainM ?? 0) > 0 }.max { ($0.elevationGainM ?? 0) < ($1.elevationGainM ?? 0) } }

    // MARK: Forma

    /// CTL (42 días) y ATL (7 días) con medias exponenciales de la carga diaria de las carreras.
    public func fitness(days: Int, today: LocalDate) -> [FitnessPoint] {
        guard let first = summaries.first?.date else { return [] }
        var load: [Int: Double] = [:]
        for s in summaries { load[s.date.dayNumber, default: 0] += s.trimp ?? 0 }
        let begin = min(first, today.adding(days: -days))
        var ctl = 0.0, atl = 0.0
        var out: [FitnessPoint] = []
        var d = begin
        while d <= today {
            let l = load[d.dayNumber] ?? 0
            ctl += (l - ctl) / 42
            atl += (l - atl) / 7
            if d >= today.adding(days: -days + 1) { out.append(FitnessPoint(date: d, load: l, fitness: ctl, fatigue: atl)) }
            d = d.adding(days: 1)
        }
        return out
    }

    // MARK: VDOT, predicciones y potencia crítica

    /// VDOT actual: la mejor marca reciente (≥ 3 km); si no hay, la mediana de los VO₂ máx. estimados.
    public func vdot(today: LocalDate, days: Int = 120) -> VDOTEstimate? {
        let recent = summaries.filter { $0.date >= today.adding(days: -days) }
        var best: VDOTEstimate?
        for s in recent {
            for d in RaceDistance.allCases where d.rawValue >= 3000 {
                guard let secs = s.best(d), let v = RunPhysiology.vdot(meters: d.rawValue, seconds: secs) else { continue }
                if v > (best?.value ?? 0) {
                    best = VDOTEstimate(value: v, distance: d, seconds: secs, runID: s.id, date: s.date, fromEstimates: false)
                }
            }
        }
        let estimates = recent.suffix(10).compactMap(\.vo2maxEstimate)
        if let median = Stats.median(estimates), estimates.count >= 3 {
            // Las marcas de entrenamiento infravaloran el VDOT: si los VO₂ estimados apuntan más alto, se usan (a medio camino).
            if let b = best, median > b.value { best?.value = (b.value + median) / 2 }
            if best == nil { best = VDOTEstimate(value: median, fromEstimates: true) }
        }
        return best
    }

    public func predictions(vdot: Double) -> [(distance: RaceDistance, seconds: Double)] {
        RaceDistance.predicted.compactMap { d in RunPhysiology.predictedSeconds(meters: d.rawValue, vdot: vdot).map { (d, $0) } }
    }

    /// Potencia crítica aproximada: 95 % de la mejor media de 20 min (o 90 % de la de 10 min) de los últimos 90 días.
    public func criticalPower(today: LocalDate) -> Double? {
        let recent = summaries.filter { $0.date >= today.adding(days: -90) }
        func best(_ seconds: Double) -> Double? { recent.compactMap { s in s.powerCurve.first { $0.seconds == seconds }?.value }.max() }
        if let p = best(1200) { return 0.95 * p }
        if let p = best(600) { return 0.90 * p }
        return nil
    }

    public func context(today: LocalDate) -> RunContext {
        let v = vdot(today: today)?.value
        return RunContext(vdot: v, thresholdSpeed: v.map { RunPhysiology.speed(fractionOfVDOT: 0.88, vdot: $0) },
                          criticalPower: criticalPower(today: today))
    }

    // MARK: Tendencias

    public func trend(_ metric: RunTrendMetric, days: Int, today: LocalDate) -> [(date: Date, value: Double)] {
        summaries.filter { $0.date >= today.adding(days: -days) && $0.movingS >= 600 }.compactMap { s in metric.value(s).map { (s.start, $0) } }
    }

    // MARK: Carreras parecidas

    /// Por la misma zona (salida a menos de 300 m) y con distancia parecida (±15 %); si no hay, solo por distancia.
    public func similar(to run: RunSummary, limit: Int = 8) -> [RunSummary] {
        let others = summaries.filter { $0.id != run.id && abs($0.distanceM - run.distanceM) <= 0.15 * run.distanceM && $0.kind == run.kind }
        let sameArea = others.filter { s in
            guard let a = run.startLat, let b = run.startLon, let c = s.startLat, let d = s.startLon else { return false }
            return Geo.distance(a, b, c, d) <= 300
        }
        return Array((sameArea.isEmpty ? others : sameArea).sorted { $0.start > $1.start }.prefix(limit))
    }

    // MARK: Zapatillas

    /// Zapatillas de una carrera: las elegidas o, si no, las predeterminadas que ya tenías ese día.
    public static func shoeID(for run: RunSummary, shoes: [Shoe], assignments: [String: String]) -> String? {
        if let id = assignments[run.id], shoes.contains(where: { $0.id == id }) { return id }
        return shoes.first { $0.isDefault && !$0.retired && $0.addedAt <= run.start.addingTimeInterval(86_400) }?.id
    }

    /// Km de cada par (los iniciales más los de sus carreras).
    public func shoeKilometers(shoes: [Shoe], assignments: [String: String]) -> [String: Double] {
        var km: [String: Double] = [:]
        for shoe in shoes { km[shoe.id] = shoe.startKm }
        for s in summaries {
            if let id = Self.shoeID(for: s, shoes: shoes, assignments: assignments) { km[id, default: 0] += s.distanceM / 1000 }
        }
        return km
    }
}
