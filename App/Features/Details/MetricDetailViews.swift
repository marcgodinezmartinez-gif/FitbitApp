import SwiftUI
import Charts
import MetricsKit
import Insights

/// Serie diaria de los últimos `days` ciclos hasta `date`.
@MainActor
func series(_ model: AppModel, until date: LocalDate, days: Int, _ value: (CycleMetrics) -> Double?) -> [DayPoint] {
    guard let output = model.output else { return [] }
    let offset = TimeZone.current.secondsFromGMT()
    return output.cycles.filter { $0.date <= date && date.days(since: $0.date) < days }.compactMap { c in
        value(c).map { DayPoint(date: c.date.startDate(utcOffsetSeconds: offset), value: $0) }
    }
}

// MARK: - Recuperación

struct RecoveryDetailView: View {
    let date: LocalDate
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            if let cycle = model.output?.cycle(on: date) {
                let r = cycle.recovery
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 20) {
                        RingDial(progress: Double(r.score ?? 0) / 100, color: Palette.recovery(r.zone), lineWidth: 14) {
                            Text(r.score.map { "\($0)%" } ?? "—").font(.metric(26)).monospacedDigit()
                        }
                        .frame(width: 120, height: 120)
                        VStack(alignment: .leading, spacing: 6) {
                            if let zone = r.zone {
                                Label("Recuperación \(zone.label.lowercased())", systemImage: zone.symbol)
                                    .font(.headline).foregroundStyle(Palette.recovery(zone))
                            }
                            Text(statusText(r)).font(.subheadline).foregroundStyle(Palette.textSecondary)
                            ConfidenceBadge(confidence: r.confidence)
                        }
                    }
                    if let t = cycle.target {
                        InsightCard(text: "Carga objetivo de hoy: \(Format.decimal(t.low))–\(Format.decimal(t.high)).", symbol: "target",
                                    tint: Palette.strain)
                    }
                    Card {
                        SectionHeader(title: "Qué la explica", trailing: "frente a tu referencia")
                        ForEach(r.components) { c in
                            ComponentBar(component: c)
                        }
                    }
                    Card {
                        SectionHeader(title: "Últimos 30 días")
                        TrendChart(points: series(model, until: date, days: 30) { $0.recovery.score.map(Double.init) },
                                   color: Palette.recovery(r.zone), yDomain: 0...100, unit: "%")
                            .frame(height: 180)
                    }
                    Text("La recuperación compara tu VFC, tu FC en reposo, tu sueño y otros vitales de esta noche con tu referencia de las últimas 30–60 noches. No es una medida médica.")
                        .font(.footnote).foregroundStyle(Palette.textSecondary)
                }
                .padding(16)
            } else {
                ContentUnavailableView("Sin datos de este día", systemImage: "moon.zzz")
            }
        }
        .screenBackground()
        .navigationTitle("Recuperación")
    }

    private func statusText(_ r: RecoveryResult) -> String {
        switch r.status {
        case .ok: return "Basada en \(r.baselineNights) noches de referencia."
        case .calibrating(let n, let needed): return "Calibrando: \(n) de \(needed) noches."
        case .insufficient(let reason): return "Sin datos suficientes: \(reason)."
        }
    }
}

/// Barra divergente de la contribución de un componente.
struct ComponentBar: View {
    let component: RecoveryComponent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name).font(.subheadline.weight(.medium))
                Spacer()
                Text(TodayRecommendation.explain(component)).font(.caption).foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.separator).frame(height: 8)
                    Rectangle().fill(Palette.textSecondary.opacity(0.5)).frame(width: 2, height: 14)
                        .offset(x: geo.size.width / 2 - 1)
                    Capsule()
                        .fill(positive ? Palette.recoveryHigh : Palette.recoveryLow)
                        .frame(width: barWidth(geo.size.width), height: 8)
                        .offset(x: barOffset(geo.size.width))
                }
            }
            .frame(height: 14)
        }
        .accessibilityElement(children: .combine)
    }

    private var positive: Bool { component.contribution >= 0 }

    /// Ancho proporcional a |z| (saturado en 2,5), sobre la mitad de la barra.
    private func barWidth(_ full: CGFloat) -> CGFloat {
        let half: CGFloat = full / 2
        let fraction: Double = Swift.min(abs(component.z), 2.5) / 2.5
        return Swift.max(CGFloat(4), half * CGFloat(fraction))
    }

    private func barOffset(_ full: CGFloat) -> CGFloat {
        let half: CGFloat = full / 2
        return positive ? half : half - barWidth(full)
    }

    private var name: String {
        switch component.kind {
        case .hrv: return "VFC"
        case .restingHR: return "FC en reposo"
        case .sleep: return "Sueño"
        case .respiratoryRate: return "Frecuencia respiratoria"
        case .skinTemp: return "Temperatura"
        case .spo2: return "SpO₂"
        }
    }
}

