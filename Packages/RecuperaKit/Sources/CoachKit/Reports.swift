import Foundation
import Insights
import MetricsKit
import Store

// MARK: - Resumen matinal (RF-COA-05) e informe semanal (RF-COA-06) redactados por la IA
//
// Una sola petición por informe, con los hechos ya calculados en el propio mensaje y salida estructurada (JSON validado contra
// un esquema). Sin herramientas ni hilos del Coach. No se usa la API de lotes (Message Batches): son una o dos peticiones al día
// y el resultado hace falta en el momento, así que el descuento no compensa la espera de hasta 24 h.

/// Resumen matinal: título, 2–3 frases, carga objetivo y hora de acostarse.
public struct MorningSummary: Codable, Sendable, Hashable {
    public var titulo: String
    public var resumen: String
    public var cargaObjetivo: String
    public var horaAcostarse: String

    enum CodingKeys: String, CodingKey {
        case titulo, resumen
        case cargaObjetivo = "carga_objetivo"
        case horaAcostarse = "hora_acostarse"
    }

    public init(titulo: String, resumen: String, cargaObjetivo: String, horaAcostarse: String) {
        self.titulo = titulo
        self.resumen = resumen
        self.cargaObjetivo = cargaObjetivo
        self.horaAcostarse = horaAcostarse
    }

    public static let jsonSchema = """
    {"type":"object","additionalProperties":false,"required":["titulo","resumen","carga_objetivo","hora_acostarse"],
     "properties":{"titulo":{"type":"string"},"resumen":{"type":"string"},"carga_objetivo":{"type":"string"},
     "hora_acostarse":{"type":"string"}}}
    """

    func validated() -> Bool {
        let fields = [titulo, resumen, cargaObjetivo, horaAcostarse].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return !fields.contains(where: \.isEmpty) && titulo.count <= 140 && resumen.count <= 900
    }

    var allText: String { [titulo, resumen, cargaObjetivo, horaAcostarse].joined(separator: ". ") }
}

/// Informe semanal: resumen, 3 logros, 3 áreas de mejora y comparación con la semana anterior.
public struct WeeklyNarrative: Codable, Sendable, Hashable {
    public var resumen: String
    public var logros: [String]
    public var mejoras: [String]
    public var comparacion: String

    public init(resumen: String, logros: [String], mejoras: [String], comparacion: String) {
        self.resumen = resumen
        self.logros = logros
        self.mejoras = mejoras
        self.comparacion = comparacion
    }

    public static let jsonSchema = """
    {"type":"object","additionalProperties":false,"required":["resumen","logros","mejoras","comparacion"],
     "properties":{"resumen":{"type":"string"},"logros":{"type":"array","items":{"type":"string"}},
     "mejoras":{"type":"array","items":{"type":"string"}},"comparacion":{"type":"string"}}}
    """

    /// Limpia listas (sin vacíos, máximo 3) y comprueba que hay contenido.
    func normalized() -> WeeklyNarrative? {
        func clean(_ list: [String]) -> [String] {
            Array(list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(3))
        }
        let r = WeeklyNarrative(resumen: resumen.trimmingCharacters(in: .whitespacesAndNewlines), logros: clean(logros),
                                mejoras: clean(mejoras), comparacion: comparacion.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !r.resumen.isEmpty, !r.logros.isEmpty, !r.mejoras.isEmpty, r.resumen.count <= 1200 else { return nil }
        return r
    }

    var allText: String { ([resumen, comparacion] + logros + mejoras).joined(separator: ". ") }
}

/// Informe guardado en la tabla `report` (tipo `ai_morning` o `ai_weekly`).
public struct AIReport: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case morning = "ai_morning"
        case weekly = "ai_weekly"
    }

    public var kind: Kind
    /// Día del resumen matinal o lunes de la semana del informe (AAAA-MM-DD).
    public var periodStart: String
    public var createdAt: Date
    public var provider: String
    public var model: String
    public var costUSD: Double
    public var usedFallback: Bool?
    public var morning: MorningSummary?
    public var weekly: WeeklyNarrative?
    /// Recuperación con la que se redactó el resumen matinal: si cambia (llegan tarde los vitales), se rehace.
    public var recoveryScore: Int?

    public init(kind: Kind, periodStart: String, createdAt: Date, provider: String, model: String, costUSD: Double,
                usedFallback: Bool? = nil, morning: MorningSummary? = nil, weekly: WeeklyNarrative? = nil, recoveryScore: Int? = nil) {
        self.kind = kind
        self.periodStart = periodStart
        self.createdAt = createdAt
        self.provider = provider
        self.model = model
        self.costUSD = costUSD
        self.usedFallback = usedFallback
        self.morning = morning
        self.weekly = weekly
        self.recoveryScore = recoveryScore
    }
}

