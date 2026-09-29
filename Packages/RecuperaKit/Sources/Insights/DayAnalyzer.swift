import Foundation
import MetricsKit

/// ALG-ANA-01 · Análisis determinista del día («Analizar mi día» sin IA).
public enum DayAnalyzer {
    public static func facts(for cycle: CycleMetrics, output: MetricsOutput, profile: UserProfile,
                             params: AlgorithmParams = .default, now: Date, journalLabels: [String: String] = [:],
                             journal: [JournalAnswer] = []) -> DayFacts {
        var facts: [DayFact] = []
        var used: [DayAnalysis.DataUsed] = []
        let date = cycle.date
        let fitbit = DataSourceKind.googleHealth

        func use(_ metric: String, _ source: DataSourceKind) {
            used.append(DayAnalysis.DataUsed(metrica: metric, fecha: date.isoString, fuente: source.analysisSourceID))
        }

        // Sueño.
        if let s = cycle.sleep {
            let tone: DayAnalysis.Tone = s.performance >= 85 ? .positivo : (s.performance < 70 ? .aVigilar : .neutro)
            var text = "Dormiste \(Format.duration(minutes: s.asleepMin)) de las \(Format.duration(minutes: s.need.totalMin)) que necesitabas (\(Format.percent(s.sufficiency)))."
            if s.debtMin >= 60 { text += " Llevas \(Format.duration(minutes: s.debtMin)) de deuda de sueño." }
            facts.append(DayFact(block: .sleep, metric: "sleep_performance", text: text, tone: tone,
                                 relevance: abs(s.performance - 85) / 10, source: fitbit, confident: true))
            use("sleep_performance", fitbit)
        }

        // Recuperación y los dos componentes que más la mueven.
        if let score = cycle.recovery.score, let zone = cycle.recovery.zone {
            let top = cycle.recovery.components.sorted { abs($0.contribution) > abs($1.contribution) }.prefix(2)
            let reasons = top.compactMap { componentSentence($0) }
            let tone: DayAnalysis.Tone = zone == .high ? .positivo : (zone == .low ? .aVigilar : .neutro)
            var text = "Recuperación del \(score) % (\(zone.label.lowercased()))."
            if !reasons.isEmpty { text += " " + reasons.joined(separator: " ") }
            facts.append(DayFact(block: .recovery, metric: "recovery", text: text, tone: tone,
                                 relevance: abs(Double(score) - 57) / 20, source: fitbit,
                                 confident: cycle.recovery.confidence != .low))
            use("recovery", fitbit)
            if top.contains(where: { $0.kind == .hrv }) { use("hrv_rmssd", fitbit) }
            if top.contains(where: { $0.kind == .restingHR }) { use("resting_hr", fitbit) }
        } else if case .calibrating(let n, let needed) = cycle.recovery.status {
            facts.append(DayFact(block: .recovery, metric: "recovery", text: "Tu recuperación aún se está calibrando (\(n) de \(needed) noches).",
                                 tone: .neutro, relevance: 0.1, source: fitbit, confident: true))
        }

        // Carga frente al objetivo.
        let hrSources = Set(cycle.activities.compactMap(\.activity.hrSource)).union([fitbit])
        if let t = cycle.target {
            let st = t.status(of: cycle.strain.strain)
            let width = max(t.high - t.low, 0.5)
            let (tone, text): (DayAnalysis.Tone, String)
            switch st {
            case .within: (tone, text) = (.positivo, "Carga de \(Format.decimal(cycle.strain.strain)), dentro de tu objetivo (\(Format.decimal(t.low))–\(Format.decimal(t.high))).")
            case .below: (tone, text) = (.neutro, "Carga de \(Format.decimal(cycle.strain.strain)), por debajo de tu objetivo (\(Format.decimal(t.low))–\(Format.decimal(t.high))).")
            case .above: (tone, text) = (.aVigilar, "Carga de \(Format.decimal(cycle.strain.strain)), por encima de tu objetivo (\(Format.decimal(t.low))–\(Format.decimal(t.high))).")
            }
            let dist = st == .within ? 0 : min(abs(cycle.strain.strain - t.low), abs(cycle.strain.strain - t.high)) / width
            facts.append(DayFact(block: .strain, metric: "strain", text: text, tone: tone, relevance: 0.5 + dist, source: fitbit,
                                 confident: cycle.strain.confidence != .low))
        } else {
            facts.append(DayFact(block: .strain, metric: "strain", text: "Carga del día: \(Format.decimal(cycle.strain.strain)).",
                                 tone: .neutro, relevance: 0.3, source: fitbit, confident: cycle.strain.confidence != .low))
        }
        for s in hrSources { use("strain", s) }

        // Actividades (con la comparación de ritmo en carreras del Watch).
        var summaries: [DayAnalysis.ActivitySummary] = []
        for a in cycle.activities {
            let act = a.activity
            let sources = act.sources.map(\.analysisSourceID)
            summaries.append(DayAnalysis.ActivitySummary(tipo: act.kind.displayName.lowercased(),
                                                         distanciaKm: act.distanceM.map { ($0 / 100).rounded() / 10 },
                                                         ritmoMinKm: act.paceSecondsPerKm.map { Format.pace(secondsPerKm: $0) },
                                                         carga: a.strain.strain, fuentes: sources))
            var text = "\(act.name): \(Format.duration(minutes: act.durationMinutes)), carga \(Format.decimal(a.strain.strain))"
            var relevance = a.strain.strain / 10
            var tone: DayAnalysis.Tone = .neutro
            if act.kind.isRun, let d = act.distanceM, let pace = act.paceSecondsPerKm {
                text += ", \(Format.km(d)) a \(Format.pace(secondsPerKm: pace))/km"
                if let ref = medianPace(similarTo: act, in: output, params: params, before: act.start) {
                    let diff = pace - ref
                    if abs(diff) >= 5 {
                        text += diff < 0 ? ", \(Int(abs(diff).rounded())) s/km más rápido que tu media reciente"
                                         : ", \(Int(diff.rounded())) s/km más lento que tu media reciente"
                        tone = diff < 0 ? .positivo : .neutro
                        relevance += abs(diff) / 20
                    }
                }
                let hard = a.strain.zoneMinutes.count == 6 ? a.strain.zoneMinutes[4] + a.strain.zoneMinutes[5] : 0
                if hard > 0 { text += "; \(hard) min en zonas 4–5" }
                use("run_pace", .appleHealth)
            }
            facts.append(DayFact(block: .activity, metric: "activity:\(act.id)", text: text + ".", tone: tone, relevance: relevance,
                                 source: act.primary.source, confident: true))
        }

        // Estrés frente a tu media de 14 días.
        if let avg = cycle.stress.average {
            let prior = output.cycles.filter { $0.date < date && date.days(since: $0.date) <= 14 }.compactMap(\.stress.average)
            if let m = Stats.mean(prior), let sd = Stats.sd(prior), sd > 0.05 {
                let z = (avg - m) / sd
                let tone: DayAnalysis.Tone = z > 1 ? .aVigilar : (z < -1 ? .positivo : .neutro)
                let text = "Estrés medio de \(Format.decimal(avg)) (tu media: \(Format.decimal(m)))" +
                    (cycle.stress.sustainedHigh ? ", con un rato de estrés alto sostenido." : ".")
                facts.append(DayFact(block: .stress, metric: "stress", text: text, tone: tone, relevance: abs(z) * 0.7,
                                     source: fitbit, confident: true))
                use("stress", fitbit)
            }
        }

        // Vitales fuera de rango (lenguaje de bienestar, RL-02).
        if let h = cycle.health, h.vitals.contains(where: \.outOfRange) {
            let names = h.vitals.filter(\.outOfRange).map { $0.kind.label.lowercased() }
            let text = h.combinedAlert ? HealthMonitor.alertMessage
                : "Esta noche tu \(names.joined(separator: " y tu ")) quedó fuera de tu rango habitual."
            facts.append(DayFact(block: .health, metric: "vitals", text: text, tone: .aVigilar,
                                 relevance: h.combinedAlert ? 3 : 1.5, source: fitbit, confident: true))
            use("vitals", fitbit)
        }

        // Hábitos del diario de ese día.
        let answers = journal.filter { $0.date == date && $0.yes == true }
        for a in answers {
            let label = journalLabels[a.questionKey] ?? a.questionKey
            if let impact = output.habitImpacts.first(where: { $0.questionKey == a.questionKey }), impact.status == .effect,
               let e = impact.effect {
                let text = "Marcaste «\(label)». En tus datos suele \(e < 0 ? "restar" : "sumar") unos \(Int(abs(e).rounded())) puntos a la recuperación del día siguiente."
                facts.append(DayFact(block: .habits, metric: "habit:\(a.questionKey)", text: text, tone: e < 0 ? .aVigilar : .positivo,
                                     relevance: abs(e) / 10, source: .manual, confident: true))
            }
        }

        let tonight = tonightRecommendation(cycle: cycle, output: output, profile: profile, params: params)
        let tomorrow = tomorrowRecommendation(cycle: cycle)
        let headline = headline(cycle: cycle)
        let isOpen = cycle.isOpen
        let until = isOpen ? now : (cycle.cycle.end ?? now)
        return DayFacts(date: date.isoString, dataUntil: iso(until, offset: cycle.cycle.utcOffsetSeconds),
                        dataUntilLocal: Format.clock(until, utcOffsetSeconds: cycle.cycle.utcOffsetSeconds), facts: facts,
                        activities: summaries, tonight: tonight, tomorrow: tomorrow, headline: headline, dataUsed: dedupe(used))
    }

