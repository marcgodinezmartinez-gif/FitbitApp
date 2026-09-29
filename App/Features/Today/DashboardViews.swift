import SwiftUI
import Charts
import MetricsKit
import Insights

/// «Mi panel»: tarjetas de métricas elegibles y reordenables; cada una abre su tendencia (doc. 11 §4).
struct DashboardSection: View {
    @Environment(AppModel.self) private var model
    let date: LocalDate
    @State private var editing = false

    var body: some View {
        let metrics = DayMetric.dashboard(model.settings.dashboardMetrics)
        let cycles = model.output?.cycles ?? []
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Mi panel").font(.title3.weight(.bold))
                Spacer()
                Button("Editar") { editing = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.recoveryHigh)
            }
            if metrics.isEmpty {
                Text("Elige qué métricas quieres ver aquí.").font(.footnote).foregroundStyle(Palette.textSecondary)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(metrics) { m in
                    NavigationLink(value: DetailRoute.trend(m)) {
                        DashboardTile(summary: MetricSummary.build(m, cycles: cycles, until: date))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $editing) { DashboardEditor() }
    }
}

struct DashboardTile: View {
    let summary: MetricSummary

    var body: some View {
        let m = summary.metric
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: m.symbolName).font(.caption).foregroundStyle(m.color)
                Text(m.title).font(.caption.weight(.semibold)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(summary.latest.map { m.formatted($0) } ?? "—").font(.metric(22)).monospacedDigit()
                    .foregroundStyle(Palette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                if m != .sleep && !m.unit.isEmpty {
                    Text(m.unit).font(.caption).foregroundStyle(Palette.textSecondary)
                }
            }
            Sparkline(values: summary.last7, color: m.color)
                .frame(height: 28)
            Text(deltaText).font(.caption2).foregroundStyle(deltaColor).lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var deltaText: String {
        if summary.inProgress { return "hoy, en curso" }
        guard let d = summary.delta else { return "sin referencia aún" }
        let m = summary.metric
        let scaled = m == .sleep ? d * 60 : d * pow(10.0, Double(m.digits))
        if scaled.rounded() == 0 { return "igual que lo habitual" }
        let value = m == .sleep ? Format.signed(d * 60, digits: 0) + " min" : Format.signed(d, digits: m.digits) + (m.unit.isEmpty ? "" : " \(m.unit)")
        return "\(value) vs. lo habitual"
    }

    private var deltaColor: Color {
        if summary.inProgress { return Palette.textSecondary }
        switch summary.isImprovement {
        case true?: return Palette.recoveryHigh
        case false?: return Palette.recoveryMedium
        case nil: return Palette.textSecondary
        }
    }
}

/// Mini gráfica de los últimos 7 días.
struct Sparkline: View {
    let values: [Double?]
    let color: Color

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { item in
                if let v = item.element {
                    LineMark(x: .value("Día", item.offset), y: .value("Valor", v))
                        .foregroundStyle(color)
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: 0...6)
        .chartYScale(domain: .automatic(includesZero: false))
        .accessibilityHidden(true)
    }
}

/// Elegir y ordenar las tarjetas de «Mi panel».
struct DashboardEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selected: [DayMetric] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(selected) { m in
                        Label(m.title, systemImage: m.symbolName)
                    }
                    .onMove { selected.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { selected.remove(atOffsets: $0) }
                } header: {
                    Text("En tu panel")
                } footer: {
                    Text("Arrastra para ordenar. Cada tarjeta abre la tendencia de su métrica.")
                }
                Section("Añadir") {
                    ForEach(DayMetric.allCases.filter { !selected.contains($0) }) { m in
                        Button {
                            withAnimation { selected.append(m) }
                        } label: {
                            Label(m.title, systemImage: "plus.circle.fill")
                        }
                        .moveDisabled(true)
                        .deleteDisabled(true)
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Mi panel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        model.updateSettings { $0.dashboardMetrics = selected.map(\.rawValue) }
                        dismiss()
                    }
                }
            }
            .onAppear { selected = DayMetric.dashboard(model.settings.dashboardMetrics) }
        }
    }
}
