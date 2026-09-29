import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CoachKit

@Suite struct JSONValueTests {
    @Test func roundTripKeepsKeyOrderAndNumberLiterals() throws {
        let raw = #"{"z":1,"a":[1.50,-2e3,true,null],"m":{"y":"x","b":"é\n\"q\""},"big":12345678901234567890}"#
        let v = try JSONValue.parse(raw)
        #expect(v.serialized() == #"{"z":1,"a":[1.50,-2e3,true,null],"m":{"y":"x","b":"é\n\"q\""},"big":12345678901234567890}"#)
        #expect(v["a"]?[0]?.doubleValue == 1.5)
        #expect(v["m"]?["b"]?.stringValue == "é\n\"q\"")
        #expect(v.objectValue?.map(\.key) == ["z", "a", "m", "big"])
    }

    @Test func surrogatePairsAndErrors() throws {
        #expect(try JSONValue.parse(#""🏃""#).stringValue == "🏃")
        #expect(throws: JSONParseError.self) { try JSONValue.parse(#"{"a":}"#) }
        #expect(throws: JSONParseError.self) { try JSONValue.parse(#"[1,2"#) }
        #expect(throws: JSONParseError.self) { try JSONValue.parse(#"{"a":1} x"#) }
    }

    @Test func settingReplacesInPlaceAndAppends() {
        let v: JSONValue = ["a": 1, "b": 2]
        #expect(v.setting("a", 3).serialized() == #"{"a":3,"b":2}"#)
        #expect(v.setting("c", "x").serialized() == #"{"a":1,"b":2,"c":"x"}"#)
        #expect(v.setting("a", nil).serialized() == #"{"b":2}"#)
        #expect(JSONValue.from(3.0).serialized() == "3")
        #expect(JSONValue.rounded(2.345, 2).serialized() == "2.35" || JSONValue.rounded(2.345, 2).serialized() == "2.34")
        #expect(JSONValue.from(Double.nan) == .null)
    }

    @Test func controlCharactersAreEscaped() {
        #expect(JSONValue.string("a\u{01}b\tc").serialized() == #""a\u0001b\tc""#)
    }
}

@Suite struct AnthropicProviderTests {
    let tools = [CoachToolDefinition(name: "get_today_overview", description: "Hoy",
                                     inputSchema: ["type": "object", "properties": .object([]), "additionalProperties": false])]

    func request(history: [NativeTurn], schema: JSONValue? = nil, model: String = "claude-opus-5-5") -> LLMRequest {
        LLMRequest(model: model, system: "Sistema", tools: tools, history: history, effort: "medium", maxTokens: 16_000, responseSchema: schema)
    }

    @Test func requestFollowsOpus55Rules() throws {
        let p = AnthropicProvider(apiKey: "sk-test")
        let req = p.urlRequest(request(history: [p.userTurn(text: "Hola")]))
        #expect(req.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(req.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(req.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let betas = req.value(forHTTPHeaderField: "anthropic-beta") ?? ""
        #expect(betas.contains("server-side-fallback-2026-07-01"))
        #expect(betas.contains("thinking-binding-controls-2026-08-01"))
        let body = try JSONValue.parse(req.httpBody!)
        #expect(body["model"]?.stringValue == "claude-opus-5-5")
        #expect(body["stream"]?.boolValue == true)
        // Razonamiento adaptativo (nunca «disabled» ni presupuesto) y esfuerzo explícito.
        #expect(body["thinking"]?["type"]?.stringValue == "adaptive")
        #expect(body["thinking"]?["budget_tokens"] == nil)
        #expect(body["thinking"]?["block_binding"]?["prefix_mismatch_behavior"]?.stringValue == "drop_block")
        #expect(body["output_config"]?["effort"]?.stringValue == "medium")
        #expect(body["fallbacks"]?.stringValue == "default")
        // Sin muestreo, sin tool_choice forzado.
        #expect(body["temperature"] == nil && body["top_p"] == nil && body["tool_choice"] == nil)
        // Caché: punto fijo en el sistema y automático en la conversación.
        #expect(body["system"]?[0]?["cache_control"]?["type"]?.stringValue == "ephemeral")
        #expect(body["cache_control"]?["type"]?.stringValue == "ephemeral")
        #expect(body["tools"]?[0]?["eager_input_streaming"]?.boolValue == true)
        // El mismo contenido produce los mismos bytes.
        #expect(p.body(request(history: [p.userTurn(text: "Hola")])).serialized() == body.serialized())
    }

