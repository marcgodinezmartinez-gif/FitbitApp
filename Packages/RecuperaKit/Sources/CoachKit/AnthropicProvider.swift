import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Claude por HTTPS directo a la Messages API (no hay SDK oficial para Swift). Doc. 06 §5.
///
/// - Razonamiento adaptativo siempre activo en Claude Opus 5.5: no se envía `thinking: disabled` ni presupuestos;
///   la profundidad se regula con `output_config.effort`.
/// - Los bloques de razonamiento (aunque lleguen vacíos) se guardan y se reenvían intactos. Por si algún día cambiara el
///   prefijo de un hilo, se pide `prefix_mismatch_behavior: "drop_block"`: el bloque afectado se descarta en vez de dar 400.
/// - *Fallback* del servidor activado (`fallbacks: "default"`): si Claude declina por sus clasificadores, responde el
///   modelo de reserva recomendado y la etiqueta de la respuesta lo indica.
/// - Caché de *prompt*: punto fijo al final del sistema (herramientas + sistema) y automático para la conversación.
public struct AnthropicProvider: LLMProvider {
    public let id = "anthropic"
    public static let apiVersion = "2023-06-01"
    public static let fallbackBeta = "server-side-fallback-2026-07-01"
    public static let thinkingBindingBeta = "thinking-binding-controls-2026-08-01"

    let apiKey: String
    let http: StreamingHTTP
    let baseURL: URL
    let retrySleep: @Sendable (Double) async -> Void

    public init(apiKey: String, http: StreamingHTTP = URLSessionStreamingHTTP(),
                baseURL: URL = URL(string: "https://api.anthropic.com/v1/")!,
                retrySleep: @escaping @Sendable (Double) async -> Void = { s in try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }) {
        self.apiKey = apiKey
        self.http = http
        self.baseURL = baseURL
        self.retrySleep = retrySleep
    }

    // MARK: Capacidades por modelo

    /// Modelos con razonamiento adaptativo y `output_config.effort`.
    static func supportsEffort(_ model: String) -> Bool {
        ["claude-opus-5", "claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6", "claude-sonnet-5", "claude-sonnet-4-6",
         "claude-fable", "claude-mythos"].contains { model.hasPrefix($0) }
    }

    /// Modelos con razonamiento preservado (bloques ligados al hilo): se pide descartar en vez de fallar.
    static func bindsThinking(_ model: String) -> Bool {
        ["claude-opus-5-5", "claude-sonnet-5-5", "claude-fable-5-1", "claude-mythos-5-1"].contains { model.hasPrefix($0) }
    }

    /// Modelos con clasificadores de seguridad y *fallback* del servidor.
    static func supportsFallbacks(_ model: String) -> Bool {
        ["claude-opus-5", "claude-sonnet-5-5", "claude-fable-5-1"].contains { model.hasPrefix($0) }
    }

    // MARK: Petición

    func headers(for model: String) -> [String: String] {
        var h = ["x-api-key": apiKey, "anthropic-version": Self.apiVersion, "content-type": "application/json"]
        var betas: [String] = []
        if Self.supportsFallbacks(model) { betas.append(Self.fallbackBeta) }
        if Self.bindsThinking(model) { betas.append(Self.thinkingBindingBeta) }
        if !betas.isEmpty { h["anthropic-beta"] = betas.joined(separator: ",") }
        return h
    }

    static func toolJSON(_ t: CoachToolDefinition) -> JSONValue {
        // `eager_input_streaming`: la entrada llega sin búfer; se valida en el iPhone antes de ejecutar nada.
        ["name": .string(t.name), "description": .string(t.description), "input_schema": t.inputSchema, "eager_input_streaming": true]
    }

    func body(_ r: LLMRequest) -> JSONValue {
        var m: [JSONValue.Member] = [
            .init("model", .string(r.model)),
            .init("max_tokens", .from(r.maxTokens)),
            .init("stream", true),
            .init("system", [["type": "text", "text": .string(r.system), "cache_control": ["type": "ephemeral"]]]),
        ]
        if !r.tools.isEmpty { m.append(.init("tools", .array(r.tools.map(Self.toolJSON)))) }
        m.append(.init("messages", .array(r.history.map { turn in
            ["role": turn.role == .assistant ? "assistant" : "user", "content": turn.content]
        })))
        if Self.bindsThinking(r.model) {
            m.append(.init("thinking", ["type": "adaptive", "block_binding": ["prefix_mismatch_behavior": "drop_block"]]))
        }
        var output: [JSONValue.Member] = []
        if Self.supportsEffort(r.model) { output.append(.init("effort", .string(r.effort))) }
        if let schema = r.responseSchema { output.append(.init("format", ["type": "json_schema", "schema": schema])) }
        if !output.isEmpty { m.append(.init("output_config", .object(output))) }
        if Self.supportsFallbacks(r.model) { m.append(.init("fallbacks", "default")) }
        m.append(.init("cache_control", ["type": "ephemeral"]))
        return .object(m)
    }

