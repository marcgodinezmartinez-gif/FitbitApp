import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Gemini por HTTPS directo (`streamGenerateContent` con SSE, cabecera `x-goog-api-key`). Doc. 06 §5.
///
/// Google considera `generateContent` una API heredada desde que publicó la *Interactions API* (2026), pero sigue con
/// soporte completo y es la que mejor encaja con un historial guardado en el iPhone. Las partes del modelo se guardan
/// tal cual llegan, con sus firmas de pensamiento (`thoughtSignature`), que Gemini 3 exige recibir de vuelta en las
/// conversaciones con herramientas.
public struct GeminiProvider: LLMProvider {
    public let id = "gemini"

    let apiKey: String
    let http: StreamingHTTP
    let baseURL: URL
    let retrySleep: @Sendable (Double) async -> Void

    public init(apiKey: String, http: StreamingHTTP = URLSessionStreamingHTTP(),
                baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta/")!,
                retrySleep: @escaping @Sendable (Double) async -> Void = { s in try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }) {
        self.apiKey = apiKey
        self.http = http
        self.baseURL = baseURL
        self.retrySleep = retrySleep
    }

    /// Nivel de razonamiento de Gemini 3 a partir del esfuerzo elegido (los modelos *flash* admiten `medium`).
    static func thinkingLevel(effort: String, model: String) -> String {
        switch effort {
        case "low": return "low"
        case "medium": return model.contains("flash") ? "medium" : "high"
        default: return "high"
        }
    }

    /// El subconjunto de esquemas de Gemini no admite `additionalProperties` ni uniones con `null`: se traducen a `nullable`.
    static func sanitize(schema: JSONValue) -> JSONValue {
        switch schema {
        case .object(let members):
            var out: [JSONValue.Member] = []
            var nullable = false
            for m in members {
                switch m.key {
                case "additionalProperties", "$schema", "strict":
                    continue
                case "anyOf":
                    let options = m.value.arrayValue ?? []
                    let nonNull = options.filter { $0["type"]?.stringValue != "null" }
                    if nonNull.count == 1, options.count == 2, let inner = sanitize(schema: nonNull[0]).objectValue {
                        out.append(contentsOf: inner)
                        nullable = true
                    } else {
                        out.append(.init("anyOf", .array(options.map(sanitize(schema:)))))
                    }
                case "type":
                    if let types = m.value.arrayValue {
                        let nonNull = types.filter { $0.stringValue != "null" }
                        out.append(.init("type", nonNull.first ?? "string"))
                        if nonNull.count < types.count { nullable = true }
                    } else {
                        out.append(m)
                    }
                case "properties":
                    out.append(.init("properties", .object((m.value.objectValue ?? []).map { .init($0.key, sanitize(schema: $0.value)) })))
                case "items":
                    out.append(.init("items", sanitize(schema: m.value)))
                default:
                    out.append(m)
                }
            }
            if nullable { out.append(.init("nullable", true)) }
            return .object(out)
        default:
            return schema
        }
    }

    // MARK: Petición

    func body(_ r: LLMRequest) -> JSONValue {
        var m: [JSONValue.Member] = [
            .init("systemInstruction", ["parts": [["text": .string(r.system)]]]),
            .init("contents", .array(r.history.map(\.content))),
        ]
        // Con salida estructurada no se declaran herramientas: los datos van en el propio mensaje.
        if !r.tools.isEmpty && r.responseSchema == nil {
            m.append(.init("tools", [["functionDeclarations": .array(r.tools.map { t in
                var decl: JSONValue = ["name": .string(t.name), "description": .string(t.description)]
                if !(t.inputSchema["properties"]?.objectValue ?? []).isEmpty {
                    decl = decl.setting("parameters", Self.sanitize(schema: t.inputSchema))
                }
                return decl
            })]]))
            m.append(.init("toolConfig", ["functionCallingConfig": ["mode": "AUTO"]]))
        }
        var config: [JSONValue.Member] = [
            .init("maxOutputTokens", .from(r.maxTokens)),
            .init("thinkingConfig", ["thinkingLevel": .string(Self.thinkingLevel(effort: r.effort, model: r.model))]),
        ]
        if let schema = r.responseSchema {
            config.append(.init("responseMimeType", "application/json"))
            config.append(.init("responseSchema", Self.sanitize(schema: schema)))
        }
        m.append(.init("generationConfig", .object(config)))
        return .object(m)
    }

