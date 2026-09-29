import SwiftUI
import Charts
import MapKit
import MetricsKit
import Insights
import Store
import RunKit

// MARK: - Formatos

enum RunFormat {
    static func pace(_ secondsPerKm: Double?) -> String {
        guard let s = secondsPerKm, s.isFinite, s > 0 else { return "–" }
        return Format.pace(secondsPerKm: s)
    }

    static func paceFromSpeed(_ speed: Double?) -> String {
        guard let v = speed, v > 0.3 else { return "–" }
        return Format.pace(secondsPerKm: 1000 / v)
    }

    static func distance(_ meters: Double) -> String {
        meters >= 1000 ? Format.decimal(meters / 1000, digits: 2) + " km" : "\(Int(meters.rounded())) m"
    }

    static func time(_ seconds: Double) -> String { Format.raceTime(seconds: seconds) }

    static func number(_ v: Double?, digits: Int = 0, unit: String = "") -> String {
        guard let v, v.isFinite else { return "–" }
        let text = digits == 0 ? "\(Int(v.rounded()))" : Format.decimal(v, digits: digits)
        return unit.isEmpty ? text : "\(text) \(unit)"
    }

    static func date(_ s: RunSummary) -> String {
        "\(Format.weekdayName(s.date).capitalized) \(s.date.day) \(Format.monthName(s.date.month).prefix(3))"
    }
}

extension FormMetric.Rating {
    var color: Color {
        switch self {
        case .excellent, .good: return Palette.recoveryHigh
        case .fair: return Palette.recoveryMedium
        case .poor: return Palette.recoveryLow
        case .info: return Palette.textSecondary
        }
    }
}

// MARK: - Piezas

/// Cifra con su etiqueta, en una rejilla de dos columnas.
struct RunStatGrid: View {
    var items: [(String, String)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.1).font(.metric(20, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    Text(item.0).font(.caption).foregroundStyle(Palette.textSecondary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }
}

/// Barra apilada con etiquetas (zonas de ritmo o de potencia).
struct LabeledZoneBar: View {
    var seconds: [Double]
    var labels: [String]
    var colors: [Color]

    private var total: Double { max(1, seconds.reduce(0, +)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(seconds.indices, id: \.self) { i in
                        if seconds[i] > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(colors[min(i, colors.count - 1)])
                                .frame(width: max(3, geo.size.width * seconds[i] / total - 2))
                        }
                    }
                }
            }
            .frame(height: 12)
            FlowRow(items: seconds.indices.filter { seconds[$0] > 0 }.map { i in
                "\(labels[min(i, labels.count - 1)]) \(Int((seconds[i] / 60).rounded()))′"
            })
        }
    }
}

/// Etiquetas pequeñas que saltan de línea.
struct FlowRow: View {
    var items: [String]

    var body: some View {
        let rows = stride(from: 0, to: items.count, by: 3).map { Array(items[$0..<min($0 + 3, items.count)]) }
        VStack(alignment: .leading, spacing: 2) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 10) {
                    ForEach(rows[r], id: \.self) { Text($0).font(.caption2).monospacedDigit().foregroundStyle(Palette.textSecondary) }
                }
            }
        }
    }
}

struct RatingBadge: View {
    var rating: FormMetric.Rating

    var body: some View {
        if rating != .info {
            Text(rating.label).font(.caption.weight(.semibold)).foregroundStyle(rating.color)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(rating.color.opacity(0.14), in: Capsule())
        }
    }
}

struct PRBadge: View {
    var body: some View {
        Label("Récord", systemImage: "trophy.fill").font(.caption2.weight(.semibold)).foregroundStyle(Palette.recoveryMedium)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Palette.recoveryMedium.opacity(0.14), in: Capsule())
    }
}

/// Fila de tabla de dos columnas.
struct RunRow: View {
    var name: String
    var value: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).foregroundStyle(Palette.textSecondary)
            Spacer()
            if let detail { Text(detail).font(.caption).foregroundStyle(Palette.textSecondary) }
            Text(value).monospacedDigit()
        }
        .font(.subheadline)
    }
}

// MARK: - Gráficas del historial

struct VolumeChart: View {
    var periods: [RunPeriod]
    var monthly: Bool

