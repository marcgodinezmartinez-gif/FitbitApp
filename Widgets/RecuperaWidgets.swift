import WidgetKit
import SwiftUI
import MetricsKit

// Widgets de inicio y de pantalla de bloqueo (doc. 11 §10). Leen solo la instantánea ligera del App Group.

struct SnapshotEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
    var isPlaceholder = false
}

enum SnapshotStore {
    static var url: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "RecuperaAppGroup") as? String, !group.contains("$(") else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("widget-snapshot.json")
    }

    static func load() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: SnapshotStore.load() ?? .placeholder, isPlaceholder: SnapshotStore.load() == nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = SnapshotStore.load()
        let entry = SnapshotEntry(date: Date(), snapshot: snapshot ?? .placeholder, isPlaceholder: snapshot == nil)
        // La app recarga los widgets al sincronizar; aquí solo se refresca de vez en cuando.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3 * 3600))))
    }
}

enum WidgetColors {
    static let sleep = Color(red: 0.70, green: 0.55, blue: 1.0)
    static let strain = Color(red: 0.30, green: 0.64, blue: 1.0)
    static let high = Color(red: 0.24, green: 0.86, blue: 0.52)
    static let medium = Color(red: 1.0, green: 0.82, blue: 0.25)
    static let low = Color(red: 1.0, green: 0.36, blue: 0.36)
    static let background = Color(red: 0.03, green: 0.03, blue: 0.04)

    static func recovery(_ zone: String?) -> Color {
        switch zone {
        case "high": return high
        case "medium": return medium
        case "low": return low
        default: return .gray
        }
    }
}

struct MiniRing: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat
    var label: String

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.002, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label).font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6)
        }
        .padding(lineWidth / 2)
    }
}

struct RingsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        let s = entry.snapshot
        switch family {
        case .systemMedium:
            HStack(spacing: 14) {
                rings(s, size: 58)
                VStack(alignment: .leading, spacing: 6) {
                    Text(s.recommendation).font(.system(size: 13, weight: .medium)).foregroundStyle(.white).lineLimit(4)
                    if let bed = s.bedtime {
                        Label("Acuéstate a las \(bed)", systemImage: "bed.double.fill").font(.caption2).foregroundStyle(WidgetColors.sleep)
                    }
                }
            }
        default:
            VStack(spacing: 6) {
                MiniRing(progress: Double(s.recovery ?? 0) / 100, color: WidgetColors.recovery(s.recoveryZone), lineWidth: 9,
                         label: s.recovery.map { "\($0)%" } ?? "—")
                    .frame(width: 78, height: 78)
                HStack(spacing: 10) {
                    small(value: s.sleepPerformance.map { "\($0)%" } ?? "—", title: "Sueño", color: WidgetColors.sleep)
                    small(value: String(format: "%.1f", s.strain), title: "Carga", color: WidgetColors.strain)
                }
            }
        }
    }

    private func rings(_ s: WidgetSnapshot, size: CGFloat) -> some View {
        HStack(spacing: 6) {
            MiniRing(progress: Double(s.sleepPerformance ?? 0) / 100, color: WidgetColors.sleep, lineWidth: 7,
                     label: s.sleepPerformance.map { "\($0)%" } ?? "—").frame(width: size, height: size)
            MiniRing(progress: Double(s.recovery ?? 0) / 100, color: WidgetColors.recovery(s.recoveryZone), lineWidth: 7,
                     label: s.recovery.map { "\($0)%" } ?? "—").frame(width: size, height: size)
            MiniRing(progress: s.strain / 21, color: WidgetColors.strain, lineWidth: 7,
                     label: String(format: "%.1f", s.strain)).frame(width: size, height: size)
        }
    }

    private func small(value: String, title: String, color: Color) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(color).monospacedDigit()
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}

struct LockScreenView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        let s = entry.snapshot
        let showValues = s.showValuesOnLockScreen ?? false
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(s.recovery ?? 0), in: 0...100) {
                Image(systemName: "heart")
            } currentValueLabel: {
                Text(showValues ? (s.recovery.map { "\($0)" } ?? "—") : "·").monospacedDigit()
            }
            .gaugeStyle(.accessoryCircular)
            .privacySensitive(!showValues)
        default:
            VStack(alignment: .leading, spacing: 2) {
                Text("Recupera").font(.headline)
                if showValues {
                    Text("Recup. \(s.recovery.map { "\($0)%" } ?? "—") · Sueño \(s.sleepPerformance.map { "\($0)%" } ?? "—")")
                        .font(.caption).monospacedDigit()
                    Text("Carga \(String(format: "%.1f", s.strain))\(s.bedtime.map { " · cama \($0)" } ?? "")").font(.caption).monospacedDigit()
                } else {
                    Text(s.recovery == nil ? "Sin datos de hoy" : "Tu día está listo").font(.caption)
                }
            }
            .privacySensitive(!showValues)
        }
    }
}

struct RingsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecuperaRings", provider: SnapshotProvider()) { entry in
            RingsWidgetView(entry: entry)
                .containerBackground(WidgetColors.background, for: .widget)
        }
        .configurationDisplayName("Tu día")
        .description("Sueño, recuperación y carga de hoy.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecuperaLock", provider: SnapshotProvider()) { entry in
            LockScreenView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Recuperación")
        .description("Tu recuperación en la pantalla de bloqueo.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

@main
struct RecuperaWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RingsWidget()
        LockScreenWidget()
    }
}