    func urlRequest(_ r: LLMRequest) -> URLRequest {
        let path = "models/\(r.model):streamGenerateContent"
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "alt", value: "sse")]
        var req = URLRequest(url: components.url!)
        req.httpMethod = "POST"
        req.timeoutInterval = 300
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = body(r).data
        return req
    }

    // MARK: Streaming

    public func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        let provider = self
        return AsyncThrowingStream { continuation in
            let task = Task {
                var emitted = false
                do {
                    try await withRetry(sleep: provider.retrySleep, {
                        try await provider.runOnce(request) { event in
                            emitted = true
                            continuation.yield(event)
                        }
                    }, emitted: { emitted })
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func runOnce(_ request: LLMRequest, yield: (LLMStreamEvent) -> Void) async throws {
        let (response, lines) = try await http.lines(urlRequest(request))
        guard response.statusCode == 200 else {
            let body = await SSE.collect(lines)
            throw Self.error(status: response.statusCode, body: body, retryAfter: response.headerValue("retry-after"))
        }
        var parser = GeminiStreamParser(requestedModel: request.model)
        yield(.started(model: request.model))
        for try await line in lines {
            try Task.checkCancellation()
            guard let payload = SSE.payload(line), !payload.isEmpty else { continue }
            let chunk: JSONValue
            do { chunk = try JSONValue.parse(payload) } catch { throw LLMError.protocolError("fragmento SSE no válido") }
            for e in try parser.handle(chunk) { yield(e) }
        }
        yield(.completed(try parser.finish()))
    }

    static func error(status: Int, body: String, retryAfter: String?) -> LLMError {
        let json = try? JSONValue.parse(body)
        // Con alt=sse el error puede llegar como lista de un elemento.
        let err = json?["error"] ?? json?[0]?["error"]
        let message = err?["message"]?.stringValue
        let statusText = err?["status"]?.stringValue ?? ""
        switch status {
        case 400 where (message ?? "").localizedCaseInsensitiveContains("api key"): return .invalidKey(message)
        case 401, 403: return .invalidKey(message)
        case 404: return .badRequest(message ?? "modelo no disponible para esta clave")
        case 429: return .rateLimited(retryAfter: retryAfter.flatMap(Double.init))
        case 503 where statusText == "UNAVAILABLE": return .overloaded
        case 400..<500: return .badRequest(message ?? "error \(status)")
        default: return .server(status: status, message: message)
        }
    }

    // MARK: Turnos

    public func userTurn(text: String) -> NativeTurn {
        NativeTurn(role: .user, content: ["role": "user", "parts": [["text": .string(text)]]])
    }

    public func toolResultsTurn(_ outputs: [ToolOutput]) -> NativeTurn {
        NativeTurn(role: .tool, content: ["role": "user", "parts": .array(outputs.map { o in
            var response: JSONValue = ["name": .string(o.name), "response": o.isError ? ["error": o.content] : ["result": o.content]]
            if !o.callID.hasPrefix(GeminiStreamParser.localIDPrefix) { response = response.setting("id", .string(o.callID)) }
            return ["functionResponse": response]
        })])
    }

    public func toolCalls(in turn: NativeTurn) -> [ToolCall] {
        GeminiStreamParser.calls(in: turn.content["parts"]?.arrayValue ?? [])
    }

    public func testConnection(model: String) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("models/\(model)"))
        req.httpMethod = "GET"
        req.timeoutInterval = 30
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let (data, response) = try await http.data(req)
        guard response.statusCode == 200 else {
            throw Self.error(status: response.statusCode, body: String(decoding: data, as: UTF8.self), retryAfter: nil)
        }
    }
}

// MARK: - Analizador de fragmentos

struct GeminiStreamParser {
    static let localIDPrefix = "local-call-"

    let requestedModel: String
    var parts: [JSONValue] = []
    var model: String
    var finishReason: String?
    var blockReason: String?
    var usage: JSONValue?
    var chunks = 0

    init(requestedModel: String) {
        self.requestedModel = requestedModel
        model = requestedModel
    }