extension AppDatabase {
    public func aiReport(_ kind: AIReport.Kind, periodStart: LocalDate) -> AIReport? {
        guard let json = try? report(type: kind.rawValue, periodStart: periodStart.isoString) else { return nil }
        return try? JSONDecoder.reports.decode(AIReport.self, from: Data(json.utf8))
    }

    func saveAIReport(_ r: AIReport) throws {
        let data = try JSONEncoder.reports.encode(r)
        try saveReport(id: "\(r.kind.rawValue):\(r.periodStart)", type: r.kind.rawValue, periodStart: r.periodStart,
                       json: String(decoding: data, as: UTF8.self))
    }
}

extension JSONEncoder {
    static let reports: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()
}

extension JSONDecoder {
    static let reports: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
}

public enum ReportError: Error, Equatable, LocalizedError {
    case notReady(String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .notReady(let why): return why
        case .invalidResponse: return "La respuesta de la IA no tenía el formato esperado."
        }
    }
}

// MARK: - Hechos que se envían

public enum ReportFacts {
    /// Hechos del resumen matinal: la recuperación de hoy, el sueño, la carga objetivo y la hora de acostarse ya calculadas.
    public static func morning(snapshot: CoachDataSnapshot, bedtimeMinutes: Int?) -> JSONValue? {
        let out = snapshot.output
        guard let cur = out.current, cur.sleep != nil || cur.recovery.score != nil else { return nil }
        let prev = out.cycles.dropLast().last
        var members: [(String, JSONValue)] = [
            ("fecha", .string(cur.date.isoString)),
            ("dia", .string(Format.weekdayName(cur.date))),
        ]
        var recovery: [(String, JSONValue)] = [("puntuacion", .rounded(cur.recovery.score)),
                                               ("zona", .from(cur.recovery.zone?.label.lowercased()))]
        if case .calibrating(let n, let needed) = cur.recovery.status {
            recovery.append(("calibrando", .string("\(n) de \(needed) noches")))
        }
        recovery.append(("componentes", .array(cur.recovery.components.map { c in
            .compact([("metrica", .string(componentName(c.kind))), ("valor", .rounded(c.value)), ("referencia", .rounded(c.baseline)),
                      ("z", .rounded(c.z, 2))])
        })))
        members.append(("recuperacion", .compact(recovery)))
        if let s = cur.sleep {
            members.append(("sueno", .compact([
                ("dormido", .string(Format.duration(minutes: s.asleepMin))),
                ("necesidad", .string(Format.duration(minutes: s.need.totalMin))),
                ("rendimiento_pct", .rounded(s.performance, 0)),
                ("deuda", .string(Format.duration(minutes: s.debtMin))),
                ("constancia_pct", .rounded(s.consistency, 0)),
            ])))
        }
        if let t = cur.target {
            members.append(("carga_objetivo", ["min": .rounded(t.low), "max": .rounded(t.high), "modo": .string(cur.strainMode.label)]))
        }
        if let need = out.tonightNeed {
            members.append(("necesidad_esta_noche", .string(Format.duration(minutes: need.totalMin))))
        }
        if let bed = bedtimeMinutes { members.append(("hora_acostarse", .string(Format.clock(minutes: bed)))) }
        if let prev {
            members.append(("ayer", .compact([
                ("carga", .rounded(prev.strain.strain)),
                ("actividades", .array(prev.activities.map { a in
                    var text = a.activity.name
                    if let d = a.activity.distanceM, d > 0 { text += " de \(Format.km(d))" }
                    return .string(text + " (\(Format.duration(minutes: a.activity.durationMinutes)), carga \(Format.decimal(a.strain.strain)))")
                })),
            ])))
        }
        if cur.health?.combinedAlert == true {
            members.append(("vitales", .string("fuera de tu rango habitual esta noche")))
        }
        return .compact(members)
    }

