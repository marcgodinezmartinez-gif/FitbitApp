import Foundation
import Insights
import MetricsKit
import RunKit
import Store

// MARK: - Análisis de una carrera redactado por la IA (doc. 18 §7)
//
// Una sola petición con los hechos ya calculados por RunKit (sin coordenadas) y salida estructurada. Se guarda en la tabla
// `report` con el tipo `ai_run` y el id de la carrera, y no se repite salvo que se pida otra vez.

/// Titular, resumen, puntos fuertes, aspectos a mejorar y la próxima sesión recomendada.
public struct RunNarrative: Codable, Sendable, Hashable {
    public var titular: String
    public var resumen: String
    public var puntosFuertes: [String]
    public var aMejorar: [String]
    public var proximaSesion: String

    enum CodingKeys: String, CodingKey {
        case titular, resumen
        case puntosFuertes = "puntos_fuertes"
        case aMejorar = "a_mejorar"
        case proximaSesion = "proxima_sesion"
    }

    public init(titular: String, resumen: String, puntosFuertes: [String], aMejorar: [String], proximaSesion: String) {
        self.titular = titular
        self.resumen = resumen
        self.puntosFuertes = puntosFuertes
        self.aMejorar = aMejorar
        self.proximaSesion = proximaSesion
    }

    public static let jsonSchema = """
    {"type":"object","additionalProperties":false,"required":["titular","resumen","puntos_fuertes","a_mejorar","proxima_sesion"],
     "properties":{"titular":{"type":"string"},"resumen":{"type":"string"},"puntos_fuertes":{"type":"array","items":{"type":"string"}},
     "a_mejorar":{"type":"array","items":{"type":"string"}},"proxima_sesion":{"type":"string"}}}
    """

