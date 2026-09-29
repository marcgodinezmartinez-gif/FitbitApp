import SwiftUI
import Charts
import MetricsKit
import Insights
import Store
import RunKit
import CoachKit

/// Análisis completo de una carrera con todo lo que dan el Apple Watch y la Fitbit Air (doc. 18 §5). Nunca se envían
/// coordenadas a la IA.
struct RunDetailView: View {
    let runID: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var loaded: LoadedRun?
    @State private var loading = true
    @State private var mapMetric: RouteColorMetric = .pace
    @State private var chartMetric: RunChartMetric = .pace
    @State private var byDistance = true
    @State private var confirmDelete = false
    @State private var gpxURL: URL?

    var run: FusedActivity? { model.output?.fusedActivities.first { $0.id == runID } }

    var body: some View {
        ScrollView {
            if let run {
                VStack(alignment: .leading, spacing: 16) {
                    RunHeader(run: run, summary: model.runs.summary(runID), history: model.runs.history)
                    if let loaded {
                        content(run: run, loaded: loaded)
                    } else if loading {
                        ProgressView("Analizando la carrera…").frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else {
                        StateCard(symbol: "exclamationmark.triangle", title: "No se pudo analizar", message: "Faltan los datos de esta carrera.")
                    }
                    if run.primary.source == .manual && !model.settings.demoMode {
                        Button("Borrar esta actividad", role: .destructive) { confirmDelete = true }
                            .frame(maxWidth: .infinity).font(.subheadline)
                    }
                }
                .padding(16)
            } else {
                ContentUnavailableView("Carrera no encontrada", systemImage: "figure.run")
            }
        }
        .screenBackground()
        .navigationTitle(run?.name ?? "Carrera")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = gpxURL {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Exportar GPX")
                }
            }
        }
        .task(id: "\(runID)-\(model.dataVersion)") {
            guard let run else { loading = false; return }
            if model.runs.summaries.isEmpty { await model.runs.refresh(model: model) }
            loaded = await model.runs.load(run, model: model)
            if let loaded, !loaded.input.route.isEmpty { gpxURL = gpxFile(loaded) }
            loading = false
        }
        .confirmationDialog("¿Borrar esta actividad?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Borrar", role: .destructive) {
                Task {
                    await model.deleteManualActivity(id: runID)
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private func content(run: FusedActivity, loaded: LoadedRun) -> some View {
        let r = loaded.analysis
        if !loaded.input.route.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                RunRouteMap(route: loaded.input.route, series: loaded.series, metric: mapMetric)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                Picker("Color", selection: $mapMetric) {
                    ForEach(RouteColorMetric.allCases.filter { $0.available(in: loaded.series) }) { m in Text(m.label).tag(m) }
                }
                .pickerStyle(.segmented)
            }
        }
        RunSummaryGrid(analysis: r, run: run)
        RunAICard(run: run, analysis: r)
        RunChartsCard(analysis: r, metric: $chartMetric, byDistance: $byDistance, zones: loaded.input.zones)
        if !r.splits.isEmpty { RunSplitsCard(splits: r.splits) }
        if !r.laps.isEmpty { RunLapsCard(laps: r.laps) }
        RunZonesDetailCard(analysis: r)
        if !r.bestEfforts.isEmpty { RunBestEffortsCard(analysis: r, run: run) }
        if r.paceCurve.count >= 2 || r.powerCurve.count >= 2 { RunCurvesCard(analysis: r) }
        if !r.climbs.isEmpty { RunClimbsCard(climbs: r.climbs) }
        RunEfficiencyCard(analysis: r)
        if !r.form.isEmpty { RunFormCard(form: r.form) }
        if let c = r.comparison { RunComparisonCard(comparison: c) }
        if let w = r.weather, !w.isEmpty { RunWeatherCard(weather: w) }
        RunSimilarCard(runID: runID)
        RunNotesCard(run: run)
        RunSourcesCard(run: run, analysis: r)
    }