    /// Selecciona 3–5 claves (paso 3) y arma la salida.
    public static func analyze(_ f: DayFacts, params: AlgorithmParams = .default) -> DayAnalysis {
        let candidates = f.facts.filter(\.confident)
        var chosen: [DayFact] = []
        for block in [DayFact.Block.sleep, .recovery, .strain] {
            if let best = candidates.filter({ $0.block == block }).max(by: { $0.relevance < $1.relevance }) { chosen.append(best) }
        }
        if let act = candidates.filter({ $0.block == .activity }).max(by: { $0.relevance < $1.relevance }) { chosen.append(act) }
        let rest = candidates.filter { c in !chosen.contains(c) }.sorted { $0.relevance > $1.relevance }
        for c in rest where chosen.count < params.dayAnalysis.maxKeys { chosen.append(c) }
        chosen = Array(chosen.prefix(params.dayAnalysis.maxKeys))
        // Al menos una positiva si la hay («sin culpa»).
        if !chosen.contains(where: { $0.tone == .positivo }), let pos = candidates.first(where: { $0.tone == .positivo && !chosen.contains($0) }) {
            if chosen.count >= params.dayAnalysis.maxKeys { chosen.removeLast() }
            chosen.append(pos)
        }
        return DayAnalysis(titular: f.headline, datosHasta: f.dataUntilLocal,
                           claves: chosen.map { DayAnalysis.Key(tono: $0.tone, texto: $0.text, metricas: [$0.metric]) },
                           actividades: f.activities, estaNoche: f.tonight, manana: f.tomorrow, datosUsados: f.dataUsed)
    }