    /// Limpia las listas (sin vacíos, máximo 3) y comprueba que hay contenido.
    func normalized() -> RunNarrative? {
        func clean(_ list: [String]) -> [String] {
            Array(list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(3))
        }
        let r = RunNarrative(titular: titular.trimmingCharacters(in: .whitespacesAndNewlines),
                             resumen: resumen.trimmingCharacters(in: .whitespacesAndNewlines), puntosFuertes: clean(puntosFuertes),
                             aMejorar: clean(aMejorar), proximaSesion: proximaSesion.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !r.titular.isEmpty, !r.resumen.isEmpty, !r.puntosFuertes.isEmpty, !r.proximaSesion.isEmpty,
              r.titular.count <= 160, r.resumen.count <= 1200 else { return nil }
        return r
    }

    var allText: String { ([titular, resumen, proximaSesion] + puntosFuertes + aMejorar).joined(separator: ". ") }
}

/// Hechos de una carrera para la IA: solo cifras ya calculadas y nunca coordenadas.
public enum RunFacts {
    public static func make(run: FusedActivity, analysis r: RunAnalysis, history: RunHistory, today: LocalDate,
                            recoveryScore: Int?, rpe: Double?, notes: String?) -> JSONValue {
        let date = LocalDate(run.start, utcOffsetSeconds: run.primary.utcOffsetSeconds)
        func pace(_ seconds: Double?) -> JSONValue { seconds.map { .string(Format.pace(secondsPerKm: $0) + " /km") } ?? .null }
        func minutes(_ seconds: Double) -> JSONValue { .rounded(seconds / 60, 0) }
        var members: [(String, JSONValue)] = [
            ("fecha", .string(date.isoString)),
            ("dia", .string(Format.weekdayName(date))),
            ("tipo", .string(run.kind.displayName)),
            ("dispositivos", .array(run.sources.map { .string($0.deviceName) })),
            ("distancia_km", .rounded(r.distanceM / 1000, 2)),
            ("tiempo_en_movimiento", .string(Format.raceTime(seconds: r.movingS))),
            ("tiempo_total", .string(Format.raceTime(seconds: r.elapsedS))),
            ("pausas", r.pauses > 0 ? .from(r.pauses) : .null),
            ("ritmo_medio", pace(r.avgPace)),
            ("ritmo_ajustado_por_pendiente", pace(r.avgGAP)),
            ("fc_media", .rounded(r.avgHR, 0)),
            ("fc_maxima", .rounded(r.maxHR, 0)),
            ("desnivel_positivo_m", .rounded(r.elevationGainM, 0)),
            ("desnivel_negativo_m", .rounded(r.elevationLossM, 0)),
            ("carga_trimp", .rounded(r.trimp, 0)),
            ("estres_rtss", .rounded(r.stressScore, 0)),
            ("intensidad_respecto_al_umbral", .rounded(r.intensityFactor, 2)),
            ("vo2max_estimado", .rounded(r.vo2maxEstimate, 1)),
            ("eficiencia_m_min_por_latido", .rounded(r.efficiencyFactor, 2)),
            ("desacoplamiento_aerobico_pct", .rounded(r.decouplingPct, 1)),
            ("deriva_fc_pct", .rounded(r.hrDriftPct, 1)),
            ("minutos_por_zona_fc", .array(r.hrZoneSeconds.map { minutes($0) })),
        ]
        if let z = r.paceZoneSeconds {
            members.append(("minutos_por_zona_de_ritmo", .compact(zip(["recuperacion", "suave", "maraton", "umbral", "intervalos", "repeticiones"], z)
                .map { ($0.0, minutes($0.1)) })))
        }
        members.append(("parciales", .array(r.splits.map { s in
            .compact([("km", .from(s.index)), ("distancia_m", s.distanceM < 999 ? .rounded(s.distanceM, 0) : .null), ("ritmo", pace(s.pace)),
                      ("ritmo_ajustado", pace(s.gapPace)), ("fc", .rounded(s.avgHR, 0)), ("cadencia", .rounded(s.cadence, 0)),
                      ("subida_m", .rounded(s.elevationGainM, 0)), ("bajada_m", .rounded(s.elevationLossM, 0))])
        })))
        if !r.laps.isEmpty {
            members.append(("vueltas", .array(r.laps.map { l in
                .compact([("vuelta", .from(l.index)), ("tipo", .string(l.kind)), ("tiempo", .string(Format.raceTime(seconds: l.seconds))),
                          ("distancia_m", .rounded(l.distanceM, 0)), ("ritmo", pace(l.pace)), ("fc", .rounded(l.avgHR, 0))])
            })))
        }
        if let iv = r.intervals {
            members.append(("series_detectadas", .compact([
                ("sesion", .string(iv.label)), ("ritmo_medio_series", pace(iv.avgRepPace)),
                ("recuperacion_media_s", .rounded(iv.avgRecoverySeconds, 0)), ("caida_ritmo_pct", .rounded(iv.fadePct, 1)),
                ("variacion_ritmo_pct", .rounded(iv.paceSpreadPct, 1)),
                ("series", .array(iv.reps.map { rep in
                    .compact([("serie", .from(rep.index)), ("distancia_m", .rounded(rep.distanceM, 0)),
                              ("tiempo", .string(Format.raceTime(seconds: rep.seconds))), ("ritmo", pace(rep.pace)),
                              ("fc_media", .rounded(rep.avgHR, 0)), ("recuperacion_s", .rounded(rep.recoverySeconds, 0))])
                })),
            ])))
        }
        members.append(("mejores_marcas", .array(r.bestEfforts.map { e in
            .compact([("distancia", .string(e.distance.label)), ("tiempo", .string(Format.raceTime(seconds: e.seconds)))])
        })))
        if let summary = history.summaries.first(where: { $0.id == run.id }) {
            let prs = history.personalRecords(in: summary)
            if !prs.isEmpty { members.append(("records_personales_nuevos", .array(prs.map { .string($0.label) }))) }
        }
        if !r.climbs.isEmpty {
            members.append(("subidas", .array(r.climbs.map { c in
                .compact([("km_inicio", .rounded(c.startKm, 1)), ("longitud_m", .rounded(c.lengthM, 0)), ("desnivel_m", .rounded(c.gainM, 0)),
                          ("pendiente_pct", .rounded(c.avgGradePct, 1)), ("vam_m_h", .rounded(c.vam, 0))])
            })))
        }
        members.append(("tecnica", .array(r.form.map { f in
            .compact([("metrica", .string(f.metric.label)), ("valor", .rounded(f.value, f.metric == .stride ? 2 : 1)),
                      ("valoracion", f.rating == .info ? .null : .string(f.rating.label))])
        })))
        if let w = r.weather {
            members.append(("meteo", .compact([("temperatura_c", .rounded(w.temperatureC, 0)), ("humedad_pct", .rounded(w.humidityPct, 0)),
                                               ("estado", .from(w.condition))])))
        }
        if let c = r.comparison {
            members.append(("apple_watch_frente_a_fitbit", .compact([
                ("distancia_watch_km", .rounded(c.watchDistanceM.map { $0 / 1000 }, 2)), ("distancia_fitbit_km", .rounded(c.fitbitDistanceM.map { $0 / 1000 }, 2)),
                ("fc_media_watch", .rounded(c.watchAvgHR, 0)), ("fc_media_fitbit", .rounded(c.fitbitAvgHR, 0)),
                ("diferencia_fc_media", .rounded(c.hrBias, 1)), ("cadencia_watch", .rounded(c.watchCadence, 0)),
                ("cadencia_fitbit", .rounded(c.fitbitCadence, 0)), ("vo2max_fitbit", .rounded(c.fitbitVO2max, 1)),
            ])))
        }
        // Contexto: forma, volumen reciente y ritmos de entrenamiento.
        var context: [(String, JSONValue)] = []
        if let v = history.vdot(today: today) {
            context.append(("vdot", .rounded(v.value, 1)))
            context.append(("ritmos_entrenamiento", .compact(RunPhysiology.trainingPaces(vdot: v.value).map { p in
                (p.zone.label, .string(p.slowSpeed == p.fastSpeed ? Format.pace(secondsPerKm: 1000 / p.fastSpeed)
                                       : "\(Format.pace(secondsPerKm: 1000 / p.slowSpeed))–\(Format.pace(secondsPerKm: 1000 / p.fastSpeed))"))
            })))
        }
        let weeks = history.weeks(count: 4, today: today)
        context.append(("km_ultimas_4_semanas", .array(weeks.map { .rounded($0.distanceM / 1000, 1) })))
        if let f = history.fitness(days: 1, today: today).last {
            context.append(("forma_ctl", .rounded(f.fitness, 0)))
            context.append(("fatiga_atl", .rounded(f.fatigue, 0)))
            context.append(("frescura_tsb", .rounded(f.form, 0)))
        }
        members.append(("contexto", .compact(context)))
        members.append(("recuperacion_de_ese_dia", .rounded(recoveryScore)))
        members.append(("esfuerzo_percibido_rpe", .rounded(rpe, 0)))
        if let notes, !notes.isEmpty {
            // Contenido del usuario: se marca como dato, no como instrucción.
            members.append(("notas_del_usuario_como_dato", .string(String(notes.prefix(400)))))
        }
        return .compact(members)
    }
}

extension AppDatabase {
    public func aiRunReport(activityID: String) -> AIReport? {
        guard let json = try? report(type: AIReport.Kind.run.rawValue, periodStart: activityID) else { return nil }
        return try? JSONDecoder.reports.decode(AIReport.self, from: Data(json.utf8))
    }
}

extension CoachPrompts {
    /// Petición del análisis de una carrera.
    public static func runRequest(facts: JSONValue) -> String {
        """
        Analiza esta carrera como un entrenador de running con estos datos:
        \(facts.serialized())

        - "titular": una frase (máx. 12 palabras) que resuma la carrera.
        - "resumen": 3–4 frases: qué tipo de sesión fue, cómo se repartió el esfuerzo (parciales, zonas, pendiente) y qué dice de tu forma.
        - "puntos_fuertes": 2 o 3 aspectos buenos concretos, con cifras.
        - "a_mejorar": 1 a 3 aspectos a mejorar, cada uno con una acción concreta (técnica, ritmo, hidratación, reparto del esfuerzo…).
        - "proxima_sesion": una frase con la próxima sesión recomendada (tipo, duración y ritmo o zona), según la recuperación y la forma.
        Si hay desacoplamiento, deriva de FC, mejores marcas o récords, coméntalos. No menciones datos que no estén.
        """
    }
}

extension CoachEngine {
    /// Análisis de una carrera. Si ya existe, lo devuelve sin llamar a la IA (salvo `force`).
    public func runAnalysis(runID: String, facts: JSONValue, snapshot: CoachDataSnapshot, force: Bool = false) async throws -> AIReport {
        if !force, let existing = db.aiRunReport(activityID: runID) { return existing }
        let (text, response, provider, model, cost) = try await generate(prompt: CoachPrompts.runRequest(facts: facts),
                                                                          schema: RunNarrative.jsonSchema, snapshot: snapshot)
        guard let decoded = try? JSONValue.parse(text).decode(RunNarrative.self), let parsed = decoded.normalized(),
              CoachSafety.violations(in: parsed.allText).isEmpty else { throw ReportError.invalidResponse }
        let report = AIReport(kind: .run, periodStart: runID, createdAt: clock(), provider: provider, model: model, costUSD: cost,
                              usedFallback: response.usedFallback ? true : nil, run: parsed)
        try db.saveAIReport(report)
        return report
    }
}