// MARK: - Sueño

struct SleepDetailView: View {
    let date: LocalDate
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let cycle = model.output?.cycle(on: date), let s = cycle.sleep {
                    HStack(spacing: 20) {
                        RingDial(progress: s.performance / 100, color: Palette.sleep, lineWidth: 14) {
                            Text("\(Int(s.performance.rounded()))%").font(.metric(26)).monospacedDigit()
                        }
                        .frame(width: 120, height: 120)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Format.duration(minutes: s.asleepMin)).font(.metric(30))
                            Text("de \(Format.duration(minutes: s.need.totalMin)) que necesitabas").font(.subheadline)
                                .foregroundStyle(Palette.textSecondary)
                            Text(bandText(s.band)).font(.caption.weight(.semibold)).foregroundStyle(Palette.sleep)
                        }
                    }
                    if let session = cycle.sleepSession, session.hasStages {
                        Card {
                            SectionHeader(title: "Fases",
                                          trailing: "\(Format.clock(session.start, utcOffsetSeconds: session.utcOffsetSeconds))–\(Format.clock(session.end, utcOffsetSeconds: session.utcOffsetSeconds))")
                            Hypnogram(stages: session.stages)
                            HStack {
                                stage("Profundo", s.deepMin)
                                stage("REM", s.remMin)
                                stage("Ligero", s.lightMin)
                                stage("Despierto", s.wasoMin)
                            }
                        }
                    }
                    Card {
                        SectionHeader(title: "Detalle")
                        row("Suficiencia", Format.percent(s.sufficiency))
                        row("Eficiencia", Format.percent(s.efficiency))
                        if let c = s.consistency { row("Constancia", Format.percent(c)) }
                        row("Sueño reparador", "\(Format.duration(minutes: s.restorativeMin)) (\(Format.percent(s.restorativePct)))")
                        if let l = s.latencyMin { row("Tardaste en dormirte", Format.duration(minutes: l)) }
                        row("Despertares", "\(s.awakenings)")
                        row("Deuda de sueño", s.debtMin >= 1 ? Format.duration(minutes: s.debtMin) : "Ninguna")
                        if !cycle.naps.isEmpty { row("Siestas", "\(cycle.naps.count)") }
                    }
                    Card {
                        SectionHeader(title: "Por qué necesitabas \(Format.duration(minutes: s.need.totalMin))")
                        row("Base", Format.duration(minutes: s.need.baseMin))
                        row("Por la carga de ayer", signedMinutes(s.need.strainAdjMin))
                        row("Por la deuda", signedMinutes(s.need.debtAdjMin))
                        if s.need.napCreditMin > 0 { row("Siestas", signedMinutes(-s.need.napCreditMin)) }
                    }
                } else {
                    ContentUnavailableView("Sin sueño registrado", systemImage: "moon.zzz",
                                           description: Text("No llevabas la pulsera esta noche o aún no se ha sincronizado."))
                }
                SleepPlannerCard()
                Card {
                    SectionHeader(title: "Últimos 30 días")
                    TrendChart(points: series(model, until: date, days: 30) { $0.sleep.map { $0.asleepMin / 60 } },
                               color: Palette.sleep, unit: "h")
                        .frame(height: 180)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Sueño")
    }

    private func stage(_ name: String, _ minutes: Double) -> some View {
        VStack(spacing: 2) {
            Text(Format.duration(minutes: minutes)).font(.subheadline.weight(.semibold)).monospacedDigit()
            Text(name).font(.caption2).foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name).foregroundStyle(Palette.textSecondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.subheadline)
    }

    private func signedMinutes(_ m: Double) -> String { (m >= 0 ? "+" : "−") + Format.duration(minutes: abs(m)) }

    private func bandText(_ b: SleepBand) -> String {
        switch b {
        case .optimal: return "Óptimo"
        case .sufficient: return "Suficiente"
        case .poor: return "Bajo"
        }
    }
}

