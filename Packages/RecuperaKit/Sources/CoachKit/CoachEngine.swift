import Foundation
import Insights
import MetricsKit
import Store

/// Pregunta al Coach. Sin `threadID` se abre un hilo nuevo con el proveedor y el modelo de Ajustes.
public struct CoachQuestion: Sendable {
    public var threadID: String?
    public var text: String
    /// Pantalla desde la que se abre el Coach (p. ej. «Sueño del 28/09»), RF-COA-17.
    public var screenContext: String?

    public init(threadID: String? = nil, text: String, screenContext: String? = nil) {
        self.threadID = threadID
        self.text = text
        self.screenContext = screenContext
    }
}

/// Eventos para la interfaz mientras el Coach responde.
public enum CoachEvent: Sendable {
    case threadReady(CoachThread)
    case userMessage(CoachMessageRecord)
    case started(model: String)
    case thinking
    case text(String)
    case tool(label: String)
    case proposal(GoalProposal)
    /// Se ha guardado un paso intermedio (llamadas a herramientas): recargar mensajes y vaciar el texto en curso.
    case stepSaved
    case assistantMessage(CoachMessageRecord)
    case notice(CoachMessageRecord)
}

public enum CoachError: Error, Equatable, LocalizedError {
    case disabled
    case missingKey(provider: String)
    case geminiNotConfirmed
    case dailyLimit(Int)
    case budgetReached(Double)
    case threadNotFound
    case noData
    case tooManySteps
    case provider(LLMError)

    public var errorDescription: String? {
        switch self {
        case .disabled: return "El Coach está desactivado. Actívalo en Ajustes › Coach."
        case .missingKey(let p): return "Falta la clave de API de \(p == "gemini" ? "Gemini" : "Claude"). Añádela en Ajustes › Coach."
        case .geminiNotConfirmed: return "Confirma en Ajustes que tu clave de Gemini es de un proyecto con facturación activada."
        case .dailyLimit(let n): return "Has llegado al límite de \(n) preguntas de hoy. Puedes cambiarlo en Ajustes › Coach."
        case .budgetReached(let usd): return "Has alcanzado el gasto máximo del mes (\(String(format: "%.2f", usd)) $). Puedes cambiarlo en Ajustes › Coach."
        case .threadNotFound: return "La conversación ya no existe."
        case .noData: return "No hay datos de ese día."
        case .tooManySteps: return "El Coach no ha conseguido terminar la respuesta. Prueba a reformular la pregunta."
        case .provider(let e): return e.errorDescription
        }
    }
}

/// Metadatos de cada mensaje para la interfaz (se guardan en `coach_message.meta_json`).
public struct CoachMessageMeta: Codable, Sendable, Hashable {
    public var kind: String?
    public var provider: String?
    public var model: String?
    public var usedFallback: Bool?
    public var dataUsed: [CoachDataRef]?
    public var proposal: GoalProposal?
    public var filtered: Bool?
    public var hidden: Bool?

    public init(kind: String? = nil, provider: String? = nil, model: String? = nil, usedFallback: Bool? = nil, dataUsed: [CoachDataRef]? = nil,
                proposal: GoalProposal? = nil, filtered: Bool? = nil, hidden: Bool? = nil) {
        self.kind = kind
        self.provider = provider
        self.model = model
        self.usedFallback = usedFallback
        self.dataUsed = dataUsed
        self.proposal = proposal
        self.filtered = filtered
        self.hidden = hidden
    }

    public static func decode(_ json: String?) -> CoachMessageMeta? {
        guard let json else { return nil }
        return try? JSONDecoder().decode(CoachMessageMeta.self, from: Data(json.utf8))
    }

    var json: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Sistema y herramientas congelados al crear un hilo.
struct CoachThreadContext {
    var mode: String
    var kind: String
    var system: String
    var tools: [CoachToolDefinition]

    var json: JSONValue {
        ["v": .from(CoachPrompts.version), "mode": .string(mode), "kind": .string(kind), "system": .string(system),
         "tools": .array(tools.map(\.json))]
    }

