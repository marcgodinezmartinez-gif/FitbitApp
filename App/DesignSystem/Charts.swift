import SwiftUI
import Charts
import MetricsKit
import Insights

/// Punto de una serie diaria.
struct DayPoint: Identifiable, Hashable {
    var date: Date
    var value: Double
    var id: Date { date }
}

/// Tendencia con área en degradado, media móvil de 7 días y banda gris de «tu rango habitual».
struct TrendChart: View {
    var points: [DayPoint]
    var color: Color
    var band: ClosedRange<Double>? = nil
    var showAverage = true
    var yDomain: ClosedRange<Double>? = nil
    var unit: String = ""

    @State private var selected: Date?

    var average: [DayPoint] {
        guard showAverage, points.count >= 7 else { return [] }
        return points.indices.compactMap { i in
            guard i >= 6 else { return nil }
            let window = points[(i - 6)...i].map(\.value)
            return DayPoint(date: points[i].date, value: window.reduce(0, +) / Double(window.count))
        }
    }

    var body: some View {
        Chart {
            if let band, let first = points.first?.date, let last = points.last?.date {
                RectangleMark(xStart: .value("Inicio", first), xEnd: .value("Fin", last),
                              yStart: .value("Mínimo habitual", band.lowerBound), yEnd: .value("Máximo habitual", band.upperBound))
                    .foregroundStyle(Palette.textSecondary.opacity(0.12))
            }
            ForEach(points) { p in
                AreaMark(x: .value("Día", p.date), y: .value("Valor", p.value))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Día", p.date), y: .value("Valor", p.value), series: .value("Serie", "valor"))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.catmullRom)
            }
            ForEach(average) { p in
                LineMark(x: .value("Día", p.date), y: .value("Media 7 días", p.value), series: .value("Serie", "media"))
                    .foregroundStyle(Palette.textPrimary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            if let selected, let p = points.min(by: { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) }) {
                RuleMark(x: .value("Día", p.date))
                    .foregroundStyle(Palette.textSecondary.opacity(0.5))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Text("\(Format.decimal(p.value)) \(unit)")
                            .font(.caption.weight(.semibold)).monospacedDigit()
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Palette.surfaceElevated, in: Capsule())
                    }
                PointMark(x: .value("Día", p.date), y: .value("Valor", p.value)).foregroundStyle(color)
            }
        }
        .chartYScale(domain: yDomain ?? autoDomain)
        .chartXSelection(value: $selected)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Palette.separator)
                AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: false)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Palette.separator)
                AxisValueLabel()
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    var autoDomain: ClosedRange<Double> {
        let values = points.map(\.value) + (band.map { [$0.lowerBound, $0.upperBound] } ?? [])
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        let pad = max((hi - lo) * 0.15, 0.5)
        return (lo - pad)...(hi + pad)
    }
}

/// Hipnograma de una noche.
struct Hypnogram: View {
    var stages: [SleepStageSegment]

    static let order: [SleepStageKind] = [.wake, .rem, .light, .deep]

    func name(_ k: SleepStageKind) -> String {
        switch k {
        case .wake: return "Despierto"
        case .rem: return "REM"
        case .light, .asleep: return "Ligero"
        case .deep: return "Profundo"
        }
    }

    func color(_ k: SleepStageKind) -> Color {
        switch k {
        case .wake: return Palette.recoveryMedium
        case .rem: return Palette.sleep
        case .light, .asleep: return Palette.strain.opacity(0.8)
        case .deep: return Color(light: 0x3B1F8C, dark: 0x6D4AE8)
        }
    }

    var body: some View {
        Chart(Array(stages.enumerated()), id: \.offset) { _, s in
            RectangleMark(xStart: .value("Inicio", s.start), xEnd: .value("Fin", s.end), y: .value("Fase", name(s.stage)))
                .foregroundStyle(color(s.stage))
                .cornerRadius(3)
        }
        .chartYScale(domain: Self.order.map(name))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Palette.separator)
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .frame(height: 140)
        .accessibilityLabel("Hipnograma de la noche")
    }
}

/// Curva de FC con las zonas de fondo.
struct HeartRateChart: View {
    struct Sample: Identifiable, Hashable {
        var time: Date
        var bpm: Double
        var source: DataSourceKind
        var id: String { "\(source.rawValue)-\(time.timeIntervalSince1970)" }
    }

    var samples: [Sample]
    var zones: HRZones?
    var compareSources = false

    var body: some View {
        Chart {
            if let zones {
                ForEach(Array(zones.lowerBounds.enumerated()), id: \.offset) { i, lb in
                    RuleMark(y: .value("Zona \(i + 1)", lb))
                        .foregroundStyle(Palette.zones[min(i + 1, Palette.zones.count - 1)].opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
            }
            ForEach(samples) { s in
                LineMark(x: .value("Hora", s.time), y: .value("lpm", s.bpm), series: .value("Fuente", s.source.label))
                    .foregroundStyle(by: .value("Fuente", s.source.label))
                    .interpolationMethod(.monotone)
            }
        }
        .chartForegroundStyleScale(["Apple Watch": Palette.recoveryLow, "Fitbit Air": Palette.fitbit, "Manual": Palette.textSecondary])
        .chartLegend(compareSources ? .visible : .hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Palette.separator)
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .frame(height: 180)
    }
}

/// Barras de nivel de estrés (0–3) a lo largo del día.
struct StressBars: View {
    var windows: [StressWindow]

    var body: some View {
        Chart(windows.filter { $0.level != nil }, id: \.start) { w in
            BarMark(x: .value("Hora", Date(timeIntervalSince1970: TimeInterval(w.start))), y: .value("Estrés", w.level ?? 0), width: .fixed(2))
                .foregroundStyle(Palette.stress.opacity(0.35 + 0.2 * (w.level ?? 0)))
        }
        .chartYScale(domain: 0...3)
        .chartYAxis(.hidden)
        .chartXAxis(.hidden)
        .frame(height: 44)
        .accessibilityLabel("Estrés a lo largo del día")
    }
}