    func urlRequest(_ r: LLMRequest) -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent("messages"))
        req.httpMethod = "POST"
        req.timeoutInterval = 300
        for (k, v) in headers(for: r.model) { req.setValue(v, forHTTPHeaderField: k) }
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
        var parser = AnthropicStreamParser()
        for try await line in lines {
            try Task.checkCancellation()
            guard let payload = SSE.payload(line), !payload.isEmpty else { continue }
            let event: JSONValue
            do { event = try JSONValue.parse(payload) } catch { throw LLMError.protocolError("evento SSE no válido") }
            for e in try parser.handle(event) { yield(e) }
            if parser.finished { break }
        }
        yield(.completed(try parser.finish()))
    }

    static func error(status: Int, body: String, retryAfter: String?) -> LLMError {
        let json = try? JSONValue.parse(body)
        let message = json?["error"]?["message"]?.stringValue
        switch status {
        case 401, 403: return .invalidKey(message)
        case 404: return .badRequest(message ?? "modelo no disponible para esta clave")
        case 429: return .rateLimited(retryAfter: retryAfter.flatMap(Double.init))
        case 529: return .overloaded
        case 400..<500: return .badRequest(message ?? "error \(status)")
        default: return .server(status: status, message: message)
        }
    }

    // MARK: Turnos

    public func userTurn(text: String) -> NativeTurn {
        NativeTurn(role: .user, content: [["type": "text", "text": .string(text)]])
    }

    public func toolResultsTurn(_ outputs: [ToolOutput]) -> NativeTurn {
        NativeTurn(role: .tool, content: .array(outputs.map { o in
            var block: JSONValue = ["type": "tool_result", "tool_use_id": .string(o.callID), "content": .string(o.content.serialized())]
            if o.isError { block = block.setting("is_error", true) }
            return block
        }))
    }

    public func toolCalls(in turn: NativeTurn) -> [ToolCall] {
        (turn.content.arrayValue ?? []).compactMap { b in
            guard b["type"]?.stringValue == "tool_use", let id = b["id"]?.stringValue, let name = b["name"]?.stringValue else { return nil }
            let input = b["input"] ?? .object([])
            return ToolCall(id: id, name: name, input: input, rawInput: input.serialized())
        }
    }

    public func testConnection(model: String) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("models").appendingPathComponent(model))
        req.httpMethod = "GET"
        req.timeoutInterval = 30
        for (k, v) in headers(for: model) where k != "anthropic-beta" { req.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await http.data(req)
        guard response.statusCode == 200 else {
            throw Self.error(status: response.statusCode, body: String(decoding: data, as: UTF8.self), retryAfter: nil)
        }
    }
}

// MARK: - Analizador de eventos SSE

/// Reconstruye el mensaje a partir de los eventos (`message_start`, `content_block_*`, `message_delta`, `message_stop`).
struct AnthropicStreamParser {
    struct Block {
        var start: JSONValue
        var text: String
        var thinking: String
        var signature: String
        var partialJSON = ""

        init(start: JSONValue) {
            self.start = start
            text = start["text"]?.stringValue ?? ""
            thinking = start["thinking"]?.stringValue ?? ""
            signature = start["signature"]?.stringValue ?? ""
        }

        var type: String { start["type"]?.stringValue ?? "" }
    }

    var blocks: [Int: Block] = [:]
    var order: [Int] = []
    var model = ""
    var usage: JSONValue = .object([])
    var stopReason: String?
    var stopDetails: JSONValue?
    var finished = false

    mutating func handle(_ event: JSONValue) throws -> [LLMStreamEvent] {
        switch event["type"]?.stringValue {
        case "message_start":
            let message = event["message"] ?? .object([])
            model = message["model"]?.stringValue ?? model
            if let u = message["usage"] { merge(usage: u) }
            return [.started(model: model)]
        case "content_block_start":
            guard let index = event["index"]?.intValue, let start = event["content_block"] else { return [] }
            let block = Block(start: start)
            if blocks[index] == nil { order.append(index) }
            blocks[index] = block
            switch block.type {
            case "thinking", "redacted_thinking": return [.thinking]
            case "tool_use": return [.toolCallStarted(name: start["name"]?.stringValue ?? "")]
            case "text": return block.text.isEmpty ? [] : [.textDelta(block.text)]
            default: return []
            }
        case "content_block_delta":
            guard let index = event["index"]?.intValue, var block = blocks[index], let delta = event["delta"] else { return [] }
            var out: [LLMStreamEvent] = []
            switch delta["type"]?.stringValue {
            case "text_delta":
                let t = delta["text"]?.stringValue ?? ""
                block.text += t
                if !t.isEmpty { out.append(.textDelta(t)) }
            case "thinking_delta": block.thinking += delta["thinking"]?.stringValue ?? ""
            case "signature_delta": block.signature += delta["signature"]?.stringValue ?? ""
            case "input_json_delta": block.partialJSON += delta["partial_json"]?.stringValue ?? ""
            default: break
            }
            blocks[index] = block
            return out
        case "message_delta":
            if let d = event["delta"] {
                if let r = d["stop_reason"]?.stringValue { stopReason = r }
                if let s = d["stop_details"], !s.isNull { stopDetails = s }
            }
            if let s = event["stop_details"], !s.isNull { stopDetails = s }
            if let u = event["usage"] { merge(usage: u) }
            return []
        case "message_stop":
            finished = true
            return []
        case "error":
            let e = event["error"]
            let message = e?["message"]?.stringValue ?? "error del proveedor"
            switch e?["type"]?.stringValue {
            case "overloaded_error": throw LLMError.overloaded
            case "rate_limit_error": throw LLMError.rateLimited(retryAfter: nil)
            case "invalid_request_error": throw LLMError.badRequest(message)
            case "authentication_error", "permission_error": throw LLMError.invalidKey(message)
            default: throw LLMError.server(status: 500, message: message)
            }
        default:
            return [] // ping y eventos nuevos
        }
    }