    mutating func handle(_ chunk: JSONValue) throws -> [LLMStreamEvent] {
        chunks += 1
        if let err = chunk["error"] {
            throw LLMError.server(status: err["code"]?.intValue ?? 500, message: err["message"]?.stringValue)
        }
        if let v = chunk["modelVersion"]?.stringValue { model = v }
        if let u = chunk["usageMetadata"] { usage = u }
        if let b = chunk["promptFeedback"]?["blockReason"]?.stringValue { blockReason = b }
        guard let candidate = chunk["candidates"]?[0] else { return [] }
        if let f = candidate["finishReason"]?.stringValue { finishReason = f }
        var out: [LLMStreamEvent] = []
        for part in candidate["content"]?["parts"]?.arrayValue ?? [] {
            if let call = part["functionCall"] {
                parts.append(part)
                out.append(.toolCallStarted(name: call["name"]?.stringValue ?? ""))
            } else if part["thought"]?.boolValue == true {
                continue // resúmenes de pensamiento (no se piden)
            } else if let text = part["text"]?.stringValue {
                append(text: text, signature: part["thoughtSignature"])
                if !text.isEmpty { out.append(.textDelta(text)) }
            } else if let signature = part["thoughtSignature"] {
                append(text: "", signature: signature)
            } else {
                parts.append(part)
            }
        }
        return out
    }

    /// Une los trozos de texto consecutivos y conserva la firma en la parte donde llegó.
    mutating func append(text: String, signature: JSONValue?) {
        if let last = parts.last, let lastText = last["text"]?.stringValue, last["thoughtSignature"] == nil, last.objectValue?.count == 1 {
            var merged: JSONValue = ["text": .string(lastText + text)]
            if let signature { merged = merged.setting("thoughtSignature", signature) }
            parts[parts.count - 1] = merged
        } else {
            var part: JSONValue = ["text": .string(text)]
            if let signature { part = part.setting("thoughtSignature", signature) }
            parts.append(part)
        }
    }

    static func calls(in parts: [JSONValue]) -> [ToolCall] {
        var n = 0
        return parts.compactMap { part in
            guard let call = part["functionCall"], let name = call["name"]?.stringValue else { return nil }
            n += 1
            let args = call["args"] ?? .object([])
            let id = call["id"]?.stringValue ?? "\(localIDPrefix)\(n)"
            return ToolCall(id: id, name: name, input: args.objectValue != nil ? args : nil, rawInput: args.serialized())
        }
    }

    func finish() throws -> LLMResponse {
        if let blockReason {
            return LLMResponse(turn: NativeTurn(role: .assistant, content: ["role": "model", "parts": []]), text: "", toolCalls: [],
                               stop: .refusal(category: blockReason), usage: tokens, model: model)
        }
        guard chunks > 0 else { throw LLMError.protocolError("respuesta vacía") }
        let calls = Self.calls(in: parts)
        let text = parts.compactMap { $0["functionCall"] == nil ? $0["text"]?.stringValue : nil }.joined()
        let stop: StopKind
        switch finishReason {
        case "STOP", nil: stop = calls.isEmpty ? .endTurn : .toolUse
        case "MAX_TOKENS": stop = .maxTokens
        case "SAFETY", "RECITATION", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII", "IMAGE_SAFETY", "LANGUAGE":
            stop = .refusal(category: finishReason)
        case let other?: stop = .other(other)
        }
        // Una parte de modelo vacía no es válida al reenviarla: se deja al menos un texto vacío.
        let finalParts = parts.isEmpty ? [["text": ""]] as [JSONValue] : parts
        return LLMResponse(turn: NativeTurn(role: .assistant, content: ["role": "model", "parts": .array(finalParts)]), text: text,
                           toolCalls: calls, stop: stop, usage: tokens, model: model)
    }

    var tokens: TokenUsage {
        guard let u = usage else { return TokenUsage() }
        let prompt = u["promptTokenCount"]?.intValue ?? 0
        let cached = u["cachedContentTokenCount"]?.intValue ?? 0
        return TokenUsage(inputTokens: max(0, prompt - cached),
                          outputTokens: (u["candidatesTokenCount"]?.intValue ?? 0) + (u["thoughtsTokenCount"]?.intValue ?? 0),
                          cacheReadTokens: cached, cacheWriteTokens: 0)
    }
}
