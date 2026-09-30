import SwiftUI
import Charts
import MetricsKit
import Insights
import Store
import RunKit
import SyncKit

/// Pestaña «Correr» (doc. 18): volumen, forma, rendimiento, récords, tendencias, zonas, zapatillas y todas tus carreras.
struct RunsHubView: View {
    @Environment(AppModel.self) private var model
    @State private var volumeScale: RunVolumeScale = .weeks
    @State private var trendMetric: RunTrendMetric = .efficiency
    @State private var openRun: String?
    @State private var openSession: PlannedSession?

    var body: some View {
        let runs = model.runs
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if runs.summaries.isEmpty {
                        if runs.isLoading {
                            ProgressView("Analizando tus carreras…").frame(maxWidth: .infinity).padding(.top, 80)
                        } else {
                            StateCard(symbol: "figure.run", title: "Aún no hay carreras",
                                      message: "Cuando corras con el Apple Watch o con la Fitbit Air, aquí verás cada carrera analizada al detalle, tu forma, tus récords y tus predicciones.")
                        }
                    } else {
                        if model.historyRunning, let h = model.history, !h.isComplete {
                            HistoryBanner(state: h)
                        }
                        RunWeekHeader(runs: runs)
                        TrainingCard(runs: runs).id("training")
                        GoalRaceCard(runs: runs).id("goal")
                        RunVolumeCard(runs: runs, scale: $volumeScale)
                        RunFitnessCard(runs: runs)
                        if let risk = runs.risk { RunRiskCard(risk: risk, runs: runs).id("risk") }
                        RunPerformanceCard(runs: runs).id("performance")
                        RunVO2Card(runs: runs)
                        RunRecordsCard(runs: runs).id("records")
                        SegmentsCard(runs: runs).id("segments")
                        RunTrendsCard(runs: runs, metric: $trendMetric)
                        RunZonesCard(runs: runs, zones: model.output?.current?.zones)
                        RunShoesCard(runs: runs)
                        RunListSection(runs: runs)
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Correr")
            .detailDestinations()
            .navigationDestination(item: $openRun) { id in RunDetailView(runID: id) }
            .navigationDestination(item: $openSession) { s in WorkoutDetailView(workout: s.workout, date: s.date) }
            .task(id: model.dataVersion) {
                await runs.refresh(model: model)
                guard let screen = AppModel.screenshotScreen else { return }
                if screen == "run" || screen.hasPrefix("run-"), openRun == nil {
                    // Para la captura de las series, una carrera de series; para la de segmentos, una que pase por alguno.
                    var wanted: RunSummary?
                    if screen == "run-intervals" { wanted = runs.summaries.last { $0.intervalLabel != nil && $0.startLat != nil } }
                    if screen == "run-segments" { wanted = runs.summaries.last { !runs.efforts(runID: $0.id, model: model).isEmpty } }
                    openRun = wanted?.id ?? runs.summaries.last { $0.startLat != nil }?.id ?? runs.summaries.last?.id
                } else if screen == "runs-workout", openSession == nil, let plan = runs.plan {
                    // El próximo entreno de calidad del plan, con sus pasos y ritmos.
                    let upcoming = plan.sessions.filter { $0.date >= runs.today }
                    openSession = upcoming.first { $0.workout.kind.isQuality && $0.workout.kind != .race } ?? upcoming.first
                } else if screen.hasPrefix("runs-") {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    proxy.scrollTo(String(screen.dropFirst(5)), anchor: .top)
                }
            }
            .refreshable { await model.sync(.pull) }
        }
    }
}

/// Mientras llega el historial completo: las carreras antiguas van apareciendo.
struct HistoryBanner: View {
    let state: HistoryImportState

    private var detail: String {
        var text = "Paso \(state.step) de 4 · " + state.phaseLabel
        if let oldest = state.oldestData { text += " · desde " + oldest.formatted(.dateTime.year()) }
        return text
    }

