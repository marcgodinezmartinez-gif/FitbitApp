import Foundation
import Testing
@testable import CoachKit
@testable import Insights
@testable import MetricsKit
@testable import Store

@Suite struct AIReportTests {
    let now = utc("2026-09-29T19:00")

    func setup(_ http: ScriptedHTTP, provider: AppSettings.CoachProvider = .anthropic, configure: (inout AppSettings) -> Void = { _ in })
        throws -> (CoachEngine, AppDatabase) {
        let db = try AppDatabase.inMemory()
        try db.updateSettings {
            $0.coachEnabled = true
            $0.coachProvider = provider
            $0.geminiPaidTierConfirmed = true
            configure(&$0)
        }
        let fixedNow = now
        let engine = CoachEngine(db: db, keys: { _ in "test-key" }, makeProvider: { id, key -> any LLMProvider in
            if id == "gemini" { return GeminiProvider(apiKey: key, http: http, retrySleep: { _ in }) }
            return AnthropicProvider(apiKey: key, http: http, retrySleep: { _ in })
        }, clock: { fixedNow })
        return (engine, db)
    }

    static let morningJSON = #"{"titulo":"Llegas con energía","resumen":"Has dormido 7 h 40 min y tu VFC está por encima de lo habitual.","carga_objetivo":"Entre 11 y 14: buen día para series.","hora_acostarse":"Acuéstate a las 23:05 para dormir 8 h."}"#

    @Test func morningSummaryUsesStructuredOutputWithoutTools() async throws {
        let http = ScriptedHTTP([ClaudeSSE.reply([ClaudeSSE.start(input: 1500), ClaudeSSE.text(0, [Self.morningJSON]),
                                                  ClaudeSSE.stop("end_turn", output: 200)])])
        let (engine, db) = try setup(http)
        let snapshot = makeSnapshot(now: now)
        let report = try await engine.morningSummary(snapshot: snapshot, bedtimeMinutes: 23 * 60 + 5)
        #expect(report.morning?.titulo == "Llegas con energía")
        #expect(report.kind == .morning && report.periodStart == snapshot.output.current!.date.isoString)
        #expect(report.costUSD > 0)

        let body = try #require(http.requestBodies.first)
        #expect(body["tools"] == nil)
        #expect(body["output_config"]?["format"]?["type"]?.stringValue == "json_schema")
        #expect(body["output_config"]?["effort"]?.stringValue == "low")
        let prompt = body["messages"]?[0]?["content"]?[0]?["text"]?.stringValue ?? ""
        #expect(prompt.contains("\"hora_acostarse\":\"23:05\""))
        #expect(prompt.contains("recuperacion"))

        // Guardado: la 2.ª vez no se llama a la IA.
        #expect(db.aiReport(.morning, periodStart: snapshot.output.current!.date) == report)
        let again = try await engine.morningSummary(snapshot: snapshot, bedtimeMinutes: 23 * 60 + 5)
        #expect(again == report)
        #expect(http.requestCount == 1)
        // El gasto cuenta, pero no como pregunta.
        let spend = try db.coachSpend(fromDay: "2026-09-01")
        #expect(spend.questions == 0 && spend.costUSD == report.costUSD)
    }

    @Test func weeklyNarrativeWithGemini() async throws {
        let json = #"{"resumen":"Semana sólida.","logros":["5 noches de más de 7 h","3 carreras","VFC estable"," ","Extra"],"mejoras":["Acuéstate antes el domingo","Estira 10 min","Menos cafeína por la tarde"],"comparacion":"Mejor que la anterior."}"#
        let escaped = JSONValue.string(json).serialized()
        let http = ScriptedHTTP([GeminiSSE.reply([
            #"{"candidates":[{"content":{"role":"model","parts":[{"text":\#(escaped)}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":900,"candidatesTokenCount":150},"modelVersion":"gemini-3.8-flash"}"#,
        ])])
        let (engine, db) = try setup(http, provider: .gemini)
        let snapshot = makeSnapshot(now: now)
        let monday = WeeklyPlanner.weekStart(of: snapshot.today).adding(days: -7)
        let report = try await engine.weeklyNarrative(snapshot: snapshot, weekStart: monday, plan: nil)
        let w = try #require(report.weekly)
        #expect(w.logros == ["5 noches de más de 7 h", "3 carreras", "VFC estable"])
        #expect(w.mejoras.count == 3)
        #expect(report.provider == "gemini")
        let body = try #require(http.requestBodies.first)
        #expect(body["generationConfig"]?["responseMimeType"]?.stringValue == "application/json")
        #expect(body["tools"] == nil)
        #expect(db.aiReport(.weekly, periodStart: monday)?.weekly == w)
    }

    @Test func invalidOrUnsafeResponsesAreNotSaved() async throws {
        let http = ScriptedHTTP([
            ClaudeSSE.reply([ClaudeSSE.start(), ClaudeSSE.text(0, ["{\"titulo\":\"Hola\"}"]), ClaudeSSE.stop("end_turn")]),
            ClaudeSSE.reply([ClaudeSSE.start(), ClaudeSSE.text(0, [Self.morningJSON.replacingOccurrences(of: "Llegas con energía", with: "Tienes una infección")]),
                             ClaudeSSE.stop("end_turn")]),
        ])
        let (engine, db) = try setup(http)
        let snapshot = makeSnapshot(now: now)
        await #expect(throws: ReportError.invalidResponse) {
            _ = try await engine.morningSummary(snapshot: snapshot, bedtimeMinutes: nil)
        }
        await #expect(throws: ReportError.invalidResponse) {
            _ = try await engine.morningSummary(snapshot: snapshot, bedtimeMinutes: nil)
        }
        #expect(db.aiReport(.morning, periodStart: snapshot.output.current!.date) == nil)
    }

    @Test func respectsSettings() async throws {
        let http = ScriptedHTTP([])
        let snapshot = makeSnapshot(now: now)
        let (off, _) = try setup(http) { $0.coachEnabled = false }
        await #expect(throws: CoachError.disabled) { _ = try await off.morningSummary(snapshot: snapshot, bedtimeMinutes: nil) }
        let (edu, _) = try setup(http) { $0.coachMode = .educational }
        await #expect(throws: ReportError.self) { _ = try await edu.morningSummary(snapshot: snapshot, bedtimeMinutes: nil) }
        let (broke, db) = try setup(http) { $0.coachMonthlyBudgetUSD = 1 }
        try db.addCoachSpend(day: snapshot.today.isoString, questions: 0, costUSD: 2)
        await #expect(throws: CoachError.budgetReached(1)) { _ = try await broke.morningSummary(snapshot: snapshot, bedtimeMinutes: nil) }
        #expect(http.requestCount == 0)
    }
}
