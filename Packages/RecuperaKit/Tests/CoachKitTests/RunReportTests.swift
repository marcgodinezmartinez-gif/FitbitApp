import Foundation
import Testing
@testable import CoachKit
@testable import Insights
@testable import MetricsKit
@testable import RunKit
@testable import Store

@Suite struct RunReportTests {
    let now = utc("2026-09-29T19:00")

    static let runJSON = #"{"titular":"Rodaje sólido con buena subida","resumen":"Rodaje aeróbico de 6 km a 5:00 /km.","puntos_fuertes":["Parciales muy regulares","Cadencia de 172 ppm",""],"a_mejorar":["Deriva de FC del 7 %: hidrátate antes"],"proxima_sesion":"Mañana, 40 min suaves en zona 2."}"#

    /// Carrera de 6 km a 5:00/km con ruta GPS.
    func run() -> (FusedActivity, RunAnalysis) {
        let start = utc("2026-09-29T07:00")
        let end = start.addingTimeInterval(1800)
        let perDegree = 111_320 * cos(40.0 * .pi / 180)
        let route = stride(from: 0.0, through: 1800, by: 2).map { t in
            RoutePoint(time: start.addingTimeInterval(t), latitude: 40.4153, longitude: -3.6845 + t * 1000 / 300 / perDegree, altitude: 650,
                       horizontalAccuracy: 5)
        }
        let hr = stride(from: 0.0, through: 1800, by: 5).map { HRSample(time: start.addingTimeInterval($0), bpm: 150, source: .appleHealth) }
        let watch = ActivitySession(source: .appleHealth, sourceRecordID: "w9", kind: .running, start: start, end: end, utcOffsetSeconds: 7200,
                                    distanceM: 6000, hasRoute: true)
        let activity = FusedActivity(id: watch.id, members: [watch], start: start, end: end, kind: .running, isLeftover: false,
                                     hrSource: .appleHealth, sourcesDisagree: false, agreement: nil)
        let input = RunInput(activity: activity, route: route, hrWatch: hr, zones: StrainCalculator.zones(hrMax: 190, restingRef: 55))
        return (activity, RunAnalyzer.analyze(input))
    }

    @Test func runAnalysisSendsFactsWithoutCoordinatesAndIsSaved() async throws {
        let http = ScriptedHTTP([ClaudeSSE.reply([ClaudeSSE.start(input: 2000), ClaudeSSE.text(0, [Self.runJSON]),
                                                  ClaudeSSE.stop("end_turn", output: 300)])])
        let db = try AppDatabase.inMemory()
        try db.updateSettings { $0.coachEnabled = true }
        let fixedNow = now
        let engine = CoachEngine(db: db, keys: { _ in "test-key" }, makeProvider: { _, key -> any LLMProvider in
            AnthropicProvider(apiKey: key, http: http, retrySleep: { _ in })
        }, clock: { fixedNow })
        let (activity, analysis) = run()
        let history = RunHistory(summaries: [RunLibrary.summary(activity, analysis: analysis, route: [])])
        let facts = RunFacts.make(run: activity, analysis: analysis, history: history, today: LocalDate(year: 2026, month: 9, day: 29),
                                  recoveryScore: 72, rpe: 5, notes: "Piernas cargadas")
        let report = try await engine.runAnalysis(runID: activity.id, facts: facts, snapshot: makeSnapshot(now: now))
        #expect(report.kind == .run && report.periodStart == activity.id)
        // Listas limpias: sin el punto fuerte vacío.
        #expect(report.run?.puntosFuertes == ["Parciales muy regulares", "Cadencia de 172 ppm"])

        let body = try #require(http.requestBodies.first)
        let prompt = body["messages"]?[0]?["content"]?[0]?["text"]?.stringValue ?? ""
        #expect(prompt.contains("\"parciales\"") && prompt.contains("\"ritmo_medio\":\"5:00 /km\"") && prompt.contains("\"recuperacion_de_ese_dia\":72"))
        #expect(prompt.contains("\"mejores_marcas\"") && prompt.contains("notas_del_usuario_como_dato"))
        // Nunca coordenadas.
        #expect(!prompt.contains("40.415") && !prompt.contains("-3.68") && !prompt.contains("\"lat") && !prompt.contains("latitud"))
        // Guardado: la 2.ª vez no se llama a la IA.
        #expect(db.aiRunReport(activityID: activity.id) == report)
        let again = try await engine.runAnalysis(runID: activity.id, facts: facts, snapshot: makeSnapshot(now: now))
        #expect(again == report && http.requestCount == 1)
    }
}