    /// GPX en un fichero temporal para compartirlo.
    private func gpxFile(_ loaded: LoadedRun) -> URL? {
        let date = LocalDate(loaded.input.activity.start, utcOffsetSeconds: loaded.input.activity.primary.utcOffsetSeconds)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Recupera-\(date.isoString).gpx")
        let text = GPXWriter.gpx(name: loaded.input.activity.name, route: loaded.input.route, series: loaded.series)
        do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { return nil }
        return url
    }
}

// MARK: - Cabecera y cifras

struct RunHeader: View {
    let run: FusedActivity
    let summary: RunSummary?
    let history: RunHistory

    var body: some View {
        let date = LocalDate(run.start, utcOffsetSeconds: run.primary.utcOffsetSeconds)
        let records = summary.map { history.personalRecords(in: $0) } ?? []
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Image(systemName: run.kind.symbolName).font(.title).foregroundStyle(Palette.strain)
                    .frame(width: 56, height: 56).background(Palette.strain.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(run.name).font(.title3.weight(.bold))
                    Text("\(Format.longDate(date)) · \(Format.clock(run.start, utcOffsetSeconds: run.primary.utcOffsetSeconds))")
                        .font(.subheadline).foregroundStyle(Palette.textSecondary)
                    SourceBadges(sources: run.sources)
                }
            }
            if !records.isEmpty {
                HStack(spacing: 6) {
                    PRBadge()
                    Text(records.map(\.label).joined(separator: " · ")).font(.caption.weight(.semibold)).foregroundStyle(Palette.recoveryMedium)
                }
            }
        }
    }
}

struct RunSummaryGrid: View {
    let analysis: RunAnalysis
    let run: FusedActivity

    private var items: [(String, String)] {
        let r = analysis
        var items: [(String, String)] = [("Distancia", RunFormat.distance(r.distanceM)), ("Tiempo en movimiento", RunFormat.time(r.movingS)),
                                         ("Ritmo medio", "\(RunFormat.pace(r.avgPace)) /km")]
        if let gap = r.avgGAP, let pace = r.avgPace, abs(gap - pace) >= 2 { items.append(("Ritmo ajustado (GAP)", "\(RunFormat.pace(gap)) /km")) }
        if r.pausedS > 5 { items.append(("Tiempo total", "\(RunFormat.time(r.elapsedS)) · \(r.pauses) pausa\(r.pauses == 1 ? "" : "s")")) }
        if let hr = r.avgHR { items.append(("FC media / máx.", "\(Int(hr.rounded())) / \(RunFormat.number(r.maxHR))")) }
        if let v = r.maxSpeed { items.append(("Ritmo más rápido", "\(RunFormat.paceFromSpeed(v)) /km")) }
        if let g = r.elevationGainM { items.append(("Desnivel", "+\(Int(g.rounded())) / −\(RunFormat.number(r.elevationLossM)) m")) }
        if let c = r.avgCadence { items.append(("Cadencia", "\(Int(c.rounded())) ppm")) }
        if let p = r.avgPower { items.append(("Potencia", "\(Int(p.rounded())) W")) }
        if let s = r.avgStride { items.append(("Zancada", "\(Format.decimal(s, digits: 2)) m")) }
        if let kcal = r.caloriesKcal { items.append(("Calorías", "\(Int(kcal.rounded())) kcal")) }
        if let t = r.trimp { items.append(("Carga (TRIMP)", "\(Int(t.rounded()))")) }
        if let s = r.stressScore { items.append(("Estrés (rTSS)", "\(Int(s.rounded()))")) }
        if let v = r.vo2maxEstimate { items.append(("VO₂ máx. estimado", Format.decimal(v))) }
        if let rec = run.watchMember?.hrRecovery1Min { items.append(("Recuperación FC 1 min", "\(Int(rec.rounded())) lpm")) }
        if let e = run.watchMember?.effortScore { items.append(("Esfuerzo (Apple)", "\(Format.decimal(e)) / 10")) }
        return items
    }

