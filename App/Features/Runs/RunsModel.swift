import Foundation
import Observation
import MetricsKit
import Insights
import Store
import RunKit
import CoachKit

/// Carrera ya analizada: el análisis, lo que se leyó de la base de datos y la serie segundo a segundo (mapa y GPX).
struct LoadedRun: @unchecked Sendable {
    var analysis: RunAnalysis
    var input: RunInput
    var series: RunSeries
}

/// Datos del apartado «Correr» (doc. 18): resúmenes de todas las carreras, historial, zapatillas y análisis de cada una.
@Observable
final class RunsModel {
    var summaries: [RunSummary] = []
    var history = RunHistory(summaries: [])
    var context = RunContext()
    var shoes: [Shoe] = []
    var assignments: [String: String] = [:]
    var vo2: [VO2MaxValue] = []
    var isLoading = false
    /// Carreras que fueron récord el día que se corrieron (para marcarlas en la lista).
    var recordIDs: Set<String> = []
    /// Riesgo de lesión: carga de todo el día (aguda frente a crónica) y picos de distancia.
    var risk: InjuryRisk?
    /// Carrera objetivo y plan de entrenamiento hacia ella (doc. 18 §7).
    var goal: GoalRace?
    var plan: TrainingPlan?
    /// Segmentos propios con tu mejor pasada y cuántas llevas (doc. 18 §8).
    var segments: [Segment] = []
    var segmentBests: [String: SegmentEffort] = [:]
    var segmentCounts: [String: Int] = [:]
    /// En el modo demostración, las pasadas se calculan al vuelo (no se guardan).
    @ObservationIgnored private var demoEfforts: [SegmentEffort] = []
    /// Todas las carreras (también las del historial completo), para abrir cualquiera.
    @ObservationIgnored private var runsByID: [String: FusedActivity] = [:]
    @ObservationIgnored private var loadedVersion = -1
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var refreshAgain = false

    var today: LocalDate { LocalDate(Date(), utcOffsetSeconds: TimeZone.current.secondsFromGMT()) }

    func summary(_ id: String) -> RunSummary? { summaries.first { $0.id == id } }

    func run(_ id: String) -> FusedActivity? { runsByID[id] }

