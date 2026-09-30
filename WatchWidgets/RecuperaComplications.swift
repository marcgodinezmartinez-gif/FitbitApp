import WidgetKit
import SwiftUI
import FaceKit

// Complicaciones de Recupera para las esferas de Apple y la Smart Stack (doc. 19 §4): la recuperación, el resumen del
// día y un acceso directo a tus esferas. Leen lo último que mandó el iPhone (App Group del reloj).

@main
struct RecuperaComplications: WidgetBundle {
    var body: some Widget {
        RecoveryComplication()
        DayComplication()
        FacesLauncherComplication()
    }
}

struct FaceEntry: TimelineEntry {
    var date: Date
    var data: FaceData
    var isPlaceholder = false
}

struct FaceProvider: TimelineProvider {
    func placeholder(in context: Context) -> FaceEntry {
        FaceEntry(date: Date(), data: .demo(), isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (FaceEntry) -> Void) {
        let saved = FaceShared.load()?.data
        completion(FaceEntry(date: Date(), data: saved ?? .demo(), isPlaceholder: saved == nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FaceEntry>) -> Void) {
        let saved = FaceShared.load()?.data
        let entry = FaceEntry(date: Date(), data: saved ?? FaceData(), isPlaceholder: false)
        // La app las recarga al recibir datos del iPhone; aquí solo se refrescan de vez en cuando.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

enum ComplicationColors {
    static func recovery(_ zone: String?) -> Color {
        switch zone {
        case "high": return Color(red: 0.24, green: 0.86, blue: 0.52)
        case "medium": return Color(red: 1.0, green: 0.82, blue: 0.25)
        case "low": return Color(red: 1.0, green: 0.36, blue: 0.36)
        default: return .gray
        }
    }

    static let strain = Color(red: 0.30, green: 0.64, blue: 1.0)
    static let sleep = Color(red: 0.70, green: 0.55, blue: 1.0)
    static let background = Color(red: 0.08, green: 0.08, blue: 0.10)
}

// MARK: - Recuperación

struct RecoveryComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecoveryComplication", provider: FaceProvider()) { entry in
            RecoveryComplicationView(entry: entry)
                .containerBackground(ComplicationColors.background, for: .widget)
        }
        .configurationDisplayName("Recuperación")
        .description("Tu recuperación de hoy, de Recupera.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

struct RecoveryComplicationView: View {
    let entry: FaceEntry
    @Environment(\.widgetFamily) private var family

    private var fraction: Double { Double(entry.data.recovery ?? 0) / 100 }
    private var text: String { entry.data.recovery.map { "\($0)" } ?? FaceValues.missing }
    private var color: Color { ComplicationColors.recovery(entry.data.recoveryZone) }

    var body: some View {
        switch family {
        case .accessoryCorner:
            Text(entry.data.recovery.map { "\($0)%" } ?? FaceValues.missing)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .widgetCurvesContent()
                .widgetLabel {
                    Gauge(value: fraction) { Text("REC") }
                        .gaugeStyle(.accessoryLinearCapacity)
                        .tint(color)
                }
        case .accessoryInline:
            Text("REC \(entry.data.recovery.map { "\($0) %" } ?? FaceValues.missing)")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("Recuperación", systemImage: "arrow.clockwise.heart.fill").font(.caption2.weight(.semibold)).foregroundStyle(color)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(text).font(.system(size: 30, weight: .bold, design: .rounded))
                    if entry.data.recovery != nil { Text("%").font(.caption.weight(.semibold)) }
                }
                Gauge(value: fraction) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity).tint(color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            Gauge(value: fraction) {
                Image(systemName: "arrow.clockwise.heart.fill")
            } currentValueLabel: {
                Text(text).font(.system(.body, design: .rounded).weight(.semibold))
            }
            .gaugeStyle(.accessoryCircular)
            .tint(color)
        }
    }
}

// MARK: - Resumen del día

struct DayComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DayComplication", provider: FaceProvider()) { entry in
            DayComplicationView(entry: entry)
                .containerBackground(ComplicationColors.background, for: .widget)
        }
        .configurationDisplayName("Tu día")
        .description("Recuperación, carga, sueño y el entreno de hoy.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

struct DayComplicationView: View {
    let entry: FaceEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let d = entry.data
        let summary = FaceValues.value(.summary, d, now: entry.date)?.text ?? FaceValues.missing
        let workout = FaceValues.value(.workout, d, now: entry.date)
        switch family {
        case .accessoryInline:
            Text(summary)
        default:
            VStack(alignment: .leading, spacing: 3) {
                row("REC", d.recovery.map { Double($0) / 100 }, d.recovery.map { "\($0) %" }, ComplicationColors.recovery(d.recoveryZone))
                row("CARGA", d.strain.map { $0 / 21 }, d.strain.map { FaceValues.decimal($0, digits: 1) }, ComplicationColors.strain)
                row("SUEÑO", d.sleepPerformance.map { Double($0) / 100 }, d.sleepMinutes.map { FaceValues.clockDuration(minutes: $0) },
                    ComplicationColors.sleep)
                if let workout {
                    Label(workout.text, systemImage: workout.symbol ?? "figure.run").font(.caption2).lineLimit(1)
                }
            }
        }
    }

    private func row(_ label: String, _ fraction: Double?, _ value: String?, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(color).frame(width: 38, alignment: .leading)
            Gauge(value: fraction ?? 0) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity).tint(color)
            Text(value ?? FaceValues.missing).font(.system(size: 12, weight: .semibold, design: .rounded)).frame(width: 40, alignment: .trailing)
        }
    }
}

// MARK: - Acceso a tus esferas

struct FacesLauncherComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FacesLauncherComplication", provider: FaceProvider()) { entry in
            FacesLauncherView()
                .containerBackground(ComplicationColors.background, for: .widget)
        }
        .configurationDisplayName("Mis esferas")
        .description("Abre tus esferas de Recupera con un toque.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

struct FacesLauncherView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCorner:
            Image(systemName: "applewatch.watchface")
                .font(.system(size: 20, weight: .semibold))
                .widgetLabel("Esferas")
        default:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "applewatch.watchface").font(.system(size: 22, weight: .semibold))
            }
        }
    }
}