    var body: some View {
        Chart(periods) { p in
            BarMark(x: .value("Periodo", p.start.startDate(utcOffsetSeconds: 0), unit: monthly ? .month : .weekOfYear),
                    y: .value("Km", p.distanceM / 1000))
                .foregroundStyle(Palette.strain.gradient)
                .cornerRadius(4)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisValueLabel(format: monthly ? .dateTime.month(.abbreviated) : .dateTime.day().month(.abbreviated))
            }
        }
        .chartYAxisLabel("km")
        .frame(height: 170)
    }
}

struct FitnessChart: View {
    var points: [FitnessPoint]

    var body: some View {
        Chart {
            ForEach(points) { p in
                LineMark(x: .value("Día", p.date.startDate(utcOffsetSeconds: 0)), y: .value("Valor", p.fitness), series: .value("Serie", "Forma"))
                    .foregroundStyle(by: .value("Serie", "Forma"))
                LineMark(x: .value("Día", p.date.startDate(utcOffsetSeconds: 0)), y: .value("Valor", p.fatigue), series: .value("Serie", "Fatiga"))
                    .foregroundStyle(by: .value("Serie", "Fatiga"))
                BarMark(x: .value("Día", p.date.startDate(utcOffsetSeconds: 0), unit: .day), y: .value("Frescura", p.form))
                    .foregroundStyle(by: .value("Serie", "Frescura"))
                    .opacity(0.45)
            }
        }
        .chartForegroundStyleScale(["Forma": Palette.strain, "Fatiga": Palette.stress, "Frescura": Palette.recoveryHigh])
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
        .frame(height: 180)
    }
}

/// Serie con fecha para las tendencias.
struct DatedValue: Identifiable, Hashable {
    var date: Date
    var value: Double
    var series: String
    var id: String { "\(series)-\(date.timeIntervalSince1970)" }
}

struct DatedValueChart: View {
    var values: [DatedValue]
    var reversed = false
    var formatter: (Double) -> String = { Format.decimal($0) }
    var colors: KeyValuePairs<String, Color> = ["Valor": Palette.strain]

    var body: some View {
        Chart(values) { v in
            LineMark(x: .value("Fecha", v.date), y: .value("Valor", v.value), series: .value("Serie", v.series))
                .foregroundStyle(by: .value("Serie", v.series))
                .interpolationMethod(.monotone)
                .opacity(0.5)
            PointMark(x: .value("Fecha", v.date), y: .value("Valor", v.value))
                .foregroundStyle(by: .value("Serie", v.series))
                .symbolSize(24)
        }
        .chartForegroundStyleScale(colors)
        .chartYScale(domain: .automatic(includesZero: false, reversed: reversed))
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Palette.separator)
                AxisValueLabel { if let v = value.as(Double.self) { Text(formatter(v)) } }
            }
        }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
        .frame(height: 180)
    }
}

// MARK: - Gráficas de una carrera

enum RunChartMetric: String, CaseIterable, Identifiable {
    case pace, heartRate, altitude, cadence, power, stride, verticalOsc, groundContact

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pace: return "Ritmo"
        case .heartRate: return "FC"
        case .altitude: return "Altitud"
        case .cadence: return "Cadencia"
        case .power: return "Potencia"
        case .stride: return "Zancada"
        case .verticalOsc: return "Oscilación"
        case .groundContact: return "Contacto"
        }
    }

    var unit: String {
        switch self {
        case .pace: return "/km"
        case .heartRate: return "lpm"
        case .altitude: return "m"
        case .cadence: return "ppm"
        case .power: return "W"
        case .stride: return "m"
        case .verticalOsc: return "cm"
        case .groundContact: return "ms"
        }
    }

    var color: Color {
        switch self {
        case .pace: return Palette.strain
        case .heartRate: return Palette.recoveryLow
        case .altitude: return Palette.textSecondary
        case .cadence: return Palette.sleep
        case .power: return Palette.stress
        case .stride, .verticalOsc, .groundContact: return Palette.fitbit
        }
    }

    func value(_ p: ChartPoint) -> Double? {
        switch self {
        case .pace: return p.pace
        case .heartRate: return p.hr
        case .altitude: return p.altitude
        case .cadence: return p.cadence
        case .power: return p.power
        case .stride: return p.stride
        case .verticalOsc: return p.verticalOsc
        case .groundContact: return p.groundContact
        }
    }

    func format(_ v: Double) -> String {
        switch self {
        case .pace: return Format.pace(secondsPerKm: v)
        case .stride: return Format.decimal(v, digits: 2)
        case .verticalOsc: return Format.decimal(v)
        default: return "\(Int(v.rounded()))"
        }
    }
}