    // MARK: - Recomendaciones (paso 4)

    public static func tonightRecommendation(cycle: CycleMetrics, output: MetricsOutput, profile: UserProfile,
                                             params: AlgorithmParams) -> String {
        guard let need = output.tonightNeed else { return "Intenta acostarte a tu hora habitual." }
        var bed = SleepCalculator.bedtime(wakeMinutes: profile.usualWakeMinutes, needMin: need.totalMin, goal: .peak,
                                          usualEfficiency: output.usualEfficiency, usualLatency: output.usualLatency, params: params)
        var reason = ""
        let over = cycle.target.map { cycle.strain.strain > $0.high } ?? false
        let debt = cycle.sleep?.debtMin ?? 0
        if over || debt > params.dayAnalysis.debtThresholdMin {
            let adv = (over && debt > params.dayAnalysis.debtThresholdMin)
                ? (params.dayAnalysis.bedtimeAdvanceMin.last ?? 30) : (params.dayAnalysis.bedtimeAdvanceMin.first ?? 15)
            bed -= Int(adv)
            reason = over ? " Hoy has cargado por encima de tu objetivo." : " Tienes deuda de sueño."
        }
        return "Acuéstate hacia las \(Format.clock(minutes: bed)) para dormir \(Format.duration(minutes: need.totalMin)).\(reason)"
    }

