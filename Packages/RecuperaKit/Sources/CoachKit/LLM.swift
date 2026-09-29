import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Contrato común (doc. 06 §3)

/// Herramienta del Coach escrita una sola vez en JSON Schema; cada proveedor la traduce a su formato.
public struct CoachToolDefinition: Sendable, Hashable {
    public var name: String
    public var description: String
    public var inputSchema: JSONValue

    public init(name: String, description: String, inputSchema: JSONValue) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }

    public var json: JSONValue { ["name": .string(name), "description": .string(description), "input_schema": inputSchema] }

    public init?(json: JSONValue) {
        guard let name = json["name"]?.stringValue, let schema = json["input_schema"] else { return nil }
        self.init(name: name, description: json["description"]?.stringValue ?? "", inputSchema: schema)
    }
}

/// Llamada a una herramienta pedida por el modelo.
public struct ToolCall: Sendable, Hashable {
    public var id: String
    public var name: String
    /// Entrada ya analizada; `nil` si el modelo generó JSON no válido (se le devuelve un error).
    public var input: JSONValue?
    public var rawInput: String

    public init(id: String, name: String, input: JSONValue?, rawInput: String) {
        self.id = id
        self.name = name
        self.input = input
        self.rawInput = rawInput
    }
}

/// Resultado de ejecutar una herramienta en el iPhone.
public struct ToolOutput: Sendable, Hashable {
    public var callID: String
    public var name: String
    public var content: JSONValue
    public var isError: Bool

    public init(callID: String, name: String, content: JSONValue, isError: Bool = false) {
        self.callID = callID
        self.name = name
        self.content = content
        self.isError = isError
    }
}

/// Uso de *tokens* normalizado: `inputTokens` es solo la parte sin caché y `outputTokens` incluye el razonamiento.
public struct TokenUsage: Sendable, Hashable, Codable {
    public var inputTokens = 0
    public var outputTokens = 0
    public var cacheReadTokens = 0
    public var cacheWriteTokens = 0

    public init(inputTokens: Int = 0, outputTokens: Int = 0, cacheReadTokens: Int = 0, cacheWriteTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
    }

    public static func + (a: TokenUsage, b: TokenUsage) -> TokenUsage {
        TokenUsage(inputTokens: a.inputTokens + b.inputTokens, outputTokens: a.outputTokens + b.outputTokens,
                   cacheReadTokens: a.cacheReadTokens + b.cacheReadTokens, cacheWriteTokens: a.cacheWriteTokens + b.cacheWriteTokens)
    }
}

public enum StopKind: Sendable, Hashable {
    case endTurn
    case toolUse
    case maxTokens
    /// El proveedor declinó responder (`stop_reason: "refusal"` en Claude; bloqueo de seguridad en Gemini).
    case refusal(category: String?)
    case other(String)
}

/// Turno en el formato propio del proveedor, que se guarda y se reenvía sin modificar.
public struct NativeTurn: Sendable, Hashable {
    public enum Role: String, Sendable, Codable { case user, assistant, tool }

    public var role: Role
    public var content: JSONValue

    public init(role: Role, content: JSONValue) {
        self.role = role
        self.content = content
    }
}

public struct LLMRequest: Sendable {
    public var model: String
    public var system: String
    public var tools: [CoachToolDefinition]
    public var history: [NativeTurn]
    public var effort: String
    public var maxTokens: Int
    /// Esquema JSON de la respuesta (salida estructurada); `nil` para texto libre.
    public var responseSchema: JSONValue?

    public init(model: String, system: String, tools: [CoachToolDefinition], history: [NativeTurn], effort: String = "medium",
                maxTokens: Int = 16_000, responseSchema: JSONValue? = nil) {
        self.model = model
        self.system = system
        self.tools = tools
        self.history = history
        self.effort = effort
        self.maxTokens = maxTokens
        self.responseSchema = responseSchema
    }
}

public struct LLMResponse: Sendable {
    /// Turno del asistente listo para guardar y reenviar.
    public var turn: NativeTurn
    public var text: String
    public var toolCalls: [ToolCall]
    public var stop: StopKind
    public var usage: TokenUsage
    /// Modelo que respondió de verdad (puede ser el de reserva de Claude).
    public var model: String
    public var usedFallback: Bool

    public init(turn: NativeTurn, text: String, toolCalls: [ToolCall], stop: StopKind, usage: TokenUsage, model: String,
                usedFallback: Bool = false) {
        self.turn = turn
        self.text = text
        self.toolCalls = toolCalls
        self.stop = stop
        self.usage = usage
        self.model = model
        self.usedFallback = usedFallback
    }
}

public enum LLMStreamEvent: Sendable {
    case started(model: String)
    case thinking
    case textDelta(String)
    case toolCallStarted(name: String)
    case completed(LLMResponse)
}