    @Test func olderModelsDoNotGetNewParameters() throws {
        let p = AnthropicProvider(apiKey: "k")
        let body = p.body(request(history: [p.userTurn(text: "Hola")], model: "claude-haiku-4-5"))
        #expect(body["thinking"] == nil && body["output_config"] == nil && body["fallbacks"] == nil)
        #expect(p.headers(for: "claude-haiku-4-5")["anthropic-beta"] == nil)
    }

    @Test func structuredOutputGoesInOutputConfig() {
        let p = AnthropicProvider(apiKey: "k")
        let schema: JSONValue = ["type": "object", "properties": ["a": ["type": "string"]], "required": ["a"], "additionalProperties": false]
        let body = p.body(request(history: [p.userTurn(text: "x")], schema: schema))
        #expect(body["output_config"]?["format"]?["type"]?.stringValue == "json_schema")
        #expect(body["output_config"]?["format"]?["schema"] == schema)
        #expect(body["output_config"]?["effort"]?.stringValue == "medium")
    }

    @Test func parsesThinkingTextAndToolUse() async throws {
        let http = ScriptedHTTP([ClaudeSSE.reply([
            ClaudeSSE.start(input: 120, cacheRead: 3000, cacheWrite: 10),
            ClaudeSSE.thinking(0, signature: "sig-abc"),
            ClaudeSSE.text(1, ["Voy a ", "mirar tu día."]),
            ClaudeSSE.toolUse(2, id: "toolu_1", name: "get_day_detail", inputChunks: [#"{"date":"#, #""2026-09-28"}"#]),
            ClaudeSSE.stop("tool_use", output: 80),
        ])])
        let p = AnthropicProvider(apiKey: "k", http: http)
        var deltas: [String] = []
        var sawThinking = false
        var response: LLMResponse?
        for try await e in p.stream(request(history: [p.userTurn(text: "Hola")])) {
            switch e {
            case .textDelta(let t): deltas.append(t)
            case .thinking: sawThinking = true
            case .completed(let r): response = r
            default: break
            }
        }
        let r = try #require(response)
        #expect(sawThinking)
        #expect(deltas.joined() == "Voy a mirar tu día.")
        #expect(r.text == "Voy a mirar tu día.")
        #expect(r.stop == .toolUse)
        #expect(r.toolCalls.count == 1)
        #expect(r.toolCalls[0].input?["date"]?.stringValue == "2026-09-28")
        #expect(r.usage == TokenUsage(inputTokens: 120, outputTokens: 80, cacheReadTokens: 3000, cacheWriteTokens: 10))
        // El bloque de razonamiento se conserva con su firma (vacío pero presente) y en su sitio.
        let blocks = try #require(r.turn.content.arrayValue)
        #expect(blocks.map { $0["type"]?.stringValue } == ["thinking", "text", "tool_use"])
        #expect(blocks[0]["signature"]?.stringValue == "sig-abc")
        #expect(blocks[0]["thinking"]?.stringValue == "")
        #expect(blocks[2]["input"]?.serialized() == #"{"date":"2026-09-28"}"#)
        // Los resultados de herramientas vuelven como tool_result.
        let results = p.toolResultsTurn([ToolOutput(callID: "toolu_1", name: "get_day_detail", content: ["ok": true])])
        #expect(results.content.serialized() == #"[{"type":"tool_result","tool_use_id":"toolu_1","content":"{\"ok\":true}"}]"#)
    }

    @Test func refusalIsReportedWithCategory() async throws {
        let http = ScriptedHTTP([ClaudeSSE.reply([ClaudeSSE.start(), ClaudeSSE.text(0, ["Parcial"]),
                                                  ClaudeSSE.stop("refusal", details: #"{"category":"bio","explanation":null}"#)])])
        let r = try await AnthropicProvider(apiKey: "k", http: http).complete(request(history: []))
        #expect(r.stop == .refusal(category: "bio"))
    }

    @Test func fallbackTurnDropsReasoningBeforeTheBoundary() {
        let content: [JSONValue] = [
            ["type": "thinking", "thinking": "", "signature": "s1"],
            ["type": "text", "text": "Parte "],
            ["type": "tool_use", "id": "t0", "name": "x", "input": .object([])],
            ["type": "fallback", "from": ["model": "claude-opus-5-5"], "to": ["model": "claude-opus-5"]],
            ["type": "thinking", "thinking": "", "signature": "s2"],
            ["type": "text", "text": "final"],
        ]
        let kept = AnthropicStreamParser.sanitizeFallback(content).map { $0["type"]?.stringValue ?? "" }
        #expect(kept == ["text", "fallback", "thinking", "text"])
    }

    @Test func invalidToolJSONIsNotExecuted() async throws {
        let http = ScriptedHTTP([ClaudeSSE.reply([ClaudeSSE.start(), ClaudeSSE.toolUse(0, id: "t1", name: "get_journal",
                                                                                       inputChunks: [#"{"start_date": "2026-09-01", "#]),
                                                  ClaudeSSE.stop("tool_use")])])
        let r = try await AnthropicProvider(apiKey: "k", http: http).complete(request(history: []))
        #expect(r.toolCalls.first?.input == nil)
        #expect(r.turn.content[0]?["input"]?.serialized() == "{}")
    }

    @Test func httpErrorsAreMappedAndOverloadIsRetriedOnce() async throws {
        let unauthorized = ScriptedHTTP([.init(status: 401, lines: [#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#])])
        await #expect(throws: LLMError.invalidKey("invalid x-api-key")) {
            _ = try await AnthropicProvider(apiKey: "k", http: unauthorized).complete(request(history: []))
        }
        let flaky = ScriptedHTTP([.init(status: 529, lines: [#"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#]),
                                  ClaudeSSE.reply([ClaudeSSE.start(), ClaudeSSE.text(0, ["Hola"]), ClaudeSSE.stop("end_turn")])])
        let r = try await AnthropicProvider(apiKey: "k", http: flaky, retrySleep: { _ in }).complete(request(history: []))
        #expect(r.text == "Hola")
        #expect(flaky.requestCount == 2)
    }

    @Test func midStreamErrorEventThrows() async throws {
        let http = ScriptedHTTP([ClaudeSSE.reply([ClaudeSSE.start(), ClaudeSSE.text(0, ["Ho"]),
                                                  ClaudeSSE.event("error", #"{"type":"error","error":{"type":"invalid_request_error","message":"mal"}}"#)])])
        await #expect(throws: LLMError.badRequest("mal")) {
            _ = try await AnthropicProvider(apiKey: "k", http: http, retrySleep: { _ in }).complete(request(history: []))
        }
    }

    @Test func truncatedStreamIsAnError() async throws {
        let http = ScriptedHTTP([ClaudeSSE.reply([ClaudeSSE.start(), ClaudeSSE.text(0, ["Ho"])])])
        await #expect(throws: LLMError.self) {
            _ = try await AnthropicProvider(apiKey: "k", http: http).complete(request(history: []))
        }
    }

    @Test func testConnectionUsesModelsEndpoint() async throws {
        let http = ScriptedHTTP([.init(status: 200, lines: [#"{"id":"claude-opus-5-5"}"#])])
        try await AnthropicProvider(apiKey: "k", http: http).testConnection(model: "claude-opus-5-5")
        #expect(http.requests.first?.url?.path == "/v1/models/claude-opus-5-5")
        #expect(http.requests.first?.httpMethod == "GET")
    }
}

@Suite struct GeminiProviderTests {
    let tools = [
        CoachToolDefinition(name: "get_today_overview", description: "Hoy",
                            inputSchema: ["type": "object", "properties": .object([]), "additionalProperties": false]),
        CoachToolDefinition(name: "get_day_detail", description: "Día",
                            inputSchema: ["type": "object", "properties": ["date": ["type": "string"]], "required": ["date"],
                                          "additionalProperties": false]),
    ]

    @Test func requestShape() throws {
        let p = GeminiProvider(apiKey: "g-key")
        let r = LLMRequest(model: "gemini-3.8-flash", system: "Sistema", tools: tools, history: [p.userTurn(text: "Hola")], effort: "medium")
        let req = p.urlRequest(r)
        #expect(req.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:streamGenerateContent?alt=sse")
        #expect(req.value(forHTTPHeaderField: "x-goog-api-key") == "g-key")
        let body = try JSONValue.parse(req.httpBody!)
        #expect(body["systemInstruction"]?["parts"]?[0]?["text"]?.stringValue == "Sistema")
        #expect(body["contents"]?[0]?["role"]?.stringValue == "user")
        let decls = try #require(body["tools"]?[0]?["functionDeclarations"]?.arrayValue)
        #expect(decls.count == 2)
        #expect(decls[0]["parameters"] == nil)   // sin parámetros
        #expect(decls[1]["parameters"]?["additionalProperties"] == nil)
        #expect(body["generationConfig"]?["thinkingConfig"]?["thinkingLevel"]?.stringValue == "medium")
        #expect(body["toolConfig"]?["functionCallingConfig"]?["mode"]?.stringValue == "AUTO")
    }

    @Test func schemaIsSanitizedForGemini() throws {
        let schema = try JSONValue.parse(#"{"type":"object","additionalProperties":false,"properties":{"d":{"anyOf":[{"type":"number"},{"type":"null"}]},"t":{"type":["string","null"]}},"required":["d"]}"#)
        let s = GeminiProvider.sanitize(schema: schema)
        #expect(s.serialized() == #"{"type":"object","properties":{"d":{"type":"number","nullable":true},"t":{"type":"string","nullable":true}},"required":["d"]}"#)
    }

    @Test func parsesChunksKeepingSignatures() async throws {
        let http = ScriptedHTTP([GeminiSSE.reply([
            #"{"candidates":[{"content":{"role":"model","parts":[{"text":"Voy a "}]}}],"modelVersion":"gemini-3.8-flash"}"#,
            #"{"candidates":[{"content":{"role":"model","parts":[{"text":"mirar."}]}}]}"#,
            #"{"candidates":[{"content":{"role":"model","parts":[{"functionCall":{"name":"get_day_detail","args":{"date":"2026-09-28"}},"thoughtSignature":"SIG1"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":1200,"cachedContentTokenCount":1000,"candidatesTokenCount":40,"thoughtsTokenCount":60}}"#,
        ])])
        let p = GeminiProvider(apiKey: "k", http: http)
        let r = try await p.complete(LLMRequest(model: "gemini-3.8-flash", system: "S", tools: tools, history: [p.userTurn(text: "Hola")]))
        #expect(r.text == "Voy a mirar.")
        #expect(r.stop == .toolUse)
        #expect(r.toolCalls.first?.name == "get_day_detail")
        #expect(r.toolCalls.first?.id.hasPrefix(GeminiStreamParser.localIDPrefix) == true)
        #expect(r.usage == TokenUsage(inputTokens: 200, outputTokens: 100, cacheReadTokens: 1000, cacheWriteTokens: 0))
        #expect(r.turn.content.serialized()
            == #"{"role":"model","parts":[{"text":"Voy a mirar."},{"functionCall":{"name":"get_day_detail","args":{"date":"2026-09-28"}},"thoughtSignature":"SIG1"}]}"#)
        // Sin id real del modelo, la respuesta de la función no lleva id.
        let results = p.toolResultsTurn([ToolOutput(callID: r.toolCalls[0].id, name: "get_day_detail", content: ["ok": true])])
        #expect(results.content.serialized() == #"{"role":"user","parts":[{"functionResponse":{"name":"get_day_detail","response":{"result":{"ok":true}}}}]}"#)
    }

    @Test func signatureInEmptyFinalChunkIsKept() async throws {
        let http = ScriptedHTTP([GeminiSSE.reply([
            #"{"candidates":[{"content":{"role":"model","parts":[{"text":"Hola"}]}}]}"#,
            #"{"candidates":[{"content":{"role":"model","parts":[{"text":"","thoughtSignature":"S2"}]},"finishReason":"STOP"}]}"#,
        ])])
        let r = try await GeminiProvider(apiKey: "k", http: http).complete(LLMRequest(model: "gemini-3.8-flash", system: "S", tools: [], history: []))
        #expect(r.turn.content["parts"]?.serialized() == #"[{"text":"Hola","thoughtSignature":"S2"}]"#)
        #expect(r.stop == .endTurn)
    }

    @Test func blockedPromptIsARefusal() async throws {
        let http = ScriptedHTTP([GeminiSSE.reply([#"{"promptFeedback":{"blockReason":"SAFETY"}}"#])])
        let r = try await GeminiProvider(apiKey: "k", http: http).complete(LLMRequest(model: "gemini-3.8-flash", system: "S", tools: [], history: []))
        #expect(r.stop == .refusal(category: "SAFETY"))
    }

    @Test func invalidKeyIsDetected() async throws {
        let http = ScriptedHTTP([.init(status: 400, lines: [#"{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT"}}"#])])
        await #expect(throws: LLMError.self) {
            try await GeminiProvider(apiKey: "k", http: http).testConnection(model: "gemini-3.8-flash")
        }
    }
}

@Suite struct PricingAndSafetyTests {
    @Test func estimatesMatchDocument() {
        let opus = ModelCatalog.estimatedCostPerQuestion(provider: "anthropic", model: "claude-opus-5-5")
        #expect(abs(opus - 0.0884) < 0.001)
        let flash = ModelCatalog.estimatedCostPerQuestion(provider: "gemini", model: "gemini-3.8-flash", on: utc("2026-10-01T10:00"))
        #expect(abs(flash - 0.0159) < 0.001)
        let flash2027 = ModelCatalog.estimatedCostPerQuestion(provider: "gemini", model: "gemini-3.8-flash", on: utc("2027-01-02T10:00"))
        #expect(abs(flash2027 - 2 * flash) < 0.0001)
        #expect(ModelCatalog.cost(TokenUsage(inputTokens: 1_000_000), provider: "anthropic", model: "claude-sonnet-5-5") == 2)
    }

    @Test func urgencyFilter() {
        #expect(CoachSafety.isUrgent("Tengo un DOLOR EN EL PECHO muy fuerte"))
        #expect(CoachSafety.isUrgent("a veces pienso en quitarme la vida"))
        #expect(CoachSafety.isUrgent("Me desmayé después de correr"))
        #expect(!CoachSafety.isUrgent("¿Me acuesto antes esta noche?"))
        #expect(!CoachSafety.isUrgent("¿El ejercicio ayuda a dormir mejor?"))
    }

    @Test func prohibitedExpressionsWithNegationAllowed() {
        #expect(CoachSafety.violations(in: "Esto podría ser una arritmia.") == ["arritmia"])
        #expect(CoachSafety.violations(in: "Puede deberse a una infección.") == ["infeccion"])
        #expect(CoachSafety.violations(in: "No puedo hacer diagnósticos. Consulta a un profesional.").isEmpty)
        #expect(CoachSafety.violations(in: "La pulsera no detecta la apnea del sueño.").isEmpty)
        #expect(CoachSafety.violations(in: "Duerme 8 horas y baja la carga hoy.").isEmpty)
    }
}