    var body: some View { RunStatGrid(items: items) }
}

// MARK: - IA

struct RunAICard: View {
    let run: FusedActivity
    let analysis: RunAnalysis
    @Environment(AppModel.self) private var model
    @State private var report: AIReport?
    @State private var working = false
    @State private var error: String?

    var body: some View {
        Card {
            SectionHeader(title: "Análisis del entrenador", trailing: report.map { $0.provider == "demo" ? "ejemplo" : "IA" })
            if let n = report?.run {
                Text(n.titular).font(.headline)
                Text(n.resumen).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                ForEach(n.puntosFuertes, id: \.self) { p in
                    Label(p, systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(Palette.recoveryHigh)
                }
                ForEach(n.aMejorar, id: \.self) { p in
                    Label(p, systemImage: "arrow.up.forward.circle.fill").font(.subheadline).foregroundStyle(Palette.recoveryMedium)
                }
                Label(n.proximaSesion, systemImage: "calendar").font(.subheadline.weight(.semibold))
                if report?.provider != "demo" {
                    Button("Volver a analizar") { Task { await write(force: true) } }.font(.footnote).disabled(working)
                }
            } else if !model.settings.coachEnabled && !model.settings.demoMode {
                Text("Activa el Coach IA en Perfil para que analice cada carrera: qué salió bien, qué mejorar y tu próxima sesión.")
                    .font(.subheadline).foregroundStyle(Palette.textSecondary)
            } else {
                Text("Resumen, puntos fuertes, qué mejorar y tu próxima sesión, a partir de todos los datos de la carrera.")
                    .font(.subheadline).foregroundStyle(Palette.textSecondary)
                Button(working ? "Analizando…" : "Analizar con IA") { Task { await write(force: false) } }
                    .buttonStyle(.borderedProminent).disabled(working)
            }
            if let error { Text(error).font(.footnote).foregroundStyle(Palette.recoveryLow) }
        }
        .task(id: run.id) {
            report = model.runs.savedReport(for: run.id, model: model)
            if report == nil, AppModel.screenshotScreen == "run" { await write(force: false) }
        }
    }

    private func write(force: Bool) async {
        working = true
        error = nil
        defer { working = false }
        do {
            report = try await model.runs.writeReport(run: run, analysis: analysis, model: model, force: force)
        } catch let e as LocalizedError {
            error = e.errorDescription ?? "No se pudo analizar."
        } catch {
            self.error = "No se pudo analizar: \(error.localizedDescription)"
        }
    }
}

// MARK: - Gráficas

struct RunChartsCard: View {
    let analysis: RunAnalysis
    @Binding var metric: RunChartMetric
    @Binding var byDistance: Bool
    let zones: HRZones

    private var available: [RunChartMetric] {
        RunChartMetric.allCases.filter { m in analysis.chart.contains { m.value($0) != nil } }
    }