    var body: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("Trayendo tu historial completo").font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(Palette.textSecondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Semana

struct RunWeekHeader: View {
    let runs: RunsModel

    var body: some View {
        let today = runs.today
        let week = runs.history.weeks(count: 1, today: today).last
        let streak = runs.history.weekStreak(today: today)
        let year = runs.history.totals(from: LocalDate(year: today.year, month: 1, day: 1), to: today)
        Card {
            SectionHeader(title: "Esta semana", trailing: streak > 1 ? "\(streak) semanas seguidas corriendo" : nil)
            HStack(alignment: .bottom) {
                BigNumber(value: Format.decimal((week?.distanceM ?? 0) / 1000), unit: "km",
                          caption: "\(RunFormat.count(week?.runs ?? 0, "carrera", "carreras")) · \(Format.duration(minutes: (week?.movingS ?? 0) / 60))")
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int((year.distanceM / 1000).rounded())) km").font(.metric(22, weight: .semibold)).monospacedDigit()
                    Text("en \(String(today.year)) · \(RunFormat.count(year.runs, "carrera", "carreras"))").font(.caption).foregroundStyle(Palette.textSecondary)
                }
            }
            // Con historial de más de un año: lo de siempre.
            if let first = runs.summaries.first?.date, first.year < today.year {
                let all = runs.history.totals(from: first, to: today)
                Text("Desde \(Format.monthName(first.month)) de \(String(first.year)): \(Format.thousands(all.distanceM / 1000)) km en \(RunFormat.count(all.runs, "carrera", "carreras")).")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
            }
        }
    }
}

/// Escala del volumen: semanas, meses o años.
enum RunVolumeScale: String, CaseIterable, Identifiable {
    case weeks, months, years
    var id: String { rawValue }
    var label: String {
        switch self {
        case .weeks: return "Semanas"
        case .months: return "Meses"
        case .years: return "Años"
        }
    }
}

/// Periodo de las gráficas largas (VO₂ máx. y tendencias).
enum RunRange: Int, CaseIterable, Identifiable {
    case halfYear = 180, year = 365, all = 36_500
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .halfYear: return "6 meses"
        case .year: return "1 año"
        case .all: return "Todo"
        }
    }
}

// MARK: - Volumen

struct RunVolumeCard: View {
    let runs: RunsModel
    @Binding var scale: RunVolumeScale

    private var periods: [RunPeriod] {
        switch scale {
        case .weeks: return runs.history.weeks(count: 12, today: runs.today)
        case .months: return runs.history.months(count: 12, today: runs.today)
        case .years:
            let first = runs.summaries.first?.date.year ?? runs.today.year
            return runs.history.years(count: max(2, min(15, runs.today.year - first + 1)), today: runs.today)
        }
    }

