import SwiftUI
import MapKit
import MetricsKit
import Insights
import RunKit

// MARK: - Tarjeta en «Correr»

struct SegmentsCard: View {
    let runs: RunsModel

    static func detail(_ seg: Segment, count: Int) -> String {
        var text = RunFormat.distance(seg.lengthM)
        if let g = seg.gradePct { text += " · " + Format.signed(g, digits: 1) + " %" }
        return text + " · " + RunFormat.count(count, "pasada", "pasadas")
    }

    var body: some View {
        Card {
            SectionHeader(title: "Segmentos", trailing: runs.segments.isEmpty ? nil : "tus tramos")
            if runs.segments.isEmpty {
                Text("Abre una carrera y crea un segmento con un tramo del mapa (tu cuesta, tu recta): la app busca todas las veces que lo has corrido y te dice tu mejor marca.")
                    .font(.subheadline).foregroundStyle(Palette.textSecondary)
            }
            ForEach(runs.segments) { seg in
                NavigationLink {
                    SegmentDetailView(segmentID: seg.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(seg.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                            Text(Self.detail(seg, count: runs.segmentCounts[seg.id] ?? 0)).font(.caption).foregroundStyle(Palette.textSecondary)
                        }
                        Spacer()
                        if let best = runs.segmentBests[seg.id] {
                            Text(RunFormat.time(best.seconds)).font(.subheadline.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(Palette.textPrimary)
                        }
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Palette.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Detalle de un segmento

struct SegmentDetailView: View {
    let segmentID: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var efforts: [SegmentEffort] = []
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false

    var body: some View {
        let runs = model.runs
        ScrollView {
            if let seg = runs.segments.first(where: { $0.id == segmentID }) {
                VStack(alignment: .leading, spacing: 16) {
                    SegmentMap(segment: seg)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    RunStatGrid(items: [("Longitud", RunFormat.distance(seg.lengthM)),
                                        ("Pendiente media", seg.gradePct.map { Format.signed($0, digits: 1) + " %" } ?? "–"),
                                        ("Desnivel positivo", "\(Int(seg.elevationGainM.rounded())) m"),
                                        ("Pasadas", "\(efforts.count)")])
                    if efforts.isEmpty {
                        Text("Aún no hay pasadas por este tramo.").font(.subheadline).foregroundStyle(Palette.textSecondary)
                    } else {
                        Card {
                            SectionHeader(title: "Tus mejores pasadas")
                            ForEach(Array(efforts.prefix(10).enumerated()), id: \.offset) { k, e in
                                NavigationLink(value: DetailRoute.run(e.runID)) {
                                    HStack {
                                        Text("\(k + 1)").font(.caption.weight(.bold)).frame(width: 22)
                                            .foregroundStyle(k == 0 ? Palette.recoveryHigh : Palette.textSecondary)
                                        Text(e.start.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)))
                                            .foregroundStyle(Palette.textSecondary)
                                        Spacer()
                                        Text("\(RunFormat.pace(e.pace)) /km").monospacedDigit().foregroundStyle(Palette.textSecondary)
                                        if let hr = e.avgHR { Text("\(Int(hr.rounded())) lpm").monospacedDigit().foregroundStyle(Palette.textSecondary) }
                                        Text(RunFormat.time(e.seconds)).fontWeight(.semibold).monospacedDigit()
                                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Palette.textSecondary)
                                    }
                                    .font(.subheadline)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if efforts.count >= 3 {
                            Card {
                                SectionHeader(title: "Evolución", trailing: "tiempo de cada pasada")
                                DatedValueChart(values: efforts.map { DatedValue(date: $0.start, value: $0.seconds, series: "Tiempo") },
                                                reversed: true, formatter: { RunFormat.time($0) }, colors: ["Tiempo": Palette.strain],
                                                smoothed: efforts.count >= 6 ? ["Tiempo"] : [])
                            }
                        }
                    }
                }
                .padding(16)
                .navigationTitle(seg.name)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                newName = seg.name
                                renaming = true
                            } label: { Label("Cambiar el nombre", systemImage: "pencil") }
                            Button(role: .destructive) { confirmDelete = true } label: { Label("Borrar el segmento", systemImage: "trash") }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                .alert("Nombre del segmento", isPresented: $renaming) {
                    TextField("Nombre", text: $newName)
                    Button("Guardar") { runs.renameSegment(seg, to: newName.trimmingCharacters(in: .whitespaces), model: model) }
                    Button("Cancelar", role: .cancel) {}
                }
                .confirmationDialog("¿Borrar este segmento?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Borrar", role: .destructive) {
                        runs.deleteSegment(seg, model: model)
                        dismiss()
                    }
                } message: {
                    Text("Se borran también sus pasadas; tus carreras no cambian.")
                }
            } else {
                ContentUnavailableView("Segmento no encontrado", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.dataVersion) { efforts = model.runs.efforts(segmentID: segmentID, model: model) }
    }
}

struct SegmentMap: View {
    let segment: Segment

    var body: some View {
        let coords = segment.points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        Map(initialPosition: .automatic, interactionModes: [.zoom, .pan]) {
            MapPolyline(coordinates: coords).stroke(Palette.strain, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            if let first = coords.first {
                Annotation("Salida", coordinate: first) { Circle().fill(Palette.recoveryHigh).frame(width: 14, height: 14).overlay(Circle().stroke(.white, lineWidth: 2)) }
            }
            if let last = coords.last {
                Annotation("Llegada", coordinate: last) { Circle().fill(Palette.recoveryLow).frame(width: 14, height: 14).overlay(Circle().stroke(.white, lineWidth: 2)) }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }
}

// MARK: - En cada carrera

struct RunSegmentsCard: View {
    let runID: String
    let route: [RoutePoint]

    static func rankText(rank: Int, of count: Int, behind seconds: Double) -> String {
        rank == 1 ? "Tu mejor pasada de \(count)" : "\(rank).ª de \(count) · +" + RunFormat.time(seconds) + " sobre tu mejor"
    }

    @Environment(AppModel.self) private var model
    @State private var efforts: [SegmentEffort] = []
    @State private var creating = false

    var body: some View {
        let runs = model.runs
        Card {
            SectionHeader(title: "Segmentos", trailing: efforts.isEmpty ? nil : "en esta carrera")
            ForEach(efforts) { e in
                if let seg = runs.segments.first(where: { $0.id == e.segmentID }) {
                    let all = runs.efforts(segmentID: seg.id, model: model)
                    let rank = SegmentLibrary.rank(of: e, in: all)
                    let best = all.first?.seconds ?? e.seconds
                    NavigationLink {
                        SegmentDetailView(segmentID: seg.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(seg.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                                    if rank == 1 && all.count > 1 { PRBadge() }
                                }
                                Text(Self.rankText(rank: rank, of: all.count, behind: e.seconds - best))
                                    .font(.caption).foregroundStyle(Palette.textSecondary)
                            }
                            Spacer()
                            Text(RunFormat.time(e.seconds)).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.textPrimary)
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            if efforts.isEmpty {
                Text("Esta carrera no pasa por ninguno de tus segmentos.").font(.caption).foregroundStyle(Palette.textSecondary)
            }
            if route.count > 2 {
                Button {
                    creating = true
                } label: {
                    Label("Crear un segmento con un tramo de esta carrera", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .task(id: "\(runID)-\(model.dataVersion)-\(runs.segments.count)") { efforts = runs.efforts(runID: runID, model: model) }
        .sheet(isPresented: $creating) { SegmentCreatorView(route: route, runID: runID) }
    }
}

// MARK: - Crear un segmento

struct SegmentCreatorView: View {
    let route: [RoutePoint]
    let runID: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var from = 0.0
    @State private var to = 1000.0
    @State private var name = ""
    @State private var saving = false
    @State private var message: String?

    private var points: [RoutePoint] { route.filter { ($0.horizontalAccuracy ?? 0) <= 50 } }

    private var cumulative: [Double] {
        var out = [0.0]
        for (a, b) in zip(points, points.dropFirst()) { out.append(out.last! + Geo.distance(a.latitude, a.longitude, b.latitude, b.longitude)) }
        return out
    }

    var body: some View {
        let cum = cumulative
        let total = cum.last ?? 0
        let all = points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        let selected = zip(points, cum).filter { $0.1 >= from && $0.1 <= to }.map { CLLocationCoordinate2D(latitude: $0.0.latitude, longitude: $0.0.longitude) }
        NavigationStack {
            Form {
                Section {
                    Map(initialPosition: .automatic, interactionModes: [.zoom, .pan]) {
                        MapPolyline(coordinates: all).stroke(Palette.textSecondary.opacity(0.6), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                        MapPolyline(coordinates: selected).stroke(Palette.strain, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                        if let first = selected.first {
                            Annotation("", coordinate: first) { Circle().fill(Palette.recoveryHigh).frame(width: 12, height: 12) }
                        }
                        if let last = selected.last {
                            Annotation("", coordinate: last) { Circle().fill(Palette.recoveryLow).frame(width: 12, height: 12) }
                        }
                    }
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    VStack(alignment: .leading) {
                        Text("Empieza en el km \(Format.decimal(from / 1000, digits: 2))").font(.subheadline)
                        Slider(value: $from, in: 0...max(1, total - 200), step: 10)
                    }
                    VStack(alignment: .leading) {
                        Text("Acaba en el km \(Format.decimal(to / 1000, digits: 2))").font(.subheadline)
                        Slider(value: $to, in: min(200, total)...max(200, total), step: 10)
                    }
                    LabeledContent("Longitud", value: RunFormat.distance(max(0, to - from)))
                    TextField("Nombre (p. ej. La cuesta del parque)", text: $name)
                } footer: {
                    Text("Tiene que medir al menos 200 m. Cuenta en el sentido en que lo corriste: la app busca tus pasadas en todas las carreras con GPS.")
                }
                if let message { Section { Text(message).font(.footnote) } }
            }
            .navigationTitle("Nuevo segmento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Buscando…" : "Guardar") { Task { await save() } }
                        .disabled(saving || to - from < 200 || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                from = min(from, max(0, total - 1200))
                to = min(total, from + 1000)
            }
            .onChange(of: from) { _, v in if to < v + 200 { to = min(total, v + 200) } }
            .onChange(of: to) { _, v in if from > v - 200 { from = max(0, v - 200) } }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        guard await model.runs.createSegment(name: name.trimmingCharacters(in: .whitespaces), route: route, fromM: from, toM: to,
                                             runID: runID, model: model) != nil else {
            message = "No se ha podido crear el segmento con ese tramo."
            return
        }
        Haptics.success()
        dismiss()
    }
}
