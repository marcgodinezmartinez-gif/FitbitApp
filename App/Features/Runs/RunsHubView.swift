import SwiftUI
import Charts
import MetricsKit
import Insights
import Store
import RunKit

/// Pestaña «Correr» (doc. 18): volumen, forma, rendimiento, récords, tendencias, zonas, zapatillas y todas tus carreras.
struct RunsHubView: View {
    @Environment(AppModel.self) private var model
    @State private var monthly = false
    @State private var trendMetric: RunTrendMetric = .efficiency
    @State private var openRun: String?

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
                        RunWeekHeader(runs: runs)
                        RunVolumeCard(runs: runs, monthly: $monthly)
                        RunFitnessCard(runs: runs)
                        RunPerformanceCard(runs: runs).id("performance")
                        RunVO2Card(runs: runs)
                        RunRecordsCard(runs: runs).id("records")
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
            .task(id: model.dataVersion) {
                await runs.refresh(model: model)
                guard let screen = AppModel.screenshotScreen else { return }
                if screen == "run" || screen.hasPrefix("run-"), openRun == nil {
                    openRun = runs.summaries.last { $0.startLat != nil }?.id ?? runs.summaries.last?.id
                } else if screen.hasPrefix("runs-") {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    proxy.scrollTo(String(screen.dropFirst(5)), anchor: .top)
                }
            }
            .refreshable { await model.sync(.pull) }
        }
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
        }
    }
}

// MARK: - Volumen

struct RunVolumeCard: View {
    let runs: RunsModel
    @Binding var monthly: Bool

    private var periods: [RunPeriod] {
        monthly ? runs.history.months(count: 12, today: runs.today) : runs.history.weeks(count: 12, today: runs.today)
    }