    /// Hechos del informe semanal: el informe determinista, el plan y los hábitos con efecto.
    public static func weekly(snapshot: CoachDataSnapshot, weekStart: LocalDate, plan: WeeklyPlanProgress?) -> JSONValue? {
        let report = WeeklyReportBuilder.build(output: snapshot.output, weekStart: weekStart)
        let week = snapshot.output.cycles.filter { $0.date >= weekStart && $0.date < weekStart.adding(days: 7) }
        guard week.count >= 3 else { return nil }
        var members: [(String, JSONValue)] = [
            ("semana", .string("\(report.periodStart) a \(report.periodEnd)")),
            ("recuperacion_media", .rounded(report.avgRecovery, 0)),
            ("recuperacion_media_semana_anterior", .rounded(report.previousAvgRecovery, 0)),
            ("carga_media", .rounded(report.avgStrain)),
            ("carga_media_semana_anterior", .rounded(report.previousAvgStrain)),
            ("dias_por_zona", ["alta": .rounded(report.zoneDays["high"]), "media": .rounded(report.zoneDays["medium"]),
                               "baja": .rounded(report.zoneDays["low"])]),
            ("sueno_medio", .from(report.avgSleepMin.map { Format.duration(minutes: $0) })),
            ("necesidad_media", .from(report.avgNeedMin.map { Format.duration(minutes: $0) })),
            ("carreras", .from(report.runs)),
            ("km_carrera", .rounded(report.runDistanceKm)),
            ("destacados", .array(report.best.map { .string($0) })),
        ]
        let vfc = Stats.mean(week.compactMap { $0.vitals?.hrvRmssdAvg })
        let rhr = Stats.mean(week.compactMap { $0.vitals?.restingHR })
        members.append(("vfc_media_ms", .rounded(vfc, 0)))
        members.append(("fc_reposo_media", .rounded(rhr, 0)))
        if let plan {
            members.append(("plan_semanal", .compact([
                ("progreso_pct", .from(plan.percent)),
                ("objetivos", .array(plan.items.map { .string("\($0.title): \($0.detail)") })),
            ])))
        }
        let labels = JournalCatalog.labels
        let habits = snapshot.output.habitImpacts.filter { $0.status == .effect }.compactMap { h -> JSONValue? in
            guard let e = h.effect else { return nil }
            return .string("\(labels[h.questionKey] ?? h.questionKey): \(Format.signed(e, digits: 1)) puntos de recuperación")
        }
        if !habits.isEmpty { members.append(("habitos_con_efecto", .array(habits))) }
        return .compact(members)
    }

    static func componentName(_ k: RecoveryComponent.Kind) -> String {
        switch k {
        case .hrv: return "VFC (ms)"
        case .restingHR: return "FC en reposo (lpm)"
        case .sleep: return "sueño (% de la necesidad)"
        case .respiratoryRate: return "frecuencia respiratoria (rpm)"
        case .skinTemp: return "temperatura de la piel (°C)"
        case .spo2: return "SpO₂ (%)"
        }
    }
}

// MARK: - Generación

extension CoachEngine {
    /// Resumen matinal de hoy. Si ya existe con la misma recuperación, lo devuelve sin llamar a la IA (salvo `force`).
    public func morningSummary(snapshot: CoachDataSnapshot, bedtimeMinutes: Int?, force: Bool = false) async throws -> AIReport {
        guard let cur = snapshot.output.current else { throw ReportError.notReady("Todavía no hay datos de hoy.") }
        if !force, let existing = db.aiReport(.morning, periodStart: cur.date), existing.recoveryScore == cur.recovery.score {
            return existing
        }
        guard cur.sleep != nil else { throw ReportError.notReady("El resumen se prepara cuando llega el sueño de anoche.") }
        guard cur.recovery.score != nil else {
            throw ReportError.notReady("El resumen se prepara cuando lleguen tus vitales de la noche y esté tu recuperación.")
        }
        guard let facts = ReportFacts.morning(snapshot: snapshot, bedtimeMinutes: bedtimeMinutes) else {
            throw ReportError.notReady("Todavía no hay datos de hoy.")
        }
        let prompt = CoachPrompts.morningRequest(facts: facts)
        let (text, response, provider, model, cost) = try await generate(prompt: prompt, schema: MorningSummary.jsonSchema, snapshot: snapshot)
        guard let parsed = try? JSONValue.parse(text).decode(MorningSummary.self), parsed.validated(),
              CoachSafety.violations(in: parsed.allText).isEmpty else { throw ReportError.invalidResponse }
        let report = AIReport(kind: .morning, periodStart: cur.date.isoString, createdAt: clock(), provider: provider, model: model,
                              costUSD: cost, usedFallback: response.usedFallback ? true : nil, morning: parsed, weekly: nil,
                              recoveryScore: cur.recovery.score)
        try db.saveAIReport(report)
        return report
    }