/// Planificador de sueño: hora recomendada para acostarse según el objetivo (doc. 11 §5).
struct SleepPlannerCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card {
            SectionHeader(title: "Planificador de esta noche")
            Picker("Objetivo", selection: Binding(get: { model.settings.plannerGoal }, set: { v in
                model.updateSettings { $0.plannerGoal = v }
                model.scheduleBedtimeReminder()
            })) {
                ForEach(SleepCalculator.PlannerGoal.allCases, id: \.rawValue) { g in
                    Text(g.label).tag(g.rawValue)
                }
            }
            .pickerStyle(.segmented)
            if let bed = model.tonightBedtimeMinutes, let need = model.output?.tonightNeed {
                HStack(alignment: .firstTextBaseline) {
                    Text("Acuéstate a las").foregroundStyle(Palette.textSecondary)
                    Text(Format.clock(minutes: bed)).font(.metric(34)).foregroundStyle(Palette.sleep)
                }
                Text("Necesitas \(Format.duration(minutes: need.totalMin)) para despertarte a las \(Format.clock(minutes: model.displayProfile.usualWakeMinutes)).")
                    .font(.footnote).foregroundStyle(Palette.textSecondary)
            } else {
                Text("Hace falta al menos una noche para calcularlo.").font(.footnote).foregroundStyle(Palette.textSecondary)
            }
            Toggle("Recordármelo 30 min antes", isOn: Binding(get: { model.settings.bedtimeReminder }, set: { v in
                model.updateSettings { $0.bedtimeReminder = v }
                model.scheduleBedtimeReminder()
            }))
            .font(.subheadline)
        }
    }
}

// MARK: - Carga