    var body: some View {
        let list = periods
        let average = list.map(\.distanceM).reduce(0, +) / Double(max(1, list.count)) / 1000
        Card {
            SectionHeader(title: "Volumen", trailing: "media \(Format.decimal(average)) km")
            Picker("Periodo", selection: $monthly) {
                Text("Semanas").tag(false)
                Text("Meses").tag(true)
            }
            .pickerStyle(.segmented)
            VolumeChart(periods: list, monthly: monthly)
            if let last = list.last, last.runs > 0 {
                Text("\(monthly ? "Este mes" : "Esta semana"): tirada más larga de \(RunFormat.distance(last.longestM)) y \(Int(last.elevationM.rounded())) m de desnivel.")
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

// MARK: - Rendimiento

struct RunPerformanceCard: View {
    let runs: RunsModel

    private func basis(_ v: VDOTEstimate) -> String {
        if v.fromEstimates { return "según el VO₂ máx. estimado de tus últimas carreras" }
        guard let d = v.distance, let s = v.seconds, let date = v.date else { return "" }
        return "por tus \(d.label) en \(RunFormat.time(s)) (\(date.day)/\(date.month))"
    }

    private func paceRange(_ p: TrainingPace) -> String {
        p.slowSpeed == p.fastSpeed ? RunFormat.paceFromSpeed(p.fastSpeed) + " /km"
            : "\(RunFormat.paceFromSpeed(p.slowSpeed))–\(RunFormat.paceFromSpeed(p.fastSpeed)) /km"
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

    private var values: [DatedValue] {
        let from = runs.today.adding(days: -180)
        let measured = runs.vo2.filter { $0.date >= from }.map { v in
            DatedValue(date: v.date.startDate(utcOffsetSeconds: 0), value: v.value, series: v.source == .appleHealth ? "Apple Watch" : "Fitbit Air")
        }
        let estimated = runs.summaries.filter { $0.date >= from }.compactMap { s in
            s.vo2maxEstimate.map { DatedValue(date: s.start, value: $0, series: "Estimado") }
        }
        let fitbitRuns = runs.summaries.filter { $0.date >= from }.compactMap { s in
            s.fitbitVO2max.map { DatedValue(date: s.start, value: $0, series: "Fitbit Air") }
        }
        return (measured + estimated + fitbitRuns).sorted { $0.date < $1.date }
    }

    var body: some View {
        let list = values
        if !list.isEmpty {
            Card {
                SectionHeader(title: "VO₂ máx.", trailing: "ml/kg/min · 6 meses")
                DatedValueChart(values: list, formatter: { Format.decimal($0) },
                                colors: ["Apple Watch": Palette.recoveryLow, "Fitbit Air": Palette.fitbit, "Estimado": Palette.strain])
                Text("«Estimado» sale del ritmo y la FC de cada carrera: compáralo con lo que dicen el reloj y la pulsera.")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
            }
        }
    }
}

// MARK: - Récords

struct RunRecordsCard: View {
    let runs: RunsModel
    static let shown: [RaceDistance] = [.k1, .mile, .k5, .k10, .half, .marathon]

    var body: some View {
        let records = runs.history.records().filter { Self.shown.contains($0.distance) }
        if !records.isEmpty {
            Card {
                SectionHeader(title: "Récords", trailing: "tus mejores marcas")
                ForEach(records) { r in
                    NavigationLink(value: DetailRoute.run(r.runID)) {
                        HStack {
                            Text(r.distance.label).foregroundStyle(Palette.textPrimary)
                            Spacer()
                            Text("\(r.date.day)/\(r.date.month)/\(String(r.date.year % 100))").font(.caption).foregroundStyle(Palette.textSecondary)
                            Text(RunFormat.time(r.seconds)).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.textPrimary)
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Palette.textSecondary)
                        }
                        .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                }
                if let longest = runs.history.longestRun {
                    RunRow(name: "Tirada más larga", value: RunFormat.distance(longest.distanceM), detail: RunFormat.date(longest))
                }
                if let climb = runs.history.biggestClimb, let gain = climb.elevationGainM {
                    RunRow(name: "Más desnivel", value: "\(Int(gain.rounded())) m", detail: RunFormat.date(climb))
                }
            }
        }
    }
}

// MARK: - Tendencias

struct RunTrendsCard: View {
    let runs: RunsModel
    @Binding var metric: RunTrendMetric

    private var values: [DatedValue] {
        runs.history.trend(metric, days: 180, today: runs.today).map { DatedValue(date: $0.date, value: $0.value, series: "Valor") }
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
        if pct < 1 { return "Estable en los últimos meses (\(format(b)))." }
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
            if list.count >= 2 {
                DatedValueChart(values: list, reversed: !metric.higherIsBetter, formatter: format)
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

    struct Month: Identifiable {
        var id: String
        var title: String
        var items: [RunSummary]
    }

    private var months: [Month] {
        var out: [Month] = []
        for s in runs.summaries.reversed() {
            let key = "\(s.date.year)-\(s.date.month)"
            if out.last?.id == key { out[out.count - 1].items.append(s) } else {
                out.append(Month(id: key, title: "\(Format.monthName(s.date.month).capitalized) \(String(s.date.year))", items: [s]))
            }
        }
        return out
    }

    var body: some View {
        ForEach(months) { month in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(month.title).font(.headline)
                    Spacer()
                    Text("\(Format.decimal(month.items.reduce(0) { $0 + $1.distanceM } / 1000)) km · \(RunFormat.count(month.items.count, "carrera", "carreras"))")
                        .font(.caption).foregroundStyle(Palette.textSecondary)
                }
                ForEach(month.items) { s in
                    NavigationLink(value: DetailRoute.run(s.id)) {
                        RunListRow(summary: s, isRecord: !runs.history.personalRecords(in: s).isEmpty)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
                Text("\(RunFormat.date(summary)) · \(RunFormat.pace(summary.avgPace)) /km\(summary.avgHR.map { " · \(Int($0.rounded())) lpm" } ?? "")")
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