    /// Informe de la semana que empieza en `weekStart` (lunes). Si ya existe, lo devuelve (salvo `force`).
    public func weeklyNarrative(snapshot: CoachDataSnapshot, weekStart: LocalDate, plan: WeeklyPlanProgress?,
                                force: Bool = false) async throws -> AIReport {
        if !force, let existing = db.aiReport(.weekly, periodStart: weekStart) { return existing }
        guard let facts = ReportFacts.weekly(snapshot: snapshot, weekStart: weekStart, plan: plan) else {
            throw ReportError.notReady("Hacen falta al menos 3 días con datos en la semana.")
        }
        let prompt = CoachPrompts.weeklyRequest(facts: facts)
        let (text, response, provider, model, cost) = try await generate(prompt: prompt, schema: WeeklyNarrative.jsonSchema, snapshot: snapshot)
        guard let decoded = try? JSONValue.parse(text).decode(WeeklyNarrative.self), let parsed = decoded.normalized(),
              CoachSafety.violations(in: parsed.allText).isEmpty else { throw ReportError.invalidResponse }
        let report = AIReport(kind: .weekly, periodStart: weekStart.isoString, createdAt: clock(), provider: provider, model: model,
                              costUSD: cost, usedFallback: response.usedFallback ? true : nil, morning: nil, weekly: parsed)
        try db.saveAIReport(report)
        return report
    }

    /// Una petición sin herramientas con salida estructurada; apunta el gasto (no cuenta como pregunta).
    func generate(prompt: String, schema: String, snapshot: CoachDataSnapshot) async throws
        -> (text: String, response: LLMResponse, provider: String, model: String, cost: Double) {
        let settings = try db.settings()
        guard settings.coachEnabled else { throw CoachError.disabled }
        guard settings.coachMode == .personal else {
            throw ReportError.notReady("Los informes de la IA usan tus datos: activa el modo personal del Coach.")
        }
        let today = snapshot.today
        let monthStart = LocalDate(year: today.year, month: today.month, day: 1)
        if settings.coachMonthlyBudgetUSD > 0, try db.coachSpend(fromDay: monthStart.isoString).costUSD >= settings.coachMonthlyBudgetUSD {
            throw CoachError.budgetReached(settings.coachMonthlyBudgetUSD)
        }
        let providerID = settings.coachProvider.rawValue
        if providerID == "gemini" && !settings.geminiPaidTierConfirmed { throw CoachError.geminiNotConfirmed }
        guard let key = keys(providerID), !key.isEmpty else { throw CoachError.missingKey(provider: providerID) }
        let model = settings.coachModel[providerID]
            ?? (providerID == "gemini" ? ModelCatalog.defaultGeminiModel : ModelCatalog.defaultAnthropicModel)
        let provider = makeProvider(providerID, key)
        let request = LLMRequest(model: model, system: CoachPrompts.reportSystem(profile: snapshot.profile, today: today), tools: [],
                                 history: [provider.userTurn(text: prompt)], effort: "low", maxTokens: 4_000,
                                 responseSchema: try JSONValue.parse(schema))
        let response: LLMResponse
        do {
            response = try await provider.complete(request)
        } catch let e as LLMError {
            throw CoachError.provider(e)
        }
        let served = response.model.isEmpty ? model : response.model
        let cost = ModelCatalog.cost(response.usage, provider: providerID, model: served, on: clock())
        try db.addCoachSpend(day: today.isoString, questions: 0, costUSD: cost)
        if case .refusal = response.stop { throw ReportError.invalidResponse }
        return (response.text, response, providerID, served, cost)
    }
}
