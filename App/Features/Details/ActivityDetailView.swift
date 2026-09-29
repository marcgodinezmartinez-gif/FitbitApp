import SwiftUI
import MapKit
import Charts
import MetricsKit
import Insights
import Store

/// Detalle de una actividad; en carreras del Apple Watch, mapa, parciales, dinámica de carrera y pulso de los dos
/// dispositivos superpuestos (doc. 11 §5, RF-FUS-10). Nunca se envían coordenadas al Coach.
struct ActivityDetailView: View {
    let activityID: String
    @Environment(AppModel.self) private var model

    @State private var route: [RoutePoint] = []
    @State private var hr: [HeartRateChart.Sample] = []
    @State private var rpe: Double = 5
    @State private var rpeSet = false

    var metrics: ActivityMetrics? { model.output?.cycles.flatMap(\.activities).first { $0.id == activityID } }

    var body: some View {
        ScrollView {
            if let a = metrics {
                let f = a.activity
                VStack(alignment: .leading, spacing: 16) {
                    header(a)
                    if !route.isEmpty {
                        RouteMap(points: route)
                            .frame(height: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                    statsGrid(a)
                    if f.sourcesDisagree {
                        InsightCard(text: "En esta actividad la FC del Apple Watch y la de la Fitbit Air difieren. Usamos la del \(f.hrSource?.label ?? "Apple Watch").",
                                    symbol: "exclamationmark.triangle", tint: Palette.recoveryMedium)
                    }
                    Card {
                        SectionHeader(title: "Frecuencia cardiaca", trailing: agreementText(f))
                        if hr.isEmpty {
                            Text("Sin muestras de FC para esta actividad.").font(.footnote).foregroundStyle(Palette.textSecondary)
                        } else {
                            HeartRateChart(samples: hr, zones: model.output?.cycles.last?.zones, compareSources: f.members.count > 1)
                        }
                        ZoneBar(minutes: a.strain.zoneMinutes)
                    }
                    let splits = RouteMath.splits(route)
                    if !splits.isEmpty {
                        Card {
                            SectionHeader(title: "Parciales por km")
                            Chart(splits) { s in
                                BarMark(x: .value("Km", "\(s.km)"), y: .value("Ritmo", s.seconds / 60))
                                    .foregroundStyle(Palette.strain.gradient)
                                    .cornerRadius(4)
                                    .annotation(position: .top) {
                                        Text(Format.pace(secondsPerKm: s.seconds)).font(.caption2).monospacedDigit()
                                    }
                            }
                            .chartYAxisLabel("min/km")
                            .frame(height: 180)
                        }
                    }
                    if let dyn = f.watchMember?.dynamics, !dyn.isEmpty {
                        Card {
                            SectionHeader(title: "Dinámica de carrera", trailing: "Apple Watch")
                            if let c = dyn.avgCadenceSpm { row("Cadencia", "\(Int(c.rounded())) ppm") }
                            if let p = dyn.avgPowerW { row("Potencia", "\(Int(p.rounded())) W") }
                            if let s = dyn.avgStrideM { row("Zancada", "\(Format.decimal(s, digits: 2)) m") }
                            if let v = dyn.avgVerticalOscillationCm { row("Oscilación vertical", "\(Format.decimal(v)) cm") }
                            if let g = dyn.avgGroundContactMs { row("Contacto con el suelo", "\(Int(g.rounded())) ms") }
                        }
                    }
                    Card {
                        SectionHeader(title: "¿Cuánto te costó?", trailing: "RPE 0–10")
                        Slider(value: $rpe, in: 0...10, step: 1) { editing in
                            if !editing { Task { await model.saveRPE(rpe, activity: f) } }
                        }
                        .tint(Palette.strain)
                        Text(rpeSet || f.rpe != nil ? "Tu valoración: \(Int(rpe))" : "Desliza para valorar el esfuerzo")
                            .font(.footnote).foregroundStyle(Palette.textSecondary)
                        if let effort = f.watchMember?.effortScore {
                            Text("Esfuerzo según Apple: \(Format.decimal(effort))").font(.footnote).foregroundStyle(Palette.textSecondary)
                        }
                    }
                    Card {
                        SectionHeader(title: "Fuentes")
                        ForEach(f.members, id: \.id) { m in
                            HStack {
                                Image(systemName: m.source.symbol)
                                Text(m.source.label)
                                Spacer()
                                Text("\(Format.clock(m.start, utcOffsetSeconds: m.utcOffsetSeconds))–\(Format.clock(m.end, utcOffsetSeconds: m.utcOffsetSeconds))")
                                    .foregroundStyle(Palette.textSecondary).monospacedDigit()
                            }
                            .font(.subheadline)
                        }
                        if f.members.count > 1 {
                            Text("Las dos sesiones se han fusionado en una sola actividad para no contar dos veces la carga.")
                                .font(.caption).foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
                .padding(16)
            } else {
                ContentUnavailableView("Actividad no encontrada", systemImage: "figure.run")
            }
        }
        .screenBackground()
        .navigationTitle(metrics?.activity.name ?? "Actividad")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: activityID) { load() }
    }

    private func load() {
        guard let a = metrics else { return }
        let f = a.activity
        if let r = f.rpe { rpe = r; rpeSet = true }
        if let db = model.db, !model.settings.demoMode {
            if let watch = f.watchMember { route = (try? db.route(activityID: watch.id)) ?? [] }
            let minutes = (try? db.hrMinutes(from: f.start, to: f.end)) ?? []
            hr = minutes.map { HeartRateChart.Sample(time: Date(timeIntervalSince1970: TimeInterval($0.minute)), bpm: $0.bpmAvg, source: $0.source) }
        }
        if hr.isEmpty, let output = model.output {
            let lo = f.start.minuteEpoch, hi = f.end.minuteEpoch
            hr = output.fusedHR.filter { $0.minute >= lo && $0.minute <= hi }
                .map { HeartRateChart.Sample(time: Date(timeIntervalSince1970: TimeInterval($0.minute)), bpm: $0.bpm, source: $0.source) }
        }
        if route.isEmpty, model.settings.demoMode, f.kind.isRun, let distance = f.distanceM, distance > 0 {
            route = RouteMath.demoLoop(distanceM: distance, start: f.start, end: f.end)
        }
    }

    private func header(_ a: ActivityMetrics) -> some View {
        let f = a.activity
        return HStack(spacing: 14) {
            Image(systemName: f.kind.symbolName).font(.title).foregroundStyle(Palette.strain)
                .frame(width: 56, height: 56).background(Palette.strain.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(f.name).font(.title3.weight(.bold))
                Text("\(Format.longDate(LocalDate(f.start, utcOffsetSeconds: f.primary.utcOffsetSeconds))) · \(Format.clock(f.start, utcOffsetSeconds: f.primary.utcOffsetSeconds))")
                    .font(.subheadline).foregroundStyle(Palette.textSecondary)
                SourceBadges(sources: f.sources)
            }
        }
    }

    private func statsGrid(_ a: ActivityMetrics) -> some View {
        let f = a.activity
        var items: [(String, String)] = [("Carga", Format.decimal(a.strain.strain)), ("Duración", Format.duration(minutes: f.durationMinutes))]
        if let d = f.distanceM, d > 0 { items.append(("Distancia", Format.km(d))) }
        if let p = f.paceSecondsPerKm, f.kind.isRun { items.append(("Ritmo medio", "\(Format.pace(secondsPerKm: p))/km")) }
        let avgHR = f.watchMember?.avgHR ?? f.primary.avgHR
        if let hr = avgHR { items.append(("FC media", "\(Int(hr.rounded())) lpm")) }
        if let mx = f.watchMember?.maxHR ?? f.primary.maxHR { items.append(("FC máx.", "\(Int(mx.rounded())) lpm")) }
        if let e = f.watchMember?.elevationGainM ?? f.primary.elevationGainM, e > 0 { items.append(("Desnivel", "\(Int(e.rounded())) m")) }
        if let rec = f.watchMember?.hrRecovery1Min { items.append(("FC recuperación 1 min", "\(Int(rec.rounded())) lpm")) }
        if let kcal = f.caloriesKcal { items.append(("Calorías", "\(Int(kcal.rounded())) kcal")) }
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(items, id: \.0) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.1).font(.metric(22, weight: .semibold)).monospacedDigit()
                    Text(item.0).font(.caption).foregroundStyle(Palette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private func agreementText(_ f: FusedActivity) -> String? {
        guard let ag = f.agreement else { return nil }
        return "Watch − Fitbit: \(Format.signed(ag.bias, digits: 1)) lpm"
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name).foregroundStyle(Palette.textSecondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.subheadline)
    }
}

/// Ruta coloreada por ritmo (más rápido, más intenso).
struct RouteMap: View {
    let points: [RoutePoint]

    var body: some View {
        let segments = RouteMath.coloredSegments(points)
        Map(initialPosition: .automatic, interactionModes: [.zoom, .pan]) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                MapPolyline(coordinates: seg.coordinates)
                    .stroke(seg.color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if let first = points.first {
                Annotation("Salida", coordinate: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)) {
                    Circle().fill(Palette.recoveryHigh).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .accessibilityLabel("Mapa de la ruta")
    }
}

enum RouteMath {
    struct Split: Identifiable {
        var km: Int
        var seconds: Double
        var id: Int { km }
    }

    struct Segment {
        var coordinates: [CLLocationCoordinate2D]
        var color: Color
    }

    static func distance(_ a: RoutePoint, _ b: RoutePoint) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Ruta ficticia (una vuelta por el Retiro, Madrid) solo para el modo demostración.
    static func demoLoop(distanceM: Double, start: Date, end: Date) -> [RoutePoint] {
        let center = (lat: 40.4153, lon: -3.6845)
        let lapLength = 4_200.0
        let laps = max(1.0, distanceM / lapLength)
        let count = 400
        let duration = end.timeIntervalSince(start)
        return (0...count).map { i in
            let t = Double(i) / Double(count)
            let angle = 2 * Double.pi * laps * t
            let wobble = 1 + 0.08 * sin(angle * 3)
            let lat = center.lat + 0.0062 * wobble * sin(angle)
            let lon = center.lon + 0.0081 * wobble * cos(angle)
            return RoutePoint(time: start.addingTimeInterval(duration * t), latitude: lat, longitude: lon)
        }
    }

    /// Tiempo de cada kilómetro completo.
    static func splits(_ points: [RoutePoint]) -> [Split] {
        guard points.count > 2 else { return [] }
        var out: [Split] = []
        var total = 0.0
        var kmStart = points[0].time
        var nextKm = 1000.0
        for i in 1..<points.count {
            total += distance(points[i - 1], points[i])
            if total >= nextKm {
                out.append(Split(km: Int(nextKm / 1000), seconds: points[i].time.timeIntervalSince(kmStart)))
                kmStart = points[i].time
                nextKm += 1000
            }
        }
        return out
    }

    /// Tramos de ~200 m coloreados según el ritmo relativo a la mediana.
    static func coloredSegments(_ points: [RoutePoint]) -> [Segment] {
        guard points.count > 2 else { return [] }
        var chunks: [[RoutePoint]] = [[points[0]]]
        var acc = 0.0
        for i in 1..<points.count {
            acc += distance(points[i - 1], points[i])
            chunks[chunks.count - 1].append(points[i])
            if acc >= 200 {
                chunks.append([points[i]])
                acc = 0
            }
        }
        let paces: [Double] = chunks.map { c in
            guard let a = c.first, let b = c.last, c.count > 1 else { return 0 }
            let d = zip(c, c.dropFirst()).reduce(0.0) { $0 + distance($1.0, $1.1) }
            return d > 0 ? b.time.timeIntervalSince(a.time) / d : 0
        }
        let valid = paces.filter { $0 > 0 }.sorted()
        let median = valid.isEmpty ? 0 : valid[valid.count / 2]
        return zip(chunks, paces).map { chunk, pace in
            let ratio = median > 0 && pace > 0 ? median / pace : 1   // > 1 = más rápido que la mediana
            let color: Color = ratio > 1.05 ? Palette.recoveryLow : (ratio < 0.95 ? Palette.strain : Palette.recoveryMedium)
            return Segment(coordinates: chunk.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }, color: color)
        }
    }
}
