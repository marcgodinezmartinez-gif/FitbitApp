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
    @ObservationIgnored private var loadedVersion = -1

    var today: LocalDate { LocalDate(Date(), utcOffsetSeconds: TimeZone.current.secondsFromGMT()) }

    func summary(_ id: String) -> RunSummary? { summaries.first { $0.id == id } }

    /// Recalcula lo que falte (en segundo plano) cuando cambian los datos.
    @MainActor
    func refresh(model: AppModel, force: Bool = false) async {
        guard let output = model.output, force || loadedVersion != model.dataVersion else { return }
        loadedVersion = model.dataVersion
        isLoading = summaries.isEmpty
        let profile = model.displayProfile
        let demo = model.settings.demoMode
        let db = model.db
        let result: [RunSummary] = await Task.detached(priority: .userInitiated) {
            guard !demo, let db else { return RunDemo.summaries(output: output, profile: profile) }
            return (try? RunLibrary.refresh(db: db, output: output, profile: profile)) ?? []
        }.value
        summaries = result
        history = RunHistory(summaries: result)
        context = history.context(today: today)
        if !demo, let db {
            shoes = (try? db.shoes()) ?? []
            assignments = (try? db.shoeAssignments()) ?? []
            vo2 = (try? db.vo2maxValues()) ?? []
        } else {
            shoes = Self.demoShoes
            vo2 = []
        }
        isLoading = false
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