/// Gráfica de una métrica de la carrera por distancia o por tiempo, con selección al deslizar el dedo.
struct RunMetricChart: View {
    var points: [ChartPoint]
    var metric: RunChartMetric
    var byDistance: Bool
    var zones: HRZones?
    @State private var selected: Double?

    private func x(_ p: ChartPoint) -> Double { byDistance ? p.km : p.t / 60 }

    private var valid: [ChartPoint] { points.filter { metric.value($0) != nil } }

    private var nearest: ChartPoint? {
        guard let selected else { return nil }
        return valid.min { abs(x($0) - selected) < abs(x($1) - selected) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let p = nearest, let v = metric.value(p) {
                    Text("\(metric.format(v)) \(metric.unit)").font(.headline).monospacedDigit()
                    if metric == .heartRate, let f = p.hrFitbit, let w = p.hrWatch {
                        Text("Watch \(Int(w.rounded())) · Fitbit \(Int(f.rounded()))").font(.caption).foregroundStyle(Palette.textSecondary)
                    }
                    Spacer()
                    Text(byDistance ? "km \(Format.decimal(p.km, digits: 2))" : RunFormat.time(p.t))
                        .font(.caption).foregroundStyle(Palette.textSecondary).monospacedDigit()
                } else {
                    Text("Desliza sobre la gráfica").font(.caption).foregroundStyle(Palette.textSecondary)
                }
            }
            chart
        }
    }

    private var chart: some View {
        Chart {
            if metric == .heartRate, let zones {
                ForEach(Array(zones.lowerBounds.enumerated()), id: \.offset) { i, lb in
                    RuleMark(y: .value("Zona", lb))
                        .foregroundStyle(Palette.zones[min(i + 1, Palette.zones.count - 1)].opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
            }
            ForEach(valid, id: \.t) { p in
                if metric == .altitude {
                    AreaMark(x: .value("X", x(p)), y: .value(metric.label, metric.value(p) ?? 0))
                        .foregroundStyle(LinearGradient(colors: [metric.color.opacity(0.5), metric.color.opacity(0.05)],
                                                        startPoint: .top, endPoint: .bottom))
                } else if metric == .heartRate && p.hrWatch != nil && p.hrFitbit != nil {
                    LineMark(x: .value("X", x(p)), y: .value("lpm", p.hrWatch ?? 0), series: .value("Fuente", "Apple Watch"))
                        .foregroundStyle(by: .value("Fuente", "Apple Watch"))
                    LineMark(x: .value("X", x(p)), y: .value("lpm", p.hrFitbit ?? 0), series: .value("Fuente", "Fitbit Air"))
                        .foregroundStyle(by: .value("Fuente", "Fitbit Air"))
                } else {
                    LineMark(x: .value("X", x(p)), y: .value(metric.label, metric.value(p) ?? 0))
                        .foregroundStyle(metric.color)
                        .interpolationMethod(.monotone)
                }
                if metric == .pace, let g = p.gap {
                    LineMark(x: .value("X", x(p)), y: .value("GAP", g), series: .value("Serie", "GAP"))
                        .foregroundStyle(Palette.textSecondary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            if let p = nearest {
                RuleMark(x: .value("X", x(p))).foregroundStyle(Palette.textSecondary.opacity(0.6))
            }
        }
        .chartForegroundStyleScale(["Apple Watch": Palette.recoveryLow, "Fitbit Air": Palette.fitbit])
        .chartLegend(metric == .heartRate ? .visible : .hidden)
        .chartXSelection(value: $selected)
        .chartYScale(domain: .automatic(includesZero: false, reversed: metric == .pace))
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Palette.separator)
                AxisValueLabel { if let v = value.as(Double.self) { Text(metric.format(v)) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisValueLabel { if let v = value.as(Double.self) { Text(byDistance ? "\(Format.decimal(v, digits: v < 10 ? 1 : 0))" : "\(Int(v))′") } }
            }
        }
        .frame(height: 200)
    }
}

/// Curva de mejores medias (ritmo o potencia) por duración.
struct CurveChart: View {
    var points: [CurvePoint]
    var isPace: Bool

    private func label(_ seconds: Double) -> String { seconds >= 60 ? "\(Int(seconds / 60))′" : "\(Int(seconds))″" }

    var body: some View {
        Chart(points, id: \.seconds) { p in
            LineMark(x: .value("Duración", label(p.seconds)), y: .value("Valor", isPace ? 1000 / p.value : p.value))
                .foregroundStyle(isPace ? Palette.strain : Palette.stress)
            PointMark(x: .value("Duración", label(p.seconds)), y: .value("Valor", isPace ? 1000 / p.value : p.value))
                .foregroundStyle(isPace ? Palette.strain : Palette.stress)
                .annotation(position: .top) {
                    Text(isPace ? Format.pace(secondsPerKm: 1000 / p.value) : "\(Int(p.value.rounded()))")
                        .font(.caption2).monospacedDigit().foregroundStyle(Palette.textSecondary)
                }
        }
        .chartYScale(domain: .automatic(includesZero: false, reversed: isPace))
        .chartYAxis(.hidden)
        .frame(height: 150)
    }
}

// MARK: - Mapa

enum RouteColorMetric: String, CaseIterable, Identifiable {
    case pace, heartRate, altitude, power, cadence

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pace: return "Ritmo"
        case .heartRate: return "FC"
        case .altitude: return "Altitud"
        case .power: return "Potencia"
        case .cadence: return "Cadencia"
        }
    }

    func value(_ s: RunSeries, _ i: Int) -> Double? {
        switch self {
        case .pace: return s.moving[i] ? s.speed[i] : nil
        case .heartRate: return s.hr[i]
        case .altitude: return s.altitude[i]
        case .power: return s.power[i]
        case .cadence: return s.cadence[i]
        }
    }

    func available(in s: RunSeries) -> Bool { (0..<s.count).contains { value(s, $0) != nil } }
}

/// Ruta coloreada por la métrica elegida (5 tramos de color por quintiles), con marcas de cada km.
struct RunRouteMap: View {
    var route: [RoutePoint]
    var series: RunSeries
    var metric: RouteColorMetric

    struct Segment {
        var coordinates: [CLLocationCoordinate2D]
        var color: Color
    }

    struct KmMark: Identifiable {
        var km: Int
        var coordinate: CLLocationCoordinate2D
        var id: Int { km }
    }

    private var content: (segments: [Segment], kms: [KmMark]) {
        let pts = route.filter { ($0.horizontalAccuracy ?? 0) <= 50 }
        guard pts.count > 2 else { return ([], []) }
        let chunk = max(2, pts.count / 120)
        var groups: [[RoutePoint]] = []
        var i = 0
        while i < pts.count - 1 {
            groups.append(Array(pts[i...min(pts.count - 1, i + chunk)]))
            i += chunk
        }
        let values: [Double?] = groups.map { g in
            let idx = series.index(at: g[g.count / 2].time)
            return metric.value(series, idx)
        }
        let sorted = values.compactMap { $0 }.sorted()
        func color(_ v: Double?) -> Color {
            guard let v, !sorted.isEmpty else { return Palette.textSecondary }
            let rank = Double(sorted.firstIndex { $0 >= v } ?? sorted.count - 1) / Double(max(1, sorted.count - 1))
            let colors = [Palette.zones[1], Palette.zones[2], Palette.zones[3], Palette.zones[4], Palette.zones[5]]
            return colors[min(4, Int(rank * 5))]
        }
        let segments = zip(groups, values).map { g, v in
            Segment(coordinates: g.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }, color: color(v))
        }
        var kms: [KmMark] = []
        var next = 1000.0
        for p in pts {
            let d = series.distance[series.index(at: p.time)]
            if d >= next {
                kms.append(KmMark(km: Int(next / 1000), coordinate: CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude)))
                next += 1000
            }
        }
        return (segments, kms)
    }

    var body: some View {
        let c = content
        Map(initialPosition: .automatic, interactionModes: [.zoom, .pan]) {
            ForEach(Array(c.segments.enumerated()), id: \.offset) { _, seg in
                MapPolyline(coordinates: seg.coordinates)
                    .stroke(seg.color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            ForEach(c.kms) { km in
                Annotation("", coordinate: km.coordinate) {
                    Text("\(km.km)").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 16, height: 16).background(Circle().fill(Color.black.opacity(0.7)))
                }
            }
            if let first = route.first {
                Annotation("Salida", coordinate: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)) {
                    Circle().fill(Palette.recoveryHigh).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
            if let last = route.last {
                Annotation("Llegada", coordinate: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)) {
                    Circle().fill(Palette.recoveryLow).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
        .accessibilityLabel("Mapa de la ruta coloreado por \(metric.label.lowercased())")
    }
}
