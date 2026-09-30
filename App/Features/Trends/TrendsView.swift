import SwiftUI
import Charts
import MetricsKit
import Insights

/// Tendencias: métrica y periodo, media móvil, rango habitual, calendario por recuperación e informe semanal (doc. 11 §5).
struct TrendsView: View {
    @Environment(AppModel.self) private var model
    @State private var metric: DayMetric = .recovery
    @State private var period: Int = 30
    /// «Todo»: el historial completo.
    static let allDays = 36_500

    var body: some View {
        ScrollViewReader { proxy in
            content
                .task(id: model.dataVersion) {
                    guard AppModel.screenshotScreen == "report", model.output != nil else { return }
                    try? await Task.sleep(for: .milliseconds(600))
                    proxy.scrollTo("weekly", anchor: .top)
                }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let output = model.output, let last = output.current?.date {
                    Picker("Periodo", selection: $period) {
                        Text("7 d").tag(7)
                        Text("30 d").tag(30)
                        Text("90 d").tag(90)
                        Text("1 año").tag(365)
                        Text("Todo").tag(Self.allDays)
                    }
                    .pickerStyle(.segmented)
                    .task(id: "\(period)-\(model.dataVersion)") {
                        if period > 180 { await model.loadHistoryCycles() }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(DayMetric.allCases) { m in
                                Button {
                                    withAnimation(.snappy) { metric = m }
                                    Haptics.selection()
                                } label: {
                                    Text(m.title).font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .foregroundStyle(metric == m ? Palette.bg : Palette.textPrimary)
                                        .background(metric == m ? m.color : Palette.surface, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    let points = series(model, until: last, days: period) { metric.value($0) }
                    Card {
                        HStack(alignment: .firstTextBaseline) {
                            SectionHeader(title: metric.title)
                            Spacer()
                            if let avg = average(points) {
                                Text("media \(Format.decimal(avg, digits: metric.digits)) \(metric.unit)").font(.footnote)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                        }
                        if points.count >= 2 {
                            TrendChart(points: points, color: metric.color, band: usualBand(points), showAverage: period > 7,
                                       yDomain: metric.domain, unit: metric.unit)
                                .frame(height: 220)
                        } else {
                            Text("Todavía no hay datos suficientes para este periodo.").font(.footnote).foregroundStyle(Palette.textSecondary)
                        }
                    }
                    RecoveryCalendar(cycles: output.cycles, month: last)
                    WeeklyReportCard(output: output, today: last)
                        .id("weekly")
                    HabitImpactCard(impacts: output.habitImpacts)
                } else {
                    ContentUnavailableView("Sin datos todavía", systemImage: "chart.xyaxis.line",
                                           description: Text("Las tendencias aparecen cuando haya varias noches sincronizadas."))
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Tendencias")
        .detailDestinations()
    }

    private func average(_ points: [DayPoint]) -> Double? {
        points.isEmpty ? nil : points.map(\.value).reduce(0, +) / Double(points.count)
    }

    private func usualBand(_ points: [DayPoint]) -> ClosedRange<Double>? {
        let values = points.map(\.value)
        guard values.count >= 14, let lo = Stats.percentile(values, 10), let hi = Stats.percentile(values, 90), hi > lo else { return nil }
        return lo...hi
    }
}

extension DayMetric {
    var color: Color {
        switch self {
        case .recovery, .hrv: return Palette.recoveryHigh
        case .rhr: return Palette.recoveryLow
        case .sleep, .sleepPerformance, .spo2: return Palette.sleep
        case .strain, .respiratory: return Palette.strain
        case .zoneMinutes: return Palette.zones[3]
        case .steps: return Palette.fitbit
        case .stress, .skinTemp: return Palette.stress
        }
    }
}

/// Tendencia de una métrica (se abre desde «Mi panel»).
struct MetricTrendView: View {
    let metric: DayMetric
    @Environment(AppModel.self) private var model
    @State private var period = 30

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let output = model.output, let last = output.current?.date {
                    Picker("Periodo", selection: $period) {
                        Text("7 d").tag(7)
                        Text("30 d").tag(30)
                        Text("90 d").tag(90)
                        Text("1 año").tag(365)
                        Text("Todo").tag(TrendsView.allDays)
                    }
                    .pickerStyle(.segmented)
                    .task(id: "\(period)-\(model.dataVersion)") {
                        if period > 180 { await model.loadHistoryCycles() }
                    }
                    let summary = MetricSummary.build(metric, cycles: output.cycles, until: last)
                    Card {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(summary.latest.map { metric.formatted($0) } ?? "—").font(.metric(40)).monospacedDigit()
                            if metric != .sleep { Text(metric.unit).font(.title3.weight(.semibold)).foregroundStyle(Palette.textSecondary) }
                            Spacer()
                        }
                        if let usual = summary.usual {
                            Text("Lo habitual (30 días): \(metric.formatted(usual)) \(metric == .sleep ? "" : metric.unit)")
                                .font(.subheadline).foregroundStyle(Palette.textSecondary)
                        }
                        let points = series(model, until: last, days: period) { metric.value($0) }
                        if points.count >= 2 {
                            TrendChart(points: points, color: metric.color, band: usualBand(points), showAverage: period > 7,
                                       yDomain: metric.domain, unit: metric.unit)
                                .frame(height: 240)
                        } else {
                            Text("Todavía no hay datos suficientes para este periodo.").font(.footnote).foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(metric.title)
    }

    private func usualBand(_ points: [DayPoint]) -> ClosedRange<Double>? {
        let values = points.map(\.value)
        guard values.count >= 14, let lo = Stats.percentile(values, 10), let hi = Stats.percentile(values, 90), hi > lo else { return nil }
        return lo...hi
    }
}

/// Calendario del mes coloreado por la zona de recuperación (color + forma).
struct RecoveryCalendar: View {
    let cycles: [CycleMetrics]
    let month: LocalDate

    var body: some View {
        let first = LocalDate(year: month.year, month: month.month, day: 1)
        let lead = first.isoWeekday - 1
        let daysInMonth = (0..<31).filter { first.adding(days: $0).month == month.month }.count
        let byDate = Dictionary(cycles.map { ($0.date, $0) }, uniquingKeysWith: { _, b in b })
        Card {
            SectionHeader(title: "\(Format.monthName(month.month).capitalized) \(month.year)")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(["L", "M", "X", "J", "V", "S", "D"], id: \.self) { d in
                    Text(d).font(.caption2.weight(.semibold)).foregroundStyle(Palette.textSecondary)
                }
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 34) }
                ForEach(1...max(daysInMonth, 1), id: \.self) { day in
                    let date = first.adding(days: day - 1)
                    let zone = byDate[date]?.recovery.zone
                    NavigationLink(value: DetailRoute.recovery(date)) {
                        VStack(spacing: 2) {
                            Text("\(day)").font(.caption2).monospacedDigit()
                                .foregroundStyle(zone == nil ? Palette.textSecondary : Palette.textPrimary)
                            Image(systemName: zone?.symbol ?? "circle")
                                .font(.system(size: 9))
                                .foregroundStyle(zone == nil ? Palette.separator : Palette.recovery(zone))
                        }
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background((zone == nil ? Color.clear : Palette.recovery(zone).opacity(0.12)),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(zone == nil)
                }
            }
        }
    }
}

/// Informe semanal determinista (RF-INF): medias, zonas, carreras y recomendaciones.
struct WeeklyReportCard: View {
    @Environment(AppModel.self) private var model
    let output: MetricsOutput
    let today: LocalDate

    var body: some View {
        let weekStart = today.adding(days: -(today.isoWeekday - 1) - 7)
        let report = WeeklyReportBuilder.build(output: output, weekStart: weekStart)
        Card {
            SectionHeader(title: "Semana pasada", trailing: "\(report.periodStart) – \(report.periodEnd)")
            HStack {
                stat("Recuperación", report.avgRecovery.map { "\(Int($0.rounded()))%" }, previous: report.previousAvgRecovery.map { "\(Int($0.rounded()))%" })
                stat("Carga media", report.avgStrain.map { Format.decimal($0) }, previous: report.previousAvgStrain.map { Format.decimal($0) })
                stat("Sueño", report.avgSleepMin.map { Format.duration(minutes: $0) }, previous: nil)
            }
            if report.runs > 0 {
                Label("\(report.runs) carreras · \(Format.decimal(report.runDistanceKm)) km", systemImage: "figure.run")
                    .font(.subheadline)
            }
            ForEach(report.best, id: \.self) { b in
                Label(b, systemImage: "checkmark.seal").font(.footnote).foregroundStyle(Palette.recoveryHigh)
            }
            ForEach(report.recommendations, id: \.self) { r in
                Label(r, systemImage: "arrow.forward.circle").font(.footnote).foregroundStyle(Palette.textSecondary)
            }
            if let plan = model.planProgress(weekStart: weekStart) {
                Divider().overlay(Palette.separator)
                Label("Plan semanal: \(plan.percent) % cumplido", systemImage: "checklist")
                    .font(.subheadline.weight(.semibold))
            }
        }
        AIWeeklyReportCard(weekStart: weekStart)
    }

    private func stat(_ name: String, _ value: String?, previous: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value ?? "—").font(.metric(20, weight: .semibold)).monospacedDigit()
            Text(name).font(.caption).foregroundStyle(Palette.textSecondary)
            if let previous { Text("antes \(previous)").font(.caption2).foregroundStyle(Palette.textSecondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Impacto de cada hábito del diario sobre la recuperación (± puntos, IC 95 %, días).
struct HabitImpactCard: View {
    let impacts: [HabitImpact]

    var body: some View {
        let labels = JournalCatalog.labels
        let shown = impacts.filter { $0.status != .needMoreData }
        Card {
            SectionHeader(title: "Qué afecta a tu recuperación")
            if shown.isEmpty {
                Text("Responde el diario unos días (al menos 5 con y 5 sin cada hábito) para ver su efecto.")
                    .font(.footnote).foregroundStyle(Palette.textSecondary)
            }
            ForEach(shown, id: \.questionKey) { h in
                HStack {
                    Text(labels[h.questionKey] ?? h.questionKey).font(.subheadline)
                    Spacer()
                    if h.status == .effect, let e = h.effect {
                        Text("\(Format.signed(e, digits: 1)) puntos").font(.subheadline.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(e >= 0 ? Palette.recoveryHigh : Palette.recoveryLow)
                    } else {
                        Text("sin efecto claro").font(.footnote).foregroundStyle(Palette.textSecondary)
                    }
                }
            }
        }
    }
}