    init(mode: String, kind: String, system: String, tools: [CoachToolDefinition]) {
        self.mode = mode
        self.kind = kind
        self.system = system
        self.tools = tools
    }

    init?(json: String?) {
        guard let json, let v = try? JSONValue.parse(json), let system = v["system"]?.stringValue else { return nil }
        mode = v["mode"]?.stringValue ?? "personal"
        kind = v["kind"]?.stringValue ?? "chat"
        self.system = system
        tools = (v["tools"]?.arrayValue ?? []).compactMap(CoachToolDefinition.init(json:))
    }
}

/// Resultado de «Analizar mi día».
public struct DayAnalysisOutcome: Sendable {
    public var analysis: DayAnalysis
    public var isAI: Bool
    public var threadID: String?
    public var stored: StoredDayAnalysis
    /// Por qué se muestra la versión determinista, si es el caso.
    public var note: String?
}

/// Motor del Coach, independiente del proveedor (doc. 06 §3): hilos, límites, filtros, bucle de herramientas y guardado.
public actor CoachEngine {
    public static let maxSteps = 8

    let db: AppDatabase
    let keys: @Sendable (String) -> String?
    let makeProvider: @Sendable (String, String) -> any LLMProvider
    let clock: @Sendable () -> Date

    public init(db: AppDatabase, keys: @escaping @Sendable (String) -> String?,
                makeProvider: @escaping @Sendable (String, String) -> any LLMProvider = CoachEngine.defaultProvider,
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.db = db
        self.keys = keys
        self.makeProvider = makeProvider
        self.clock = clock
    }

    public static func defaultProvider(_ id: String, _ key: String) -> any LLMProvider {
        id == "gemini" ? GeminiProvider(apiKey: key) : AnthropicProvider(apiKey: key)
    }

    /// «Probar conexión» con una clave y un modelo (RF-COA-21).
    public func testConnection(provider: String, model: String, key: String) async throws {
        do {
            try await makeProvider(provider, key).testConnection(model: model)
        } catch let e as LLMError {
            throw CoachError.provider(e)
        }
    }

    /// Guarda en la memoria una propuesta aceptada por el usuario (RF-COA-10).
    public func accept(_ proposal: GoalProposal) throws {
        let key = String(proposal.text.prefix(40)).lowercased().replacingOccurrences(of: " ", with: "_")
        try db.saveMemory(CoachMemoryItem(category: proposal.category, key: key, value: proposal.text, updatedAt: clock()))
    }

    // MARK: Preguntas

    public nonisolated func ask(_ question: CoachQuestion, snapshot: CoachDataSnapshot) -> AsyncThrowingStream<CoachEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(question, snapshot: snapshot) { continuation.yield($0) }
                    continuation.finish()
                } catch let e as LLMError {
                    continuation.finish(throwing: CoachError.provider(e))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func run(_ q: CoachQuestion, snapshot: CoachDataSnapshot, emit: @escaping @Sendable (CoachEvent) -> Void) async throws {
        let settings = try db.settings()
        guard settings.coachEnabled else { throw CoachError.disabled }
        let text = q.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let now = clock()

        // 1 · Filtro de urgencias: respuesta fija, sin llamar a ningún proveedor.
        if CoachSafety.isUrgent(text) {
            let thread = try q.threadID.flatMap { try db.thread(id: $0) } ?? newThread(title: text, settings: settings, snapshot: snapshot, kind: "chat")
            emit(.threadReady(thread))
            let user = CoachMessageRecord(threadID: thread.id, role: "local_user", model: nil, contentJSON: "null", displayText: text, createdAt: now)
            try db.appendMessage(user)
            emit(.userMessage(user))
            let notice = CoachMessageRecord(threadID: thread.id, role: "notice", model: nil, contentJSON: "null",
                                            displayText: CoachSafety.urgencyResponse, createdAt: now.addingTimeInterval(0.001),
                                            metaJSON: CoachMessageMeta(kind: "urgency").json)
            try db.appendMessage(notice)
            emit(.notice(notice))
            return
        }

        // 2 · Límites de preguntas y gasto.
        try checkLimits(settings: settings, snapshot: snapshot)

        // 3 · Hilo, proveedor y clave.
        let thread: CoachThread
        if let id = q.threadID {
            guard let t = try db.thread(id: id) else { throw CoachError.threadNotFound }
            thread = t
        } else {
            thread = try newThread(title: text, settings: settings, snapshot: snapshot, kind: "chat")
        }
        emit(.threadReady(thread))
        let provider = try providerFor(thread, settings: settings)
        guard let context = CoachThreadContext(json: thread.contextJSON) else { throw CoachError.threadNotFound }

        // 4 · Pregunta del usuario con su contexto de fecha y pantalla.
        let header = CoachPrompts.questionHeader(now: now, utcOffsetSeconds: snapshot.utcOffsetSeconds, screen: q.screenContext)
        let turn = provider.userTurn(text: header + "\n\n" + text)
        let user = CoachMessageRecord(threadID: thread.id, role: "user", model: nil, contentJSON: turn.content.serialized(), displayText: text,
                                      createdAt: now)
        try db.appendMessage(user)
        try db.addCoachSpend(day: snapshot.today.isoString, questions: 1, costUSD: 0)
        emit(.userMessage(user))

        // 5 · Bucle de herramientas hasta la respuesta final.
        _ = try await converse(thread: thread, context: context, provider: provider, settings: settings, snapshot: snapshot,
                               schema: nil, kind: "chat", emit: emit)
    }

    func checkLimits(settings: AppSettings, snapshot: CoachDataSnapshot) throws {
        let today = snapshot.today
        let spentToday = try db.coachSpend(fromDay: today.isoString)
        if settings.coachDailyLimit > 0, spentToday.questions >= settings.coachDailyLimit {
            throw CoachError.dailyLimit(settings.coachDailyLimit)
        }
        let monthStart = LocalDate(year: today.year, month: today.month, day: 1)
        let spentMonth = try db.coachSpend(fromDay: monthStart.isoString)
        if settings.coachMonthlyBudgetUSD > 0, spentMonth.costUSD >= settings.coachMonthlyBudgetUSD {
            throw CoachError.budgetReached(settings.coachMonthlyBudgetUSD)
        }
    }

    func providerFor(_ thread: CoachThread, settings: AppSettings) throws -> any LLMProvider {
        if thread.provider == "gemini" && !settings.geminiPaidTierConfirmed { throw CoachError.geminiNotConfirmed }
        guard let key = keys(thread.provider), !key.isEmpty else { throw CoachError.missingKey(provider: thread.provider) }
        return makeProvider(thread.provider, key)
    }

    func newThread(title: String, settings: AppSettings, snapshot: CoachDataSnapshot, kind: String) throws -> CoachThread {
        let provider = settings.coachProvider.rawValue
        let model = settings.coachModel[provider] ?? (provider == "gemini" ? ModelCatalog.defaultGeminiModel : ModelCatalog.defaultAnthropicModel)
        let personal = settings.coachMode == .personal
        let system = CoachPrompts.system(mode: settings.coachMode, profile: snapshot.profile, memory: personal ? snapshot.memory : [],
                                         today: snapshot.today)
        let context = CoachThreadContext(mode: settings.coachMode.rawValue, kind: kind, system: system,
                                         tools: personal ? CoachTools.definitions : [])
        let cleanTitle = title.replacingOccurrences(of: "\n", with: " ")
        let thread = CoachThread(title: cleanTitle.count > 48 ? String(cleanTitle.prefix(47)) + "…" : cleanTitle, provider: provider,
                                 model: model, createdAt: clock(), updatedAt: clock(), contextJSON: context.json.serialized())
        try db.saveThread(thread)
        return thread
    }

    /// Historial en formato del proveedor. Si un turno con llamadas a herramientas quedó sin resultados (la app se cerró a mitad),
    /// se completa con resultados de error deterministas para que la petición sea válida.
    func history(_ thread: CoachThread, provider: any LLMProvider) throws -> [NativeTurn] {
        var turns: [NativeTurn] = []
        var pending: [ToolCall] = []
        func repair() {
            guard !pending.isEmpty else { return }
            turns.append(provider.toolResultsTurn(pending.map {
                ToolOutput(callID: $0.id, name: $0.name, content: ["error": "La consulta se interrumpió."], isError: true)
            }))
            pending = []
        }
        for record in try db.messages(threadID: thread.id) {
            guard let role = NativeTurn.Role(rawValue: record.role), let content = try? JSONValue.parse(record.contentJSON) else { continue }
            let turn = NativeTurn(role: role, content: content)
            if role != .tool { repair() }
            turns.append(turn)
            pending = role == .assistant ? provider.toolCalls(in: turn) : []
        }
        repair()
        return turns
    }

    /// Bucle petición → herramientas → resultados → petición, hasta la respuesta final.
    func converse(thread: CoachThread, context: CoachThreadContext, provider: any LLMProvider, settings: AppSettings,
                  snapshot: CoachDataSnapshot, schema: JSONValue?, kind: String,
                  emit: @escaping @Sendable (CoachEvent) -> Void) async throws -> (CoachMessageRecord, LLMResponse)? {
        var dataUsed: [CoachDataRef] = []
        var proposal: GoalProposal?
        for _ in 0..<Self.maxSteps {
            try Task.checkCancellation()
            let request = LLMRequest(model: thread.model, system: context.system, tools: context.tools,
                                     history: try history(thread, provider: provider), effort: settings.coachEffort,
                                     maxTokens: 16_000, responseSchema: schema)
            var response: LLMResponse?
            do {
                for try await event in provider.stream(request) {
                    switch event {
                    case .started(let model): emit(.started(model: model))
                    case .thinking: emit(.thinking)
                    case .textDelta(let t): emit(.text(t))
                    case .toolCallStarted(let name): emit(.tool(label: CoachTools.label(for: name)))
                    case .completed(let r): response = r
                    }
                }
            } catch let e as LLMError {
                throw CoachError.provider(e)
            }
            guard let r = response else { throw CoachError.provider(.protocolError("sin respuesta")) }
            let servedModel = r.model.isEmpty ? thread.model : r.model
            let cost = ModelCatalog.cost(r.usage, provider: thread.provider, model: servedModel, on: clock())
            try db.addCoachSpend(day: snapshot.today.isoString, questions: 0, costUSD: cost)

            // Negativa: se descarta la salida parcial y se muestra un aviso (no entra en el historial).
            if case .refusal(let category) = r.stop {
                let notice = CoachMessageRecord(threadID: thread.id, role: "notice", model: servedModel, contentJSON: "null",
                                                displayText: Self.refusalText(category), inputTokens: r.usage.inputTokens,
                                                outputTokens: r.usage.outputTokens, cacheReadTokens: r.usage.cacheReadTokens,
                                                cacheWriteTokens: r.usage.cacheWriteTokens, costUSD: cost, createdAt: clock(),
                                                metaJSON: CoachMessageMeta(kind: "refusal", provider: thread.provider, model: servedModel).json)
                try db.appendMessage(notice)
                emit(.notice(notice))
                return nil
            }

            if !r.toolCalls.isEmpty {
                // Paso intermedio: se guarda el turno tal cual y los resultados de las herramientas ejecutadas en el iPhone.
                let assistant = CoachMessageRecord(threadID: thread.id, role: "assistant", model: servedModel,
                                                   contentJSON: r.turn.content.serialized(), displayText: r.text,
                                                   inputTokens: r.usage.inputTokens, outputTokens: r.usage.outputTokens,
                                                   cacheReadTokens: r.usage.cacheReadTokens, cacheWriteTokens: r.usage.cacheWriteTokens,
                                                   costUSD: cost, createdAt: clock(),
                                                   metaJSON: CoachMessageMeta(kind: kind, provider: thread.provider, model: servedModel,
                                                                              usedFallback: r.usedFallback ? true : nil,
                                                                              hidden: r.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                                                                  ? true : nil).json)
                var outputs: [ToolOutput] = []
                for call in r.toolCalls {
                    if r.stop == .maxTokens {
                        // Una entrada cortada por el límite de longitud puede parecer válida: no se ejecuta.
                        outputs.append(ToolOutput(callID: call.id, name: call.name,
                                                  content: ["error": "La llamada se cortó por el límite de longitud; vuelve a pedirla."],
                                                  isError: true))
                        continue
                    }
                    let execution = CoachTools.execute(call, snapshot: snapshot)
                    outputs.append(execution.output)
                    dataUsed += execution.dataUsed.filter { !dataUsed.contains($0) }
                    if let p = execution.proposal {
                        proposal = p
                        emit(.proposal(p))
                    }
                }
                let results = provider.toolResultsTurn(outputs)
                try db.appendMessage(assistant)
                try db.appendMessage(CoachMessageRecord(threadID: thread.id, role: "tool", model: nil, contentJSON: results.content.serialized(),
                                                        displayText: "", createdAt: clock().addingTimeInterval(0.001),
                                                        metaJSON: CoachMessageMeta(kind: kind, hidden: true).json))
                emit(.stepSaved)
                continue
            }

            // Respuesta final con el filtro posterior de expresiones prohibidas (RL-02).
            var display = r.text
            var filtered = false
            if schema == nil, !CoachSafety.violations(in: display).isEmpty {
                display = CoachSafety.safeReplacement
                filtered = true
            }
            if r.stop == .maxTokens && schema == nil { display += "\n\n_(Respuesta cortada por longitud.)_" }
            let meta = CoachMessageMeta(kind: kind, provider: thread.provider, model: servedModel, usedFallback: r.usedFallback ? true : nil,
                                        dataUsed: dataUsed.isEmpty ? nil : dataUsed, proposal: proposal, filtered: filtered ? true : nil)
            let record = CoachMessageRecord(threadID: thread.id, role: "assistant", model: servedModel, contentJSON: r.turn.content.serialized(),
                                            displayText: display, inputTokens: r.usage.inputTokens, outputTokens: r.usage.outputTokens,
                                            cacheReadTokens: r.usage.cacheReadTokens, cacheWriteTokens: r.usage.cacheWriteTokens,
                                            costUSD: cost, createdAt: clock(), metaJSON: meta.json)
            try db.appendMessage(record)
            emit(.assistantMessage(record))
            return (record, r)
        }
        throw CoachError.tooManySteps
    }

    static func refusalText(_ category: String?) -> String {
        "El proveedor de IA ha declinado responder a esta pregunta\(category.map { " (motivo: \($0))" } ?? ""). Prueba a formularla de otra manera."
    }

    // MARK: Análisis del día con IA (RF-COA-18)

    /// Analiza un día con la IA y, si no es posible o la respuesta no cumple el esquema, con la versión determinista.
    public func analyzeDay(_ date: LocalDate, snapshot: CoachDataSnapshot, useAI: Bool = true,
                           emit: @escaping @Sendable (CoachEvent) -> Void = { _ in }) async throws -> DayAnalysisOutcome {
        guard let cycle = snapshot.output.cycle(on: date) else { throw CoachError.noData }
        let answers = snapshot.journal.filter { $0.date == date }
        let facts = DayAnalyzer.facts(for: cycle, output: snapshot.output, profile: snapshot.profile, params: snapshot.params, now: snapshot.now,
                                      journalLabels: JournalCatalog.labels, journal: answers)
        let deterministic = DayAnalyzer.analyze(facts, params: snapshot.params)

        func fallback(_ note: String?, threadID: String? = nil) throws -> DayAnalysisOutcome {
            let json = (try? JSONValue(encoding: deterministic).serialized()) ?? "{}"
            let stored = StoredDayAnalysis(cycleID: cycle.id, date: date.isoString, createdAt: clock(), kind: "deterministic", json: json)
            try db.saveDayAnalysis(stored)
            return DayAnalysisOutcome(analysis: deterministic, isAI: false, threadID: threadID, stored: stored, note: note)
        }

        let settings = try db.settings()
        guard useAI else { return try fallback(nil) }
        guard settings.coachEnabled, settings.coachMode == .personal else { return try fallback(nil) }
        let thread: CoachThread
        let provider: any LLMProvider
        do {
            try checkLimits(settings: settings, snapshot: snapshot)
            thread = try newThread(title: "Análisis del \(Format.shortDate(date))", settings: settings, snapshot: snapshot, kind: "analysis")
            provider = try providerFor(thread, settings: settings)
        } catch let e as CoachError {
            return try fallback(e.errorDescription)
        }
        emit(.threadReady(thread))
        guard let context = CoachThreadContext(json: thread.contextJSON) else { return try fallback(nil) }

        var factsJSON = (try? JSONValue(encoding: facts)) ?? .object([])
        if let note = snapshot.journalNotes[date.isoString], !note.isEmpty {
            factsJSON = factsJSON.setting("nota_del_usuario", CoachTools.untrusted(note))
        }
        let turn = provider.userTurn(text: CoachPrompts.dayAnalysisRequest(date: date, facts: factsJSON))
        let user = CoachMessageRecord(threadID: thread.id, role: "user", model: nil, contentJSON: turn.content.serialized(),
                                      displayText: "Analiza mi día (\(Format.shortDate(date)))", createdAt: clock(),
                                      metaJSON: CoachMessageMeta(kind: "analysis").json)
        try db.appendMessage(user)
        try db.addCoachSpend(day: snapshot.today.isoString, questions: 1, costUSD: 0)
        emit(.userMessage(user))

        let schema = try JSONValue.parse(DayAnalysis.jsonSchema)
        let result: (CoachMessageRecord, LLMResponse)?
        do {
            result = try await converse(thread: thread, context: context, provider: provider, settings: settings, snapshot: snapshot,
                                        schema: schema, kind: "analysis", emit: emit)
        } catch let e as CoachError {
            return try fallback(e.errorDescription, threadID: thread.id)
        }
        guard let result else {
            return try fallback("La IA no ha respondido; se muestra el análisis sin IA.", threadID: thread.id)
        }
        let (record, response) = result
        guard let parsed = try? JSONValue.parse(response.text).decode(DayAnalysis.self), parsed.validated(),
              CoachSafety.violations(in: Self.allText(parsed)).isEmpty else {
            return try fallback("La respuesta de la IA no tenía el formato esperado; se muestra el análisis sin IA.", threadID: thread.id)
        }
        let stored = StoredDayAnalysis(cycleID: cycle.id, date: date.isoString, createdAt: clock(), kind: "ai", json: response.text,
                                       provider: thread.provider, model: record.model)
        try db.saveDayAnalysis(stored)
        return DayAnalysisOutcome(analysis: parsed, isAI: true, threadID: thread.id, stored: stored, note: nil)
    }

    static func allText(_ a: DayAnalysis) -> String {
        ([a.titular, a.estaNoche, a.manana] + a.claves.map(\.texto)).joined(separator: ". ")
    }
}

/// Preguntas sugeridas según el contexto (RF-COA-08).
public enum CoachSuggestions {
    public static func questions(for cycle: CycleMetrics?) -> [String] {
        var out: [String] = []
        if let c = cycle {
            switch c.recovery.zone {
            case .low?: out.append("Tengo la recuperación baja, ¿qué hago hoy?")
            case .high?: out.append("¿Aprovecho hoy para entrenar fuerte?")
            case .medium?: out.append("¿Qué carga me conviene hoy?")
            case nil: break
            }
            if let s = c.sleep, s.debtMin >= 60 { out.append("¿Cómo recupero la deuda de sueño?") }
            if c.activities.contains(where: { $0.activity.kind.isRun }) { out.append("¿Qué tal fue mi carrera?") }
        }
        out += ["¿A qué hora me acuesto esta noche?", "¿Cómo ha evolucionado mi VFC este mes?", "¿Qué hábitos me afectan más?"]
        return Array(out.prefix(4))
    }
}