    public static func tomorrowRecommendation(cycle: CycleMetrics) -> String {
        let over = cycle.target.map { cycle.strain.strain > $0.high } ?? false
        let under = cycle.target.map { cycle.strain.strain < $0.low } ?? false
        if over || (cycle.health?.vitals.contains(where: \.outOfRange) ?? false) {
            return "Mañana, sesión suave o descanso."
        }
        if cycle.recovery.zone == .high && under {
            return "Tienes margen: si te apetece, mañana puedes apretar."
        }
        return "Mañana, mantén una carga parecida y escucha a tu cuerpo."
    }

    public static func headline(cycle: CycleMetrics) -> String {
        let status = cycle.target?.status(of: cycle.strain.strain)
        switch (cycle.recovery.zone, status) {
        case (.high?, .within?): return "Gran día: recuperación alta y carga en objetivo"
        case (.high?, .below?): return "Día de energía de sobra: aún tenías margen"
        case (.high?, .above?): return "Día intenso con buena base"
        case (.medium?, .above?), (.low?, .above?): return "Día exigente: toca recuperar"
        case (.low?, _): return "Día para cuidarte"
        case (.medium?, .within?): return "Día equilibrado"
        default: return "Tu día en claro"
        }
    }

    // MARK: - Utilidades

    static func componentSentence(_ c: RecoveryComponent) -> String? {
        switch c.kind {
        case .hrv:
            guard let v = c.value, let b = c.baseline, b > 0 else { return nil }
            let pct = (v / b - 1) * 100
            if abs(pct) < 3 { return "Tu VFC está en tu media." }
            return "Tu VFC está un \(Int(abs(pct).rounded())) % \(pct > 0 ? "por encima" : "por debajo") de tu media."
        case .restingHR:
            guard let v = c.value, let b = c.baseline else { return nil }
            let d = v - b
            if abs(d) < 1 { return "Tu FC en reposo está en tu media." }
            return "Tu FC en reposo está \(Int(abs(d).rounded())) lpm \(d > 0 ? "por encima" : "por debajo") de tu media."
        case .sleep:
            guard let v = c.value else { return nil }
            return "Dormiste el \(Format.percent(v)) de lo que necesitabas."
        case .respiratoryRate:
            return c.z < -0.5 ? "Tu frecuencia respiratoria está algo alta." : nil
        case .skinTemp:
            return c.z < -0.5 ? "Tu temperatura nocturna está algo alta." : nil
        case .spo2:
            return c.z < -0.5 ? "Tu SpO₂ está algo baja." : nil
        }
    }

    static func medianPace(similarTo act: FusedActivity, in output: MetricsOutput, params: AlgorithmParams, before: Date) -> Double? {
        guard let d = act.distanceM else { return nil }
        let window = TimeInterval(params.dayAnalysis.runPaceWindowDays * 86_400)
        let paces = output.fusedActivities.filter { other in
            guard other.id != act.id, other.kind.isRun, other.start < before, before.timeIntervalSince(other.start) <= window,
                  let od = other.distanceM else { return false }
            return abs(od - d) / d <= params.dayAnalysis.runSimilarDistance
        }.compactMap(\.paceSecondsPerKm)
        return paces.count >= 2 ? Stats.median(paces) : nil
    }

    static func iso(_ date: Date, offset: Int) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(secondsFromGMT: offset)
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    static func dedupe(_ xs: [DayAnalysis.DataUsed]) -> [DayAnalysis.DataUsed] {
        var seen = Set<String>()
        return xs.filter { seen.insert("\($0.metrica)|\($0.fuente)").inserted }
    }
}