public enum LLMError: Error, Sendable, Equatable, LocalizedError {
    case missingKey
    case invalidKey(String?)
    case rateLimited(retryAfter: Double?)
    case overloaded
    case badRequest(String)
    case server(status: Int, message: String?)
    case network(String)
    case protocolError(String)

    public var errorDescription: String? {
        switch self {
        case .missingKey: return "Falta la clave de API del proveedor del Coach."
        case .invalidKey(let m): return "La clave de API no es válida o no tiene permiso\(m.map { " (\($0))" } ?? "")."
        case .rateLimited: return "El proveedor ha limitado las peticiones. Prueba de nuevo en un momento."
        case .overloaded: return "El proveedor está saturado. Prueba de nuevo en unos minutos."
        case .badRequest(let m): return "El proveedor rechazó la petición: \(m)"
        case .server(let s, let m): return "Error \(s) del proveedor\(m.map { ": \($0)" } ?? "")."
        case .network(let m): return "Sin conexión con el proveedor (\(m))."
        case .protocolError(let m): return "Respuesta inesperada del proveedor (\(m))."
        }
    }

    /// Errores transitorios que merece la pena reintentar si aún no ha llegado nada.
    var isRetryable: Bool {
        switch self {
        case .rateLimited(let after): return (after ?? 2) <= 20
        case .overloaded, .network: return true
        case .server(let s, _): return s >= 500
        default: return false
        }
    }
}

/// Un proveedor de IA (Claude o Gemini) detrás de la misma interfaz.
public protocol LLMProvider: Sendable {
    /// `anthropic` o `gemini` (coincide con `AppSettings.CoachProvider`).
    var id: String { get }
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error>
    func userTurn(text: String) -> NativeTurn
    func toolResultsTurn(_ outputs: [ToolOutput]) -> NativeTurn
    /// Llamadas a herramientas de un turno del asistente ya guardado (para reparar un historial interrumpido).
    func toolCalls(in turn: NativeTurn) -> [ToolCall]
    /// «Probar conexión» (RF-COA-21).
    func testConnection(model: String) async throws
}

extension LLMProvider {
    /// Consume el *stream* y devuelve la respuesta final (útil en tareas sin interfaz y en pruebas).
    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        for try await event in stream(request) {
            if case .completed(let r) = event { return r }
        }
        throw LLMError.protocolError("la respuesta terminó sin completarse")
    }
}

// MARK: - Transporte HTTP con *streaming*

/// Transporte inyectable: `URLSession` en la app, respuestas grabadas en las pruebas.
public protocol StreamingHTTP: Sendable {
    /// Envía la petición y devuelve la respuesta y sus líneas a medida que llegan.
    func lines(_ request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<String, Error>)
    func data(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionStreamingHTTP: StreamingHTTP {
    let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func lines(_ request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<String, Error>) {
        #if canImport(Darwin)
        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw LLMError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw LLMError.protocolError("respuesta no HTTP") }
        let stream = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    // `lines` omite las líneas vacías: el analizador SSE trata cada `data:` por separado.
                    for try await line in bytes.lines { continuation.yield(line) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: LLMError.network(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return (http, stream)
        #else
        let (data, http) = try await self.data(request)
        let text = String(decoding: data, as: UTF8.self)
        let stream = AsyncThrowingStream<String, Error> { continuation in
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                continuation.yield(line.hasSuffix("\r") ? String(line.dropLast()) : String(line))
            }
            continuation.finish()
        }
        return (http, stream)
        #endif
    }

    public func data(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: LLMError.network(error.localizedDescription))
                } else if let http = response as? HTTPURLResponse {
                    continuation.resume(returning: (data ?? Data(), http))
                } else {
                    continuation.resume(throwing: LLMError.protocolError("respuesta no HTTP"))
                }
            }
            task.resume()
        }
    }
}

enum SSE {
    /// Contenido de una línea `data:` (cada evento de ambas APIs cabe en una sola línea).
    static func payload(_ line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        var rest = line.dropFirst(5)
        if rest.first == " " { rest = rest.dropFirst() }
        return String(rest)
    }

    /// Lee el cuerpo completo de una respuesta de error.
    static func collect(_ lines: AsyncThrowingStream<String, Error>) async -> String {
        var out: [String] = []
        do {
            for try await line in lines {
                out.append(line)
                if out.count > 400 { break }
            }
        } catch {}
        return out.joined(separator: "\n")
    }
}

/// Reintenta una vez los errores transitorios si todavía no se ha emitido nada.
func withRetry(attempts: Int = 2, sleep: @Sendable (Double) async -> Void = { s in try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) },
               _ body: () async throws -> Void, emitted: () -> Bool) async throws {
    var attempt = 0
    while true {
        do {
            try await body()
            return
        } catch let error as LLMError where error.isRetryable && !emitted() && attempt + 1 < attempts {
            attempt += 1
            if case .rateLimited(let after) = error { await sleep(max(1, after ?? 2)) } else { await sleep(2) }
        }
    }
}