    mutating func merge(usage u: JSONValue) {
        for m in u.objectValue ?? [] where !m.value.isNull { usage = usage.setting(m.key, m.value) }
    }

    static func tokens(_ u: JSONValue) -> TokenUsage {
        TokenUsage(inputTokens: u["input_tokens"]?.intValue ?? 0, outputTokens: u["output_tokens"]?.intValue ?? 0,
                   cacheReadTokens: u["cache_read_input_tokens"]?.intValue ?? 0,
                   cacheWriteTokens: u["cache_creation_input_tokens"]?.intValue ?? 0)
    }

    func finish() throws -> LLMResponse {
        guard finished else { throw LLMError.protocolError("la respuesta se cortó antes de terminar") }
        var content: [JSONValue] = []
        var invalidInputs: [String: String] = [:]
        for index in order {
            guard let b = blocks[index] else { continue }
            switch b.type {
            case "text":
                content.append(b.start.setting("text", .string(b.text)))
            case "thinking":
                content.append(b.start.setting("thinking", .string(b.thinking)).setting("signature", .string(b.signature)))
            case "tool_use":
                var input = b.start["input"] ?? .object([])
                if !b.partialJSON.isEmpty {
                    if let parsed = try? JSONValue.parse(b.partialJSON), parsed.objectValue != nil {
                        input = parsed
                    } else {
                        input = .object([])
                        invalidInputs[b.start["id"]?.stringValue ?? ""] = b.partialJSON
                    }
                }
                content.append(b.start.setting("input", input))
            default:
                content.append(b.start)
            }
        }
        content = Self.sanitizeFallback(content)

        let calls: [ToolCall] = content.compactMap { b in
            guard b["type"]?.stringValue == "tool_use", let id = b["id"]?.stringValue, let name = b["name"]?.stringValue else { return nil }
            if let raw = invalidInputs[id] { return ToolCall(id: id, name: name, input: nil, rawInput: raw) }
            let input = b["input"] ?? .object([])
            return ToolCall(id: id, name: name, input: input, rawInput: input.serialized())
        }
        let text = content.filter { $0["type"]?.stringValue == "text" }.compactMap { $0["text"]?.stringValue }.joined()

        let stop: StopKind
        switch stopReason {
        case "end_turn", "stop_sequence", nil: stop = calls.isEmpty ? .endTurn : .toolUse
        case "tool_use": stop = .toolUse
        case "max_tokens", "model_context_window_exceeded": stop = .maxTokens
        case "refusal": stop = .refusal(category: stopDetails?["category"]?.stringValue)
        case let other?: stop = .other(other)
        }

        var total = Self.tokens(usage)
        var fellBack = content.contains { $0["type"]?.stringValue == "fallback" }
        if let iterations = usage["iterations"]?.arrayValue, !iterations.isEmpty {
            total = iterations.map(Self.tokens).reduce(TokenUsage(), +)
            if iterations.contains(where: { $0["type"]?.stringValue == "fallback_message" }) { fellBack = true }
        }
        return LLMResponse(turn: NativeTurn(role: .assistant, content: .array(content)), text: text, toolCalls: calls, stop: stop,
                           usage: total, model: model, usedFallback: fellBack)
    }

    /// Al reenviar un turno servido por el modelo de reserva se omiten el razonamiento y los `tool_use` anteriores al
    /// último bloque `fallback`; el texto y el propio bloque `fallback` se conservan en su sitio (doc. 06 §5).
    static func sanitizeFallback(_ content: [JSONValue]) -> [JSONValue] {
        guard let boundary = content.lastIndex(where: { $0["type"]?.stringValue == "fallback" }) else { return content }
        return content.enumerated().filter { i, b in
            i >= boundary || ["text", "fallback"].contains(b["type"]?.stringValue ?? "")
        }.map(\.element)
    }
}

extension HTTPURLResponse {
    /// Cabecera sin distinguir mayúsculas (igual en Darwin y en Linux).
    func headerValue(_ name: String) -> String? {
        for (k, v) in allHeaderFields {
            if let k = k as? String, k.caseInsensitiveCompare(name) == .orderedSame { return v as? String }
        }
        return nil
    }
}