struct StrainDetailView: View {
    let date: LocalDate
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            if let output = model.output, let cycle = output.cycle(on: date) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 20) {
                        RingDial(progress: cycle.strain.strain / 21, color: Palette.strain, lineWidth: 14,
                                 target: cycle.target.map { ($0.low / 21)...($0.high / 21) }) {
                            Text(Format.decimal(cycle.strain.strain)).font(.metric(26)).monospacedDigit()
                        }
                        .frame(width: 120, height: 120)
                        VStack(alignment: .leading, spacing: 6) {
                            if let t = cycle.target {
                                Text("Objetivo \(Format.decimal(t.low))–\(Format.decimal(t.high))").font(.headline)
                                Text(targetText(t.status(of: cycle.strain.strain))).font(.subheadline).foregroundStyle(Palette.textSecondary)
                            }
                            ConfidenceBadge(confidence: cycle.strain.confidence)
                        }
                    }
                    Card {
                        SectionHeader(title: "Minutos por zona de FC")
                        ZoneBar(minutes: cycle.strain.zoneMinutes)
                    }
                    Card {
                        SectionHeader(title: "Frecuencia cardiaca del día")
                        HeartRateChart(samples: dayHR(output, cycle), zones: cycle.zones)
                    }
                    if !cycle.activities.isEmpty { ActivitiesCard(activities: cycle.activities) }
                    Card {
                        SectionHeader(title: "Carga aguda y crónica")
                        HStack {
                            metric("Aguda (7 d)", output.acuteLoad)
                            metric("Crónica (28 d)", output.chronicLoad)
                        }
                    }
                    Card {
                        SectionHeader(title: "Últimos 30 días")
                        TrendChart(points: series(model, until: date, days: 30) { $0.strain.strain }, color: Palette.strain, yDomain: 0...21)
                            .frame(height: 180)
                    }
                }
                .padding(16)
            } else {
                ContentUnavailableView("Sin datos de este día", systemImage: "figure.run")
            }
        }
        .screenBackground()
        .navigationTitle("Carga")
    }

    private func dayHR(_ output: MetricsOutput, _ cycle: CycleMetrics) -> [HeartRateChart.Sample] {
        let range = cycle.cycle.range(now: Date())
        let lo = range.start.minuteEpoch, hi = range.end.minuteEpoch
        let minutes = output.fusedHR.filter { $0.minute >= lo && $0.minute < hi }
        // Se reduce a una muestra cada 5 minutos para que el gráfico vaya fluido.
        return stride(from: 0, to: minutes.count, by: 5).map { i in
            let m = minutes[i]
            return HeartRateChart.Sample(time: Date(timeIntervalSince1970: TimeInterval(m.minute)), bpm: m.bpm, source: m.source)
        }
    }

    private func metric(_ name: String, _ value: Double?) -> some View {
        VStack(alignment: .leading) {
            Text(value.map { Format.decimal($0) } ?? "—").font(.metric(24)).monospacedDigit()
            Text(name).font(.caption).foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func targetText(_ s: TargetBand.Status) -> String {
        switch s {
        case .below: return "Aún por debajo del objetivo."
        case .within: return "Dentro del objetivo."
        case .above: return "Por encima del objetivo: cuida el descanso."
        }
    }
}

// MARK: - Salud

struct HealthDetailView: View {
    let date: LocalDate
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let cycle = model.output?.cycle(on: date) {
                    if cycle.health?.combinedAlert == true {
                        InsightCard(text: HealthMonitor.alertMessage, symbol: "exclamationmark.triangle", tint: Palette.recoveryMedium)
                    }
                    ForEach(vitals, id: \.name) { v in
                        Card {
                            SectionHeader(title: v.name, trailing: v.unit)
                            let pts = series(model, until: date, days: 30) { $0.vitals?[keyPath: v.key] }
                            let usual = model.usualVital(v.key, before: date)
                            TrendChart(points: pts, color: v.color, band: band(pts, usual: usual), unit: v.unit)
                                .frame(height: 140)
                        }
                    }
                    StressCard(cycle: cycle)
                }
                if let pa = model.output?.physioAge {
                    Card {
                        SectionHeader(title: "Edad fisiológica", trailing: pa.calibrated ? nil : "estimación preliminar")
                        HStack(alignment: .firstTextBaseline) {
                            Text(Format.decimal(pa.estimate)).font(.metric(40)).monospacedDigit()
                            Text("años").foregroundStyle(Palette.textSecondary)
                        }
                        Text("Entre \(Format.decimal(pa.bandLow)) y \(Format.decimal(pa.bandHigh)) años.").font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                        ForEach(pa.factors) { f in
                            HStack {
                                Text(f.label).font(.subheadline)
                                Spacer()
                                Text(f.value).font(.subheadline).foregroundStyle(Palette.textSecondary)
                                Text(Format.signed(f.deltaYears, digits: 1)).font(.subheadline.weight(.semibold)).monospacedDigit()
                                    .foregroundStyle(f.deltaYears <= 0 ? Palette.recoveryHigh : Palette.recoveryMedium)
                            }
                        }
                        Text("Es una estimación de bienestar a partir de tus hábitos y vitales, no una medida médica.")
                            .font(.caption).foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Salud")
    }

    struct VitalSeries {
        var name: String
        var unit: String
        var key: KeyPath<NightlyVitals, Double?>
        var color: Color
    }

    private var vitals: [VitalSeries] {
        [VitalSeries(name: "VFC", unit: "ms", key: \.hrvRmssdAvg, color: Palette.recoveryHigh),
         VitalSeries(name: "FC en reposo", unit: "lpm", key: \.restingHR, color: Palette.recoveryLow),
         VitalSeries(name: "Frecuencia respiratoria", unit: "rpm", key: \.respiratoryRate, color: Palette.strain),
         VitalSeries(name: "SpO₂", unit: "%", key: \.spo2Avg, color: Palette.sleep),
         VitalSeries(name: "Temperatura de la piel", unit: "°C", key: \.skinTempC, color: Palette.stress)]
    }

    private func band(_ points: [DayPoint], usual: Double?) -> ClosedRange<Double>? {
        let values = points.map(\.value)
        guard let usual, values.count >= 7, let sigma = Stats.robustSigma(values), sigma > 0 else { return nil }
        return (usual - sigma)...(usual + sigma)
    }
}