    /// Recalcula lo que falte (en segundo plano) cuando cambian los datos. Si ya hay un cálculo en curso (la primera vez
    /// con años de historial puede tardar), se repite al terminar en vez de lanzar otro a la vez.
    @MainActor
    func refresh(model: AppModel, force: Bool = false) async {
        guard model.output != nil, force || loadedVersion != model.dataVersion else { return }
        if refreshing {
            refreshAgain = true
            return
        }
        refreshing = true
        defer { refreshing = false }
        repeat {
            refreshAgain = false
            guard let output = model.output else { return }
            loadedVersion = model.dataVersion
            isLoading = summaries.isEmpty
            let profile = model.displayProfile
            let demo = model.settings.demoMode
            let db = model.db
            let result: ([RunSummary], [FusedActivity]) = await Task.detached(priority: .userInitiated) {
                guard !demo, let db else { return (RunDemo.summaries(output: output, profile: profile), RunLibrary.runs(in: output)) }
                return (try? RunLibrary.refreshAll(db: db, output: output, profile: profile)) ?? ([], RunLibrary.runs(in: output))
            }.value
            summaries = result.0
            runsByID = Dictionary(result.1.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            history = RunHistory(summaries: result.0)
            recordIDs = history.recordRunIDs()
            context = history.context(today: today)
            let loads = Dictionary(output.cycles.map { ($0.date, $0.strain.loadRaw) }, uniquingKeysWith: +)
            risk = InjuryRisk.assess(dailyLoads: loads, runs: result.0, today: today)
            if !demo, let db {
                shoes = (try? db.shoes()) ?? []
                assignments = (try? db.shoeAssignments()) ?? [:]
                vo2 = (try? db.vo2maxValues()) ?? []
                goal = (try? db.readState(Self.goalKey, default: GoalState()))?.race
                plan = (try? db.readState(Self.planKey, default: PlanState()))?.plan
            } else {
                shoes = Self.demoShoes
                vo2 = model.demoVO2
                if goal == nil { goal = Self.demoGoal(today: today) }
                if plan == nil, let goal, let v = context.vdot {
                    plan = PlanBuilder.build(goal: goal, vdot: v, history: history, today: today, utcOffsetSeconds: offset,
                                             daysPerWeek: 4, longRunWeekday: 7)
                }
            }
            await refreshSegments(model: model, runs: result.1)
            isLoading = false
        } while refreshAgain
    }

    var offset: Int { TimeZone.current.secondsFromGMT() }

    // MARK: Carrera objetivo y plan

    static let goalKey = "goal_race"
    static let planKey = "training_plan"

    /// Envoltorios guardados en `app_state` (el estado se fusiona con los valores por defecto: no admite un opcional suelto).
    struct GoalState: Codable { var race: GoalRace? }
    struct PlanState: Codable { var plan: TrainingPlan? }

    /// Predicción para la carrera objetivo con tu VDOT, ajustada a su desnivel y al tiempo.
    var goalPrediction: RacePrediction? {
        guard let goal, let v = context.vdot else { return nil }
        return RacePredictor.predict(race: goal, vdot: v)
    }

    @MainActor
    func saveGoal(_ race: GoalRace?, model: AppModel) {
        goal = race
        if race == nil { plan = nil }
        guard !model.settings.demoMode, let db = model.db else { return }
        try? db.writeState(Self.goalKey, GoalState(race: race))
        if race == nil { try? db.writeState(Self.planKey, PlanState()) }
    }

    @MainActor
    func createPlan(daysPerWeek: Int, longRunWeekday: Int, model: AppModel) {
        guard let goal, let v = context.vdot ?? history.vdot(today: today)?.value else { return }
        let p = PlanBuilder.build(goal: goal, vdot: v, history: history, today: today, utcOffsetSeconds: offset,
                                  daysPerWeek: daysPerWeek, longRunWeekday: longRunWeekday)
        plan = p
        if !model.settings.demoMode { try? model.db?.writeState(Self.planKey, PlanState(plan: p)) }
    }

    @MainActor
    func deletePlan(model: AppModel) {
        plan = nil
        if !model.settings.demoMode { try? model.db?.writeState(Self.planKey, PlanState()) }
    }

    func status(of session: PlannedSession) -> SessionStatus { PlanBuilder.status(of: session, runs: summaries, today: today) }

    static func demoGoal(today: LocalDate) -> GoalRace {
        // Un 10K dentro de 10 semanas, con algo de desnivel y un día templado.
        let day = today.adding(days: 70 + (7 - today.isoWeekday))
        return GoalRace(name: "10K de ejemplo", date: day.startDate(utcOffsetSeconds: TimeZone.current.secondsFromGMT()).addingTimeInterval(9 * 3600),
                        distanceM: 10_000, elevationGainM: 60, elevationLossM: 60, temperatureC: 16, humidityPct: 65,
                        weatherSource: "ejemplo")
    }

    // MARK: Segmentos

    @MainActor
    private func refreshSegments(model: AppModel, runs: [FusedActivity]) async {
        let demo = model.settings.demoMode
        let db = model.db
        let list = summaries
        let byID = runsByID
        let output = model.output
        let profile = model.displayProfile
        let (segs, efforts): ([Segment], [SegmentEffort]) = await Task.detached(priority: .utility) {
            if !demo, let db {
                _ = try? SegmentLibrary.scan(db: db, summaries: list, runs: byID)
                let segs = (try? SegmentLibrary.segments(db: db)) ?? []
                return (segs, segs.flatMap { (try? SegmentLibrary.efforts(segmentID: $0.id, db: db)) ?? [] })
            }
            guard let output else { return ([], []) }
            return RunDemo.segments(output: output, profile: profile)
        }.value
        segments = segs
        demoEfforts = demo ? efforts : []
        var bests: [String: SegmentEffort] = [:]
        var counts: [String: Int] = [:]
        for e in efforts {
            counts[e.segmentID, default: 0] += 1
            if e.seconds < bests[e.segmentID]?.seconds ?? .infinity { bests[e.segmentID] = e }
        }
        segmentBests = bests
        segmentCounts = counts
    }

    @MainActor
    func efforts(segmentID: String, model: AppModel) -> [SegmentEffort] {
        if model.settings.demoMode { return demoEfforts.filter { $0.segmentID == segmentID }.sorted { $0.seconds < $1.seconds } }
        return (try? model.db.map { try SegmentLibrary.efforts(segmentID: segmentID, db: $0) }) ?? []
    }

    @MainActor
    func efforts(runID: String, model: AppModel) -> [SegmentEffort] {
        if model.settings.demoMode { return demoEfforts.filter { $0.runID == runID } }
        return (try? model.db.map { try SegmentLibrary.efforts(runID: runID, db: $0) }) ?? []
    }

    /// Crea un segmento con un tramo de la carrera y busca tus pasadas en todas las demás.
    @MainActor
    func createSegment(name: String, route: [RoutePoint], fromM: Double, toM: Double, runID: String, model: AppModel) async -> Segment? {
        guard let segment = SegmentMatcher.make(name: name, route: route, fromM: fromM, toM: toM, runID: runID) else { return nil }
        if model.settings.demoMode {
            segments.append(segment)
            return segment
        }
        guard let db = model.db else { return nil }
        try? db.saveSegment(segment, id: segment.id)
        await refreshSegments(model: model, runs: Array(runsByID.values))
        return segment
    }

    @MainActor
    func renameSegment(_ segment: Segment, to name: String, model: AppModel) {
        guard let i = segments.firstIndex(where: { $0.id == segment.id }) else { return }
        segments[i].name = name
        if !model.settings.demoMode { try? model.db?.saveSegment(segments[i], id: segment.id) }
    }

    @MainActor
    func deleteSegment(_ segment: Segment, model: AppModel) {
        segments.removeAll { $0.id == segment.id }
        segmentBests[segment.id] = nil
        segmentCounts[segment.id] = nil
        if !model.settings.demoMode { try? model.db?.deleteSegment(id: segment.id) }
    }

    /// Lee y analiza una carrera (con el contexto del historial: VDOT, umbral y potencia crítica).
    @MainActor
    func load(_ run: FusedActivity, model: AppModel) async -> LoadedRun? {
        guard let output = model.output else { return nil }
        let zones = RunLibrary.zones(for: run, output: output)
        let profile = model.displayProfile
        let demo = model.settings.demoMode
        let db = model.db
        let context = self.context
        return await Task.detached(priority: .userInitiated) { () -> LoadedRun? in
            let input: RunInput
            if !demo, let db {
                guard let read = try? RunLibrary.input(for: run, db: db, zones: zones, profile: profile) else { return nil }
                input = read
            } else {
                input = RunDemo.input(for: run, zones: zones, profile: profile)
            }
            let series = RunSeriesBuilder.build(input)
            return LoadedRun(analysis: RunAnalyzer.analyze(series: series, input: input, context: context), input: input, series: series)
        }.value
    }

    // MARK: Zapatillas

    @MainActor
    func saveShoes(_ list: [Shoe], model: AppModel) {
        var list = list
        // Solo un par predeterminado.
        if let firstDefault = list.firstIndex(where: \.isDefault) {
            for i in list.indices where i != firstDefault { list[i].isDefault = false }
        }
        shoes = list
        if !model.settings.demoMode { try? model.db?.saveShoes(list) }
    }

    @MainActor
    func assign(shoeID: String?, to run: FusedActivity, model: AppModel) {
        assignments[run.id] = shoeID
        guard !model.settings.demoMode, let db = model.db else { return }
        for member in run.members {
            var a = (try? db.annotation(for: member.id)) ?? ActivityAnnotation(activityID: member.id)
            a.shoeID = shoeID
            try? db.saveAnnotation(a)
        }
    }

    func shoeID(for summary: RunSummary) -> String? {
        RunHistory.shoeID(for: summary, shoes: shoes, assignments: assignments)
    }

    static let demoShoes: [Shoe] = [
        Shoe(id: "demo-1", name: "Pegasus 41", startKm: 180, isDefault: true, addedAt: Date().addingTimeInterval(-200 * 86_400)),
        Shoe(id: "demo-2", name: "Vaporfly 3", startKm: 90, limitKm: 400, addedAt: Date().addingTimeInterval(-200 * 86_400)),
    ]

    // MARK: Análisis con IA

    @MainActor
    func savedReport(for runID: String, model: AppModel) -> AIReport? {
        model.settings.demoMode ? nil : model.db?.aiRunReport(activityID: runID)
    }

    @MainActor
    func writeReport(run: FusedActivity, analysis: RunAnalysis, model: AppModel, force: Bool) async throws -> AIReport {
        if model.settings.demoMode { return Self.demoReport(run: run, analysis: analysis) }
        guard let coach = model.coach, let snapshot = model.coachSnapshot() else { throw CoachError.disabled }
        let now = Date()
        let recovery = model.output?.cycles.last { $0.cycle.contains(run.start, now: now) }?.recovery.score
        let facts = RunFacts.make(run: run, analysis: analysis, history: history, today: today, recoveryScore: recovery,
                                  rpe: run.rpe, notes: run.notes)
        return try await coach.runAnalysis(runID: run.id, facts: facts, snapshot: snapshot, force: force)
    }

    /// Texto de ejemplo del modo demostración (no llama a ninguna IA).
    static func demoReport(run: FusedActivity, analysis r: RunAnalysis) -> AIReport {
        let pace = r.avgPace.map { Format.pace(secondsPerKm: $0) } ?? "–"
        let decoupling = r.decouplingPct.map { "\(Format.decimal($0)) %" } ?? "bajo"
        let narrative = RunNarrative(
            titular: "Rodaje controlado con buen reparto del esfuerzo",
            resumen: "Has corrido \(Format.km(r.distanceM)) a \(pace) /km de media, casi todo en zonas 2 y 3. "
                + "El desacoplamiento (\(decoupling)) indica que tu base aeróbica aguanta bien este ritmo.",
            puntosFuertes: ["Parciales regulares, sin cebarte al principio",
                            "Cadencia de \(Int((r.avgCadence ?? 170).rounded())) ppm con poco rebote"],
            aMejorar: ["En los repechos sube la cadencia y acorta la zancada para no disparar la FC"],
            proximaSesion: "Mañana, 40 minutos suaves en zona 2; el jueves, 5 × 1 km a ritmo de umbral.")
        return AIReport(kind: .run, periodStart: run.id, createdAt: Date(), provider: "demo", model: "ejemplo", costUSD: 0, run: narrative)
    }
}