    var body: some View {
        let list = periods
        let average = list.map(\.distanceM).reduce(0, +) / Double(max(1, list.count)) / 1000
        Card {
            SectionHeader(title: "Volumen", trailing: "media \(Format.decimal(average)) km")
            Picker("Periodo", selection: $scale) {
                ForEach(RunVolumeScale.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            VolumeChart(periods: list, scale: scale)
            if let last = list.last, last.runs > 0 {
                let name = scale == .weeks ? "Esta semana" : (scale == .months ? "Este mes" : "Este año")
                Text("\(name): tirada más larga de \(RunFormat.distance(last.longestM)) y \(Format.thousands(last.elevationM)) m de desnivel.")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
            }
        }
    }
}

// MARK: - Forma

struct RunFitnessCard: View {
    let runs: RunsModel

    static func advice(_ points: [FitnessPoint]) -> String {
        guard let last = points.last else { return "" }
        let week = points.count > 7 ? last.fitness - points[points.count - 8].fitness : 0
        var text: String
        switch last.form {
        case 5...: text = "Estás fresco: buen momento para competir o para una sesión exigente."
        case -10..<5: text = "En equilibrio: la carga y el descanso están compensados."
        case -30 ..< -10: text = "Cargando: estás construyendo forma. Cuida el sueño y los días suaves."
        default: text = "Mucha fatiga acumulada: baja el volumen unos días para asimilarlo."
        }
        if week > 6 { text += " Tu forma sube muy deprisa: vigila el riesgo de lesión." }
        return text
    }

    var body: some View {
        let points = runs.history.fitness(days: 90, today: runs.today)
        Card {
            SectionHeader(title: "Forma y fatiga", trailing: "carga de tus carreras")
            if let last = points.last {
                HStack {
                    stat("Forma", last.fitness, Palette.strain, signed: false)
                    stat("Fatiga", last.fatigue, Palette.stress, signed: false)
                    stat("Frescura", last.form, last.form >= -10 ? Palette.recoveryHigh : Palette.recoveryMedium, signed: true)
                }
                Text(Self.advice(points)).font(.subheadline).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                FitnessChart(points: points)
            }
        }
    }

    private func stat(_ name: String, _ value: Double, _ color: Color, signed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(signed ? Format.signed(value) : "\(Int(value.rounded()))").font(.metric(24, weight: .semibold)).foregroundStyle(color)
                .monospacedDigit()
            Text(name).font(.caption).foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Riesgo de lesión

extension LoadRiskLevel {
    var color: Color {
        switch self {
        case .low: return Palette.sleep
        case .optimal: return Palette.recoveryHigh
        case .caution: return Palette.recoveryMedium
        case .high: return Palette.recoveryLow
        }
    }
}

struct RunRiskCard: View {
    let risk: InjuryRisk
    let runs: RunsModel

    var body: some View {
        Card {
            SectionHeader(title: "Riesgo de lesión", trailing: "carga de todo el día")
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(risk.ratio.map { Format.decimal($0, digits: 2) } ?? "–").font(.metric(34, weight: .bold)).monospacedDigit()
                    .foregroundStyle(risk.level?.color ?? Palette.textPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(risk.level?.label ?? "Calculando").font(.subheadline.weight(.semibold)).foregroundStyle(risk.level?.color ?? Palette.textSecondary)
                    Text("carga de 7 días ÷ carga de 28 días").font(.caption).foregroundStyle(Palette.textSecondary)
                }
            }
            let points = risk.points.filter { $0.ratio != nil }
            if points.count >= 7, let first = points.first?.date.startDate(utcOffsetSeconds: 0),
               let last = points.last?.date.startDate(utcOffsetSeconds: 0) {
                // Una fecha cada dos semanas, sin pegarse al borde derecho (ahí no cabe entera).
                let days = last.timeIntervalSince(first) / 86_400
                let ticks = stride(from: 7.0, to: max(8, days - 5), by: 14).map { first.addingTimeInterval($0 * 86_400) }
                Chart {
                    RectangleMark(xStart: .value("Inicio", first), xEnd: .value("Fin", last),
                                  yStart: .value("Desde", 0.8), yEnd: .value("Hasta", 1.3))
                        .foregroundStyle(Palette.recoveryHigh.opacity(0.12))
                    RectangleMark(xStart: .value("Inicio", first), xEnd: .value("Fin", last),
                                  yStart: .value("Desde", 1.3), yEnd: .value("Hasta", 1.5))
                        .foregroundStyle(Palette.recoveryMedium.opacity(0.12))
                    ForEach(points) { p in
                        LineMark(x: .value("Día", p.date.startDate(utcOffsetSeconds: 0)), y: .value("ACWR", min(p.ratio ?? 0, 2)))
                            .foregroundStyle(Palette.textPrimary)
                            .interpolationMethod(.monotone)
                    }
                }
                .chartYScale(domain: 0.4...2)
                .chartYAxis {
                    AxisMarks(values: [0.8, 1.3, 1.5]) { v in
                        AxisGridLine().foregroundStyle(Palette.separator)
                        AxisValueLabel { if let x = v.as(Double.self) { Text(Format.decimal(x, digits: 1)) } }
                    }
                }
                .chartXAxis { AxisMarks(values: ticks) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                .frame(height: 140)
            }
            if !risk.spikes.isEmpty {
                Text("Picos de distancia (4 semanas)").font(.subheadline.weight(.semibold)).padding(.top, 2)
                ForEach(risk.spikes) { spike in
                    NavigationLink(value: DetailRoute.run(spike.runID)) {
                        HStack {
                            Text(spike.level.label).foregroundStyle(spike.level == .moderate ? Palette.recoveryMedium : Palette.recoveryLow)
                            Spacer()
                            Text(RunFormat.shortDate(spike.date, today: runs.today)).font(.caption).foregroundStyle(Palette.textSecondary)
                            Text(RunFormat.distance(spike.distanceM)).monospacedDigit()
                            if let pct = spike.increasePct {
                                Text("+\(Int(pct.rounded())) %").monospacedDigit().foregroundStyle(Palette.textSecondary)
                            }
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Palette.textSecondary)
                        }
                        .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let safe = risk.safeLongRunM {
                Label {
                    Text("Próxima tirada larga: hasta \(Text(RunFormat.distance(safe)).fontWeight(.semibold)) (un 10 % más que la más larga del mes)")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "arrow.up.right").foregroundStyle(Palette.textSecondary)
                }
                .font(.subheadline)
            }
            Text(risk.advice).font(.caption).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Rendimiento

struct RunPerformanceCard: View {
    let runs: RunsModel

    private func basis(_ v: VDOTEstimate) -> String {
        if v.fromEstimates { return "según el VO₂ máx. estimado de tus últimas carreras" }
        guard let d = v.distance, let s = v.seconds, let date = v.date else { return "" }
        let effort = "tus \(d.label) en \(RunFormat.time(s)) (\(RunFormat.shortDate(date, today: runs.today)))"
        // Las marcas de entrenamiento se quedan cortas: si el VO₂ estimado apunta más alto, el VDOT es la media de ambos.
        return v.blended ? "por \(effort) y por el VO₂ máx. estimado de tus últimas carreras" : "por \(effort)"
    }

    private func paceRange(_ p: TrainingPace) -> String {
        p.slowSpeed == p.fastSpeed ? RunFormat.paceFromSpeed(p.fastSpeed) + " /km"
            : "\(RunFormat.paceFromSpeed(p.fastSpeed))–\(RunFormat.paceFromSpeed(p.slowSpeed)) /km"
    }

    var body: some View {
        Card {
            SectionHeader(title: "Rendimiento", trailing: "VDOT de Daniels")
            if let v = runs.history.vdot(today: runs.today) {
                BigNumber(value: Format.decimal(v.value), caption: basis(v))
                Text("Predicciones").font(.subheadline.weight(.semibold)).padding(.top, 4)
                ForEach(runs.history.predictions(vdot: v.value), id: \.distance) { p in
                    RunRow(name: p.distance.label, value: RunFormat.time(p.seconds),
                           detail: RunFormat.pace(p.seconds / p.distance.rawValue * 1000) + " /km")
                }
                Divider()
                Text("Ritmos de entrenamiento").font(.subheadline.weight(.semibold))
                ForEach(RunPhysiology.trainingPaces(vdot: v.value), id: \.zone) { p in
                    VStack(alignment: .leading, spacing: 1) {
                        RunRow(name: p.zone.label, value: paceRange(p))
                        Text(p.zone.purpose).font(.caption).foregroundStyle(Palette.textSecondary)
                    }
                }
            } else {
                Text("Corre 3 km o más a tope, o varias carreras con FC, y calcularemos tu VDOT, tus predicciones y tus ritmos.")
                    .font(.subheadline).foregroundStyle(Palette.textSecondary)
            }
        }
    }
}

struct RunVO2Card: View {
    let runs: RunsModel
    @State private var range: RunRange = .halfYear

    private struct Plot {
        var values: [DatedValue] = []
        /// Series con un valor por carrera: se dibuja su media móvil.
        var smoothed: Set<String> = ["Estimado"]
    }

    private var data: Plot {
        let from = runs.today.adding(days: -range.rawValue)
        let recent = runs.summaries.filter { $0.date >= from }
        var d = Plot()
        let measured = runs.vo2.filter { $0.date >= from }.map { v in
            DatedValue(date: v.date.startDate(utcOffsetSeconds: 0), value: v.value, series: v.source == .appleHealth ? "Apple Watch" : "Fitbit Air")
        }
        d.values = measured + recent.compactMap { s in s.vo2maxEstimate.map { DatedValue(date: s.start, value: $0, series: "Estimado") } }
        // El que da la Fitbit en cada carrera, solo si no llega el diario (es casi el mismo dato y la línea iría en zigzag).
        if !measured.contains(where: { $0.series == "Fitbit Air" }) {
            d.values += recent.compactMap { s in s.fitbitVO2max.map { DatedValue(date: s.start, value: $0, series: "Fitbit Air") } }
            d.smoothed.insert("Fitbit Air")
        }
        d.values.sort { $0.date < $1.date }
        return d
    }

    /// El último valor de cada fuente (en las de cada carrera, la media de las 5 últimas).
    private func latest(_ d: Plot) -> String {
        ["Apple Watch", "Fitbit Air", "Estimado"].compactMap { series -> String? in
            let list = d.values.filter { $0.series == series }.map(\.value)
            guard let last = list.last else { return nil }
            let v = d.smoothed.contains(series) ? (Stats.mean(Array(list.suffix(5))) ?? last) : last
            return "\(series) \(Format.decimal(v))"
        }.joined(separator: " · ")
    }

    var body: some View {
        let d = data
        if !d.values.isEmpty {
            Card {
                SectionHeader(title: "VO₂ máx.", trailing: "ml/kg/min")
                Picker("Periodo", selection: $range) {
                    ForEach(RunRange.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(latest(d)).font(.subheadline.weight(.semibold)).monospacedDigit()
                DatedValueChart(values: d.values, formatter: { Format.decimal($0) },
                                colors: ["Apple Watch": Palette.recoveryLow, "Fitbit Air": Palette.fitbit, "Estimado": Palette.strain],
                                smoothed: d.smoothed)
                Text("«Estimado» sale del ritmo y la FC de cada carrera; los puntos son cada carrera y la línea, la media de cinco. Compáralo con lo que dicen el reloj y la pulsera.")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
            }
        }
    }
}

// MARK: - Récords

struct RunRecordsCard: View {
    let runs: RunsModel
    static let shown: [RaceDistance] = [.k1, .mile, .k3, .k5, .k10, .half, .marathon]

    private func row(_ name: String, value: String, date: LocalDate, runID: String, primary: Bool = true) -> some View {
        NavigationLink(value: DetailRoute.run(runID)) {
            HStack {
                Text(name).foregroundStyle(primary ? Palette.textPrimary : Palette.textSecondary)
                Spacer()
                Text(RunFormat.shortDate(date, today: runs.today)).font(.caption).foregroundStyle(Palette.textSecondary)
                Text(value).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.textPrimary)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Palette.textSecondary)
            }
            .font(.subheadline)
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        let records = runs.history.records().filter { Self.shown.contains($0.distance) }
        if !records.isEmpty {
            Card {
                SectionHeader(title: "Récords", trailing: "tus mejores marcas")
                ForEach(records) { r in row(r.distance.label, value: RunFormat.time(r.seconds), date: r.date, runID: r.runID) }
                if let longest = runs.history.longestRun {
                    row("Tirada más larga", value: RunFormat.distance(longest.distanceM), date: longest.date, runID: longest.id, primary: false)
                }
                if let climb = runs.history.biggestClimb, let gain = climb.elevationGainM {
                    row("Más desnivel", value: "\(Int(gain.rounded())) m", date: climb.date, runID: climb.id, primary: false)
                }
            }
        }
    }
}

// MARK: - Tendencias

struct RunTrendsCard: View {
    let runs: RunsModel
    @Binding var metric: RunTrendMetric
    @State private var range: RunRange = .halfYear

    private var values: [DatedValue] {
        runs.history.trend(metric, days: range.rawValue, today: runs.today).map { DatedValue(date: $0.date, value: $0.value, series: "Valor") }
    }

    private func format(_ v: Double) -> String {
        switch metric {
        case .pace: return Format.pace(secondsPerKm: v)
        case .efficiency, .stride: return Format.decimal(v, digits: 2)
        case .vo2max, .verticalOsc: return Format.decimal(v)
        case .decoupling: return Format.decimal(v) + " %"
        default: return "\(Int(v.rounded()))"
        }
    }

    private func change(_ list: [DatedValue]) -> String? {
        guard list.count >= 4 else { return nil }
        let third = max(1, list.count / 3)
        guard let a = Stats.mean(list.prefix(third).map(\.value)), let b = Stats.mean(list.suffix(third).map(\.value)), a != 0 else { return nil }
        let better = metric.higherIsBetter ? b > a : b < a
        let pct = abs(b - a) / abs(a) * 100
        if pct < 1 { return "Estable en este periodo (\(format(b)))." }
        return "\(better ? "Mejora" : "Empeora"): de \(format(a)) a \(format(b)) (\(Format.decimal(pct)) %)."
    }

    var body: some View {
        let list = values
        Card {
            HStack {
                Text("Tendencias").font(.headline)
                Spacer()
                Picker("Métrica", selection: $metric) {
                    ForEach(RunTrendMetric.allCases) { m in Text(m.label).tag(m) }
                }
                .pickerStyle(.menu)
            }
            Picker("Periodo", selection: $range) {
                ForEach(RunRange.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            if list.count >= 2 {
                DatedValueChart(values: list, reversed: !metric.higherIsBetter, formatter: format, smoothed: ["Valor"])
                if let text = change(list) { Text(text).font(.subheadline).foregroundStyle(Palette.textSecondary) }
                if metric == .efficiency {
                    Text("Eficiencia: metros por minuto (ajustados por pendiente) por cada latido. Si sube, corres más rápido con el mismo pulso.")
                        .font(.caption).foregroundStyle(Palette.textSecondary)
                }
            } else {
                Text("Hacen falta al menos dos carreras con este dato.").font(.subheadline).foregroundStyle(Palette.textSecondary)
            }
        }
    }
}

// MARK: - Zonas

struct RunZonesCard: View {
    let runs: RunsModel
    let zones: HRZones?

    static let paceNames = ["Recuperación", "Suave (E)", "Maratón (M)", "Umbral (T)", "Intervalos (I)", "Repeticiones (R)"]

    var body: some View {
        Card {
            SectionHeader(title: "Tus zonas", trailing: "se ajustan solas")
            if let z = zones {
                Text("Frecuencia cardiaca").font(.subheadline.weight(.semibold))
                ForEach(1...5, id: \.self) { i in
                    let lower = Int(z.lowerBounds[i - 1].rounded())
                    let upper = i < 5 ? Int(z.lowerBounds[i].rounded()) - 1 : Int(z.hrMax.rounded())
                    HStack {
                        Circle().fill(Palette.zones[i]).frame(width: 8, height: 8)
                        RunRow(name: "Zona \(i)", value: "\(lower)–\(upper) lpm")
                    }
                }
            }
            if let vdot = runs.context.vdot {
                let bounds = RunPhysiology.paceZoneBounds(vdot: vdot)
                Divider()
                Text("Ritmo (VDOT \(Format.decimal(vdot)))").font(.subheadline.weight(.semibold))
                ForEach(0..<6, id: \.self) { i in
                    let slow = i == 0 ? nil : bounds[i - 1]
                    let fast = i < 5 ? bounds[i] : nil
                    RunRow(name: Self.paceNames[i],
                           value: fast == nil ? "< \(RunFormat.paceFromSpeed(slow))" : (slow == nil ? "> \(RunFormat.paceFromSpeed(fast))"
                               : "\(RunFormat.paceFromSpeed(slow))–\(RunFormat.paceFromSpeed(fast))"))
                }
            }
            if let cp = runs.context.criticalPower {
                Divider()
                Text("Potencia (crítica ≈ \(Int(cp.rounded())) W)").font(.subheadline.weight(.semibold))
                let names = ["Suave", "Moderada", "Umbral", "Intervalos", "Máxima"]
                let factors = [0.0, 0.80, 0.90, 1.00, 1.15]
                ForEach(0..<5, id: \.self) { i in
                    RunRow(name: names[i], value: i < 4 ? "\(Int((factors[i] * cp).rounded()))–\(Int((factors[i + 1] * cp).rounded())) W"
                                                    : "> \(Int((factors[4] * cp).rounded())) W")
                }
            }
        }
    }
}

// MARK: - Zapatillas

struct RunShoesCard: View {
    let runs: RunsModel

    var body: some View {
        let km = runs.history.shoeKilometers(shoes: runs.shoes, assignments: runs.assignments)
        Card {
            HStack {
                Text("Zapatillas").font(.headline)
                Spacer()
                NavigationLink(value: DetailRoute.shoes) { Text("Gestionar").font(.subheadline) }
            }
            if runs.shoes.filter({ !$0.retired }).isEmpty {
                Text("Añade tus zapatillas para llevar la cuenta de sus kilómetros y saber cuándo cambiarlas.")
                    .font(.subheadline).foregroundStyle(Palette.textSecondary)
            }
            ForEach(runs.shoes.filter { !$0.retired }) { shoe in
                let used = km[shoe.id] ?? shoe.startKm
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(shoe.name).font(.subheadline.weight(.semibold))
                        if shoe.isDefault { Text("Predeterminadas").font(.caption2).foregroundStyle(Palette.textSecondary) }
                        Spacer()
                        Text("\(Int(used.rounded())) / \(Int(shoe.limitKm)) km").font(.subheadline).monospacedDigit()
                    }
                    ProgressView(value: min(used, shoe.limitKm), total: max(1, shoe.limitKm))
                        .tint(used >= shoe.limitKm ? Palette.recoveryLow : (used >= 0.8 * shoe.limitKm ? Palette.recoveryMedium : Palette.recoveryHigh))
                    if used >= shoe.limitKm {
                        Text("Han llegado a su límite: plantéate cambiarlas.").font(.caption).foregroundStyle(Palette.recoveryLow)
                    }
                }
            }
        }
    }
}

// MARK: - Todas las carreras

struct RunListSection: View {
    let runs: RunsModel
    /// En la pestaña, los últimos meses; el resto, en «Todas tus carreras».
    static let shownMonths = 3

    struct Month: Identifiable {
        var id: String
        var title: String
        var items: [RunSummary]
    }

    static func months(_ summaries: [RunSummary]) -> [Month] {
        var out: [Month] = []
        for s in summaries.reversed() {
            let key = "\(s.date.year)-\(s.date.month)"
            if out.last?.id == key { out[out.count - 1].items.append(s) } else {
                out.append(Month(id: key, title: "\(Format.monthName(s.date.month).capitalized) \(String(s.date.year))", items: [s]))
            }
        }
        return out
    }

    var body: some View {
        let months = Self.months(runs.summaries)
        ForEach(months.prefix(Self.shownMonths)) { month in
            RunMonthSection(month: month, recordIDs: runs.recordIDs)
        }
        if months.count > Self.shownMonths {
            NavigationLink {
                AllRunsView()
            } label: {
                HStack {
                    Label("Todas tus carreras", systemImage: "list.bullet")
                    Spacer()
                    Text("\(runs.summaries.count)").monospacedDigit().foregroundStyle(Palette.textSecondary)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.textSecondary)
                }
                .font(.subheadline.weight(.semibold))
                .padding(14)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

struct RunMonthSection: View {
    let month: RunListSection.Month
    let recordIDs: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(month.title).font(.headline)
                Spacer()
                Text("\(Format.decimal(month.items.reduce(0) { $0 + $1.distanceM } / 1000)) km · \(RunFormat.count(month.items.count, "carrera", "carreras"))")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
            }
            ForEach(month.items) { s in
                NavigationLink(value: DetailRoute.run(s.id)) {
                    RunListRow(summary: s, isRecord: recordIDs.contains(s.id))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Todas tus carreras, por meses y con filtro por año (con años de historial, la lista se carga al desplazarte).
struct AllRunsView: View {
    @Environment(AppModel.self) private var model
    @State private var year: Int?

    var body: some View {
        let runs = model.runs
        let years = Array(Set(runs.summaries.map(\.date.year))).sorted(by: >)
        let list = year.map { y in runs.summaries.filter { $0.date.year == y } } ?? runs.summaries
        let totals = RunHistory(summaries: list).totals(from: list.first?.date ?? runs.today, to: list.last?.date ?? runs.today)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16, pinnedViews: []) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("Todas", selected: year == nil) { year = nil }
                        ForEach(years, id: \.self) { y in chip(String(y), selected: year == y) { year = y } }
                    }
                }
                Text("\(Format.thousands(totals.distanceM / 1000)) km · \(RunFormat.count(totals.runs, "carrera", "carreras")) · \(Format.duration(minutes: totals.movingS / 60))")
                    .font(.subheadline).foregroundStyle(Palette.textSecondary)
                ForEach(RunListSection.months(list)) { month in
                    RunMonthSection(month: month, recordIDs: runs.recordIDs)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Todas tus carreras")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundStyle(selected ? Palette.bg : Palette.textPrimary)
                .background(selected ? Palette.strain : Palette.surface, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct RunListRow: View {
    let summary: RunSummary
    let isRecord: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: summary.kind.symbolName).font(.headline).foregroundStyle(Palette.strain)
                .frame(width: 40, height: 40).background(Palette.strain.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(summary.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary).lineLimit(1)
                    if isRecord { PRBadge() }
                }
                Text("\(RunFormat.date(summary)) · \(summary.intervalLabel ?? "\(RunFormat.pace(summary.avgPace)) /km")\(summary.avgHR.map { " · \(Int($0.rounded())) lpm" } ?? "")")
                    .font(.caption).foregroundStyle(Palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                Text(RunFormat.distance(summary.distanceM)).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.textPrimary)
                SourceBadges(sources: summary.sources)
            }
        }
        .padding(12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