    var body: some View {
        Card {
            HStack {
                Text("Gráficas").font(.headline)
                Spacer()
                Picker("Eje", selection: $byDistance) {
                    Text("km").tag(true)
                    Text("min").tag(false)
                }
                .pickerStyle(.segmented).frame(width: 110)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(available) { m in
                        Button { metric = m } label: {
                            Text(m.label).font(.caption.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .foregroundStyle(metric == m ? Color.white : Palette.textPrimary)
                                .background(metric == m ? m.color : Palette.surfaceElevated, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            RunMetricChart(points: analysis.chart, metric: available.contains(metric) ? metric : (available.first ?? .pace),
                           byDistance: byDistance && analysis.distanceSource != .none, zones: zones)
            if metric == .pace {
                Text("Línea discontinua: ritmo ajustado por pendiente (lo que valdría ese esfuerzo en llano).")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
            }
        }
    }
}

// MARK: - Parciales y vueltas

struct RunSplitsCard: View {
    let splits: [RunSplit]

    var body: some View {
        let paces = splits.map(\.pace)
        let fastest = paces.min() ?? 0, slowest = paces.max() ?? 1
        Card {
            SectionHeader(title: "Parciales", trailing: "por km")
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    header("Km")
                    header("Ritmo")
                    header("")
                    header("GAP")
                    header("FC")
                    header("Desn.")
                }
                ForEach(splits) { s in
                    GridRow {
                        Text(s.distanceM < 999 ? Format.decimal(Double(s.index - 1) + s.distanceM / 1000, digits: 1) : "\(s.index)")
                            .font(.subheadline).monospacedDigit()
                        Text(RunFormat.pace(s.pace)).font(.subheadline).monospacedDigit().fontWeight(s.pace == fastest ? .bold : .regular)
                        bar(s.pace, fastest: fastest, slowest: slowest)
                        Text(RunFormat.pace(s.gapPace)).font(.subheadline).monospacedDigit().foregroundStyle(Palette.textSecondary)
                        Text(RunFormat.number(s.avgHR)).font(.subheadline).monospacedDigit()
                        Text(s.elevationGainM >= 1 || s.elevationLossM >= 1 ? Format.signed(s.elevationGainM - s.elevationLossM) : "–")
                            .font(.subheadline).monospacedDigit().foregroundStyle(Palette.textSecondary)
                    }
                }
            }
        }
    }

    private func header(_ text: String) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(Palette.textSecondary)
    }

    private func bar(_ pace: Double, fastest: Double, slowest: Double) -> some View {
        let span = max(slowest - fastest, 1)
        let share = 1 - (pace - fastest) / span * 0.7   // el más lento, al 30 %
        return Capsule().fill(Palette.strain.opacity(0.8)).frame(width: 60 * share, height: 8)
            .frame(width: 60, alignment: .leading)
    }
}

struct RunLapsCard: View {
    let laps: [RunLap]

    var body: some View {
        Card {
            SectionHeader(title: laps.first?.kind == "interval" ? "Intervalos" : "Vueltas",
                          trailing: laps.first?.source == .googleHealth ? "Fitbit Air" : "Apple Watch")
            ForEach(laps) { l in
                HStack {
                    Text("\(l.index)").font(.caption.weight(.bold)).frame(width: 22)
                    Text(RunFormat.time(l.seconds)).monospacedDigit()
                    Spacer()
                    if let d = l.distanceM { Text(RunFormat.distance(d)).monospacedDigit().foregroundStyle(Palette.textSecondary) }
                    Text("\(RunFormat.pace(l.pace)) /km").monospacedDigit()
                    Text(RunFormat.number(l.avgHR, unit: "lpm")).monospacedDigit().foregroundStyle(Palette.textSecondary)
                }
                .font(.subheadline)
            }
        }
    }
}

// MARK: - Zonas

struct RunZonesDetailCard: View {
    let analysis: RunAnalysis

    var body: some View {
        let r = analysis
        Card {
            SectionHeader(title: "Zonas")
            if r.hrZoneSeconds.reduce(0, +) > 0 {
                Text("Frecuencia cardiaca").font(.subheadline.weight(.semibold))
                ZoneBar(minutes: r.hrZoneSeconds.map { Int(($0 / 60).rounded()) })
            }
            if let pz = r.paceZoneSeconds, pz.reduce(0, +) > 0 {
                Text("Ritmo").font(.subheadline.weight(.semibold)).padding(.top, 4)
                LabeledZoneBar(seconds: pz, labels: ["Rec.", "E", "M", "T", "I", "R"], colors: Palette.zones)
            }
            if let wz = r.powerZoneSeconds, wz.reduce(0, +) > 0 {
                Text("Potencia").font(.subheadline.weight(.semibold)).padding(.top, 4)
                LabeledZoneBar(seconds: wz, labels: ["Suave", "Moder.", "Umbral", "Interv.", "Máx."], colors: Array(Palette.zones.dropFirst()))
            }
        }
    }
}

// MARK: - Mejores marcas y curvas

struct RunBestEffortsCard: View {
    let analysis: RunAnalysis
    let run: FusedActivity
    @Environment(AppModel.self) private var model

    var body: some View {
        let records = model.runs.summary(run.id).map { model.runs.history.personalRecords(in: $0) } ?? []
        Card {
            SectionHeader(title: "Mejores marcas", trailing: "dentro de esta carrera")
            ForEach(analysis.bestEfforts) { e in
                HStack {
                    Text(e.distance.label)
                    if records.contains(e.distance) { PRBadge() }
                    Spacer()
                    Text("\(RunFormat.pace(e.seconds / e.distance.rawValue * 1000)) /km").font(.caption).foregroundStyle(Palette.textSecondary)
                    Text(RunFormat.time(e.seconds)).font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                .font(.subheadline)
            }
        }
    }
}

struct RunCurvesCard: View {
    let analysis: RunAnalysis

    var body: some View {
        Card {
            if analysis.paceCurve.count >= 2 {
                SectionHeader(title: "Curva de ritmo", trailing: "mejor ritmo sostenido")
                CurveChart(points: analysis.paceCurve, isPace: true)
            }
            if analysis.powerCurve.count >= 2 {
                SectionHeader(title: "Curva de potencia", trailing: "mejor media en W")
                CurveChart(points: analysis.powerCurve, isPace: false)
            }
        }
    }
}

struct RunClimbsCard: View {
    let climbs: [Climb]

    var body: some View {
        Card {
            SectionHeader(title: "Subidas", trailing: "\(climbs.count)")
            ForEach(climbs) { c in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Km \(Format.decimal(c.startKm))").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("+\(Int(c.gainM.rounded())) m · \(Format.decimal(c.avgGradePct)) %").font(.subheadline).monospacedDigit()
                    }
                    Text("\(RunFormat.distance(c.lengthM)) en \(RunFormat.time(c.seconds)) · VAM \(Int(c.vam.rounded())) m/h")
                        .font(.caption).foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }
}

// MARK: - Eficiencia, técnica y fuentes

struct RunEfficiencyCard: View {
    let analysis: RunAnalysis

    private var decouplingText: String? {
        guard let d = analysis.decouplingPct else { return nil }
        switch d {
        case ..<5: return "Menos del 5 %: buena base aeróbica para este ritmo y esta duración."
        case 5..<10: return "Entre el 5 y el 10 %: algo de deriva; puede ser el calor, la hidratación o que el ritmo roza tu límite aeróbico."
        default: return "Más del 10 %: mucha deriva. Baja el ritmo en las tiradas largas o revisa hidratación y calor."
        }
    }

    var body: some View {
        let r = analysis
        if r.efficiencyFactor != nil || r.decouplingPct != nil || r.intensityFactor != nil {
            Card {
                SectionHeader(title: "Eficiencia aeróbica")
                if let ef = r.efficiencyFactor { RunRow(name: "Eficiencia", value: Format.decimal(ef, digits: 2), detail: "m/min por latido") }
                if let d = r.decouplingPct { RunRow(name: "Desacoplamiento (Pa:FC)", value: "\(Format.decimal(d)) %") }
                if let dr = r.hrDriftPct { RunRow(name: "Deriva de FC", value: "\(Format.signed(dr, digits: 1)) %") }
                if let i = r.intensityFactor { RunRow(name: "Intensidad frente a tu umbral", value: "\(Int((i * 100).rounded())) %") }
                if let text = decouplingText { Text(text).font(.caption).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }
}

struct RunFormCard: View {
    let form: [FormMetric]

    private func value(_ f: FormMetric) -> String {
        switch f.metric {
        case .cadence: return "\(Int(f.value.rounded())) ppm"
        case .groundContact: return "\(Int(f.value.rounded())) ms"
        case .verticalOsc: return "\(Format.decimal(f.value)) cm"
        case .verticalRatio: return "\(Format.decimal(f.value)) %"
        case .stride: return "\(Format.decimal(f.value, digits: 2)) m"
        case .power: return "\(Int(f.value.rounded())) W"
        }
    }

    var body: some View {
        Card {
            SectionHeader(title: "Técnica de carrera")
            ForEach(form) { f in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(f.metric.label).font(.subheadline)
                        RatingBadge(rating: f.rating)
                        Spacer()
                        Text(value(f)).font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                    Text(f.note).font(.caption).foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }
}

struct RunComparisonCard: View {
    let comparison: SourceComparison

    private func row(_ name: String, _ watch: String?, _ fitbit: String?) -> some View {
        GridRow {
            Text(name).font(.subheadline).foregroundStyle(Palette.textSecondary)
            Text(watch ?? "–").font(.subheadline).monospacedDigit()
            Text(fitbit ?? "–").font(.subheadline).monospacedDigit()
        }
    }

    var body: some View {
        let c = comparison
        Card {
            SectionHeader(title: "Apple Watch frente a Fitbit Air")
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    Label("Watch", systemImage: DataSourceKind.appleHealth.symbol).font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                    Label("Fitbit", systemImage: DataSourceKind.googleHealth.symbol).font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                }
                row("Distancia", c.watchDistanceM.map { RunFormat.distance($0) }, c.fitbitDistanceM.map { RunFormat.distance($0) })
                row("FC media", c.watchAvgHR.map { "\(Int($0.rounded())) lpm" }, c.fitbitAvgHR.map { "\(Int($0.rounded())) lpm" })
                row("Cadencia", c.watchCadence.map { "\(Int($0.rounded())) ppm" }, c.fitbitCadence.map { "\(Int($0.rounded())) ppm" })
                row("Calorías", c.watchCalories.map { "\(Int($0.rounded()))" }, c.fitbitCalories.map { "\(Int($0.rounded()))" })
                if c.fitbitVO2max != nil { row("VO₂ máx. de la carrera", nil, c.fitbitVO2max.map { Format.decimal($0) }) }
                if c.fitbitActiveZoneMinutes != nil { row("Minutos en zona activa", nil, c.fitbitActiveZoneMinutes.map { "\(Int($0))" }) }
            }
            if let bias = c.hrBias, let lo = c.hrLoaLow, let hi = c.hrLoaHigh, let minutes = c.overlapMinutes {
                Text("En \(Int(minutes.rounded())) min con las dos, el Watch marca de media \(Format.signed(bias, digits: 1)) lpm respecto a la Fitbit (el 95 % de las veces entre \(Format.signed(lo)) y \(Format.signed(hi))).")
                    .font(.caption).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct RunWeatherCard: View {
    let weather: WeatherInfo

    var body: some View {
        Card {
            SectionHeader(title: "Tiempo", trailing: "según el Apple Watch")
            HStack(spacing: 20) {
                if let t = weather.temperatureC { Label("\(Int(t.rounded())) °C", systemImage: "thermometer.medium") }
                if let h = weather.humidityPct { Label("\(Int(h.rounded())) %", systemImage: "humidity") }
                if let c = weather.condition { Label(c, systemImage: "cloud.sun") }
            }
            .font(.subheadline)
            if let t = weather.temperatureC, t >= 22 {
                Text("Con calor el pulso sube y el ritmo baja para el mismo esfuerzo: no compares esta carrera con las de días frescos.")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
            }
        }
    }
}

struct RunSimilarCard: View {
    let runID: String
    @Environment(AppModel.self) private var model

    var body: some View {
        let runs = model.runs
        if let me = runs.summary(runID) {
            let similar = runs.history.similar(to: me, limit: 5)
            if !similar.isEmpty {
                Card {
                    SectionHeader(title: "Carreras parecidas", trailing: "misma zona o distancia")
                    ForEach(similar) { s in
                        NavigationLink(value: DetailRoute.run(s.id)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(RunFormat.date(s)).font(.subheadline).foregroundStyle(Palette.textPrimary)
                                    Text("\(RunFormat.distance(s.distanceM)) · \(RunFormat.number(s.avgHR, unit: "lpm"))")
                                        .font(.caption).foregroundStyle(Palette.textSecondary)
                                }
                                Spacer()
                                if let a = me.avgPace, let b = s.avgPace {
                                    Text(Format.signed(b - a) + " s/km").font(.caption).monospacedDigit()
                                        .foregroundStyle(b > a ? Palette.recoveryHigh : Palette.recoveryLow)
                                }
                                Text("\(RunFormat.pace(s.avgPace)) /km").font(.subheadline.weight(.semibold)).monospacedDigit()
                                    .foregroundStyle(Palette.textPrimary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if let ef = me.efficiency, let others = Stats.mean(similar.compactMap(\.efficiency)) {
                        Text(ef >= others ? "Hoy has sido más eficiente que en tus carreras parecidas (\(Format.decimal(ef, digits: 2)) frente a \(Format.decimal(others, digits: 2)))."
                                          : "Hoy has sido menos eficiente que en tus carreras parecidas (\(Format.decimal(ef, digits: 2)) frente a \(Format.decimal(others, digits: 2))).")
                            .font(.caption).foregroundStyle(Palette.textSecondary)
                    }
                }
            }
        }
    }
}

struct RunNotesCard: View {
    let run: FusedActivity
    @Environment(AppModel.self) private var model
    @State private var rpe: Double = 5
    @State private var rpeSet = false

    var body: some View {
        let runs = model.runs
        let shoeID = runs.summary(run.id).flatMap { runs.shoeID(for: $0) } ?? runs.assignments[run.id]
        Card {
            SectionHeader(title: "¿Cuánto te costó?", trailing: "RPE 0–10")
            Slider(value: $rpe, in: 0...10, step: 1) { editing in
                if !editing {
                    rpeSet = true
                    Task { await model.saveRPE(rpe, activity: run) }
                }
            }
            .tint(Palette.strain)
            Text(rpeSet || run.rpe != nil ? "Tu valoración: \(Int(rpe))" : "Desliza para valorar el esfuerzo")
                .font(.footnote).foregroundStyle(Palette.textSecondary)
            if !runs.shoes.isEmpty {
                Divider()
                Picker("Zapatillas", selection: Binding(get: { shoeID ?? "" }, set: { new in
                    runs.assign(shoeID: new.isEmpty ? nil : new, to: run, model: model)
                })) {
                    Text("Sin asignar").tag("")
                    ForEach(runs.shoes.filter { !$0.retired || $0.id == shoeID }) { s in Text(s.name).tag(s.id) }
                }
            }
        }
        .onAppear {
            if let r = run.rpe { rpe = r; rpeSet = true }
        }
    }
}

struct RunSourcesCard: View {
    let run: FusedActivity
    let analysis: RunAnalysis

    var body: some View {
        Card {
            SectionHeader(title: "Datos")
            RunRow(name: "Distancia", value: analysis.distanceSource.label)
            RunRow(name: "Frecuencia cardiaca", value: analysis.hrSource.map { $0.label } ?? "Sin datos")
            ForEach(run.members, id: \.id) { m in
                HStack {
                    Image(systemName: m.source.symbol)
                    Text(m.source.label)
                    Spacer()
                    Text("\(Format.clock(m.start, utcOffsetSeconds: m.utcOffsetSeconds))–\(Format.clock(m.end, utcOffsetSeconds: m.utcOffsetSeconds))")
                        .foregroundStyle(Palette.textSecondary).monospacedDigit()
                }
                .font(.subheadline)
            }
            if run.members.count > 1 {
                Text("Las dos sesiones se han fusionado en una sola carrera: la FC y la dinámica salen del Watch y la Fitbit completa y compara.")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
            }
        }
    }
}
