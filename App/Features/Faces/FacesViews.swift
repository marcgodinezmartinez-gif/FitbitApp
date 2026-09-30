import SwiftUI
import UIKit
import FaceKit

// Apartado «Esferas del Apple Watch» (doc. 19): tus esferas, la galería de plantillas y el editor con vista previa en vivo.
// Se guardan en el iPhone y se mandan solas al reloj, donde se ven dentro de la app de Recupera.

struct FacesView: View {
    @Environment(AppModel.self) private var model
    @State private var library = FaceLibrary()
    @State private var editing: EditingFace?
    @State private var choosingTemplate = false
    @State private var link = WatchLink.shared

    /// Lo del iPhone y, para ver cómo quedan, valores de ejemplo de lo que mide el reloj.
    private var previewData: FaceData { WatchLink.faceData(model: model).merged(withWatch: .demo()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WatchStatusCard(link: link)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 18) {
                    ForEach(library.designs) { design in
                        Button {
                            editing = EditingFace(design: design, isNew: false)
                        } label: {
                            VStack(spacing: 8) {
                                WatchPreview(design: design, data: previewData, night: design.startsInNightMode)
                                    .frame(height: 188)
                                Text(design.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary).lineLimit(1)
                                Text(design.name == design.template.name ? design.template.summaryShort : design.template.name)
                                    .font(.caption).foregroundStyle(Palette.textSecondary).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { update { _ = $0.duplicate(design.id) } } label: { Label("Duplicar", systemImage: "plus.square.on.square") }
                            if let i = library.designs.firstIndex(of: design), i > 0 {
                                Button { update { $0.move(from: i, to: i - 1) } } label: { Label("Antes", systemImage: "arrow.left") }
                            }
                            if let i = library.designs.firstIndex(of: design), i < library.designs.count - 1 {
                                Button { update { $0.move(from: i, to: i + 1) } } label: { Label("Después", systemImage: "arrow.right") }
                            }
                            Button(role: .destructive) { update { $0.delete(design.id) } } label: { Label("Borrar", systemImage: "trash") }
                        }
                    }
                    Button { choosingTemplate = true } label: {
                        VStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 34, style: .continuous)
                                .strokeBorder(Palette.separator, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                                .overlay { Image(systemName: "plus").font(.title.weight(.semibold)).foregroundStyle(Palette.recoveryHigh) }
                                .frame(width: 150, height: 188)
                            Text("Nueva esfera").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                            Text("Elige una plantilla").font(.caption).foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                FacesHowToCard()
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Esferas del Watch")
        .sheet(item: $editing) { item in
            NavigationStack {
                FaceEditorView(design: item.design, isNew: item.isNew, data: previewData) { saved in
                    update { $0.save(saved) }
                } onDelete: {
                    update { $0.delete(item.design.id) }
                }
            }
        }
        .sheet(isPresented: $choosingTemplate) {
            NavigationStack {
                TemplateGallery(data: previewData) { template in
                    choosingTemplate = false
                    editing = EditingFace(design: template.defaultDesign(), isNew: true)
                }
            }
        }
        .onAppear {
            library = WatchLink.library(db: model.db)
            if AppModel.screenshotScreen == "face-editor", editing == nil, let first = library.designs.first {
                editing = EditingFace(design: first, isNew: false)
            }
        }
    }

    /// Cambia tus esferas, las guarda y las manda al reloj.
    private func update(_ change: (inout FaceLibrary) -> Void) {
        change(&library)
        if AppModel.screenshotScreen == nil { WatchLink.save(library, db: model.db) }
        WatchLink.shared.send(library: library, data: WatchLink.faceData(model: model))
    }
}

struct EditingFace: Identifiable {
    var design: FaceDesign
    var isNew: Bool
    var id: String { design.id }
}

/// Si el reloj está listo y cuándo se mandaron las esferas por última vez.
private struct WatchStatusCard: View {
    let link: WatchLink

    var body: some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: link.isReady ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                    .font(.title2).foregroundStyle(link.isReady ? Palette.recoveryHigh : Palette.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var title: String {
        if link.isReady { return "En tu Apple Watch" }
        return link.isPaired ? "Falta la app en el reloj" : "Sin Apple Watch emparejado"
    }

    private var detail: String {
        if link.isReady {
            if let sent = link.lastSentAt { return "Tus esferas y tus datos se mandan solos. Último envío: \(sent.formatted(date: .omitted, time: .shortened))." }
            return "Tus esferas y tus datos se mandan solos cada vez que cambian."
        }
        if link.isPaired { return "Instálala desde la app Watch del iPhone (Apps disponibles) o activa la instalación automática." }
        return "Puedes diseñar tus esferas igualmente: se mandarán cuando emparejes el reloj."
    }
}

/// Cómo se usan en el reloj (y por qué no son esferas del sistema).
private struct FacesHowToCard: View {
    var body: some View {
        Card {
            SectionHeader(title: "En el reloj", trailing: nil)
            VStack(alignment: .leading, spacing: 8) {
                step("hand.draw", "Abre Recupera en el Watch y desliza para pasar de una esfera a otra.")
                step("digitalcrown.horizontal.arrow.clockwise", "Gira la corona hacia arriba para el modo noche (todo en rojo) y hacia abajo para quitarlo.")
                step("clock.arrow.circlepath", "Para que se quede puesta: en el reloj, Ajustes › General › Volver al reloj › Recupera › Después de 1 hora.")
                step("square.grid.2x2", "En tu esfera de Apple, añade la complicación «Mis esferas» de Recupera para volver con un toque.")
            }
            Text("Apple no deja que ninguna app instale esferas propias en el reloj, así que estas se ven dentro de la app de Recupera.")
                .font(.caption).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func step(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).frame(width: 22).foregroundStyle(Palette.recoveryHigh)
            Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Plantillas

extension FaceTemplate {
    /// Una línea para la galería.
    var summaryShort: String {
        switch self {
        case .ultraModular: return "Estilo Modular Ultra"
        case .wayfinder: return "Estilo Wayfinder"
        case .recovery: return "Anillo de recuperación"
        case .analog: return "Agujas clásicas"
        case .digital: return "Hora enorme"
        }
    }
}

struct TemplateGallery: View {
    let data: FaceData
    let onChoose: (FaceTemplate) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(FaceTemplate.allCases) { template in
            Button { onChoose(template) } label: {
                HStack(spacing: 14) {
                    WatchPreview(design: template.defaultDesign(id: "preview-\(template.rawValue)"), data: data)
                        .frame(width: 96, height: 118)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(template.name).font(.headline).foregroundStyle(Palette.textPrimary)
                        Text(template.summary).font(.caption).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Elige una plantilla")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
    }
}

// MARK: - Editor

struct FaceEditorView: View {
    @State var design: FaceDesign
    let isNew: Bool
    let data: FaceData
    let onSave: (FaceDesign) -> Void
    var onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var night = false
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section {
                WatchPreview(design: design.normalized(), data: data, night: night, live: true)
                    .frame(height: 300)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                Toggle("Ver en modo noche", isOn: $night)
            }
            Section("Nombre") {
                TextField("Nombre", text: $design.name)
            }
            Section("Color") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                    ForEach(FaceColor.presets) { preset in
                        Button { setAccent(preset.color) } label: {
                            Circle().fill(Color(preset.color)).frame(width: 34, height: 34)
                                .overlay { Circle().strokeBorder(Palette.textPrimary, lineWidth: design.accent == preset.color ? 3 : 0) }
                                .accessibilityLabel(preset.name)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                ColorPicker("Otro color", selection: Binding(get: { Color(design.accent) }, set: { setAccent(FaceColor(uiColor: UIColor($0))) }),
                            supportsOpacity: false)
                Picker("Fondo", selection: Binding(get: { BackgroundChoice(design.background) }, set: { setBackground($0) })) {
                    ForEach(BackgroundChoice.allCases) { Text($0.name).tag($0) }
                }
            }
            Section("Hora") {
                Picker("Letra", selection: $design.font) {
                    ForEach(FaceFont.allCases) { Text($0.name).tag($0) }
                }
                if !design.template.hasHands { Toggle("24 horas", isOn: $design.use24h) }
                Toggle(design.template.hasHands ? "Segundero" : "Segundos", isOn: $design.showSeconds)
                if design.template.hasHands {
                    Picker("Marcas", selection: $design.dial) {
                        ForEach(FaceDial.allCases) { Text($0.name).tag($0) }
                    }
                }
                if design.template.bezels.count > 1 {
                    Picker("Bisel", selection: $design.bezel) {
                        ForEach(design.template.bezels) { Text($0.name).tag($0) }
                    }
                }
            }
            Section {
                ForEach(design.template.slots) { slot in
                    Picker(slot.name, selection: Binding(get: { design.complication(slot.id) }, set: { design.slots[slot.id] = $0 })) {
                        ForEach(FaceComplication.options(for: slot.kind)) { Text($0.name).tag($0) }
                    }
                }
            } header: {
                Text("Datos")
            } footer: {
                Text(dataFooter)
            }
            Section {
                Toggle("Empezar en modo noche", isOn: $design.startsInNightMode)
            } footer: {
                Text("En el reloj, gira la corona hacia arriba para ponerlo y hacia abajo para quitarlo, como en el Ultra.")
            }
            if !isNew, onDelete != nil {
                Section {
                    Button("Borrar esfera", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .navigationTitle(isNew ? "Nueva esfera" : "Editar esfera")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Añadir" : "Guardar") {
                    var d = design.normalized()
                    d.updatedAt = Date()
                    onSave(d)
                    dismiss()
                }
            }
        }
        .confirmationDialog("¿Borrar esta esfera?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Borrar", role: .destructive) {
                onDelete?()
                dismiss()
            }
        }
        .onAppear { night = design.startsInNightMode }
    }

    private var dataFooter: String {
        var parts: [String] = []
        if design.normalized().needsHealth { parts.append("El pulso, los pasos y los anillos los mide el reloj: te pedirá permiso para leerlos de Salud.") }
        if design.normalized().needsLocation { parts.append("La brújula y el tiempo usan la ubicación del reloj en el momento (no se guarda).") }
        parts.append("Lo demás (recuperación, carga, sueño, tu plan) lo manda el iPhone.")
        return parts.joined(separator: " ")
    }

    private func setAccent(_ color: FaceColor) {
        design.accent = color
        switch design.background {
        case .solid: design.background = .solid(color)
        case .glow: design.background = .glow(color)
        case .black: break
        }
    }

    private func setBackground(_ choice: BackgroundChoice) {
        switch choice {
        case .black: design.background = .black
        case .solid: design.background = .solid(design.accent)
        case .glow: design.background = .glow(design.accent)
        }
    }
}

enum BackgroundChoice: String, CaseIterable, Identifiable {
    case black, solid, glow

    init(_ background: FaceBackground) {
        switch background {
        case .black: self = .black
        case .solid: self = .solid
        case .glow: self = .glow
        }
    }

    var id: String { rawValue }

    var name: String {
        switch self {
        case .black: return "Negro"
        case .solid: return "Color"
        case .glow: return "Halo"
        }
    }
}

extension FaceColor {
    init(uiColor: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(Double(r), Double(g), Double(b))
    }
}

// MARK: - Vista previa con forma de reloj

/// La esfera dentro de una caja de Apple Watch (45 mm), para la galería y el editor.
struct WatchPreview: View {
    let design: FaceDesign
    let data: FaceData
    var night = false
    /// Segundo a segundo (el editor); en la galería, al minuto.
    var live = false

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let width = height * 0.8
            let screenW = width * 0.86, screenH = screenW * 242 / 198
            ZStack {
                RoundedRectangle(cornerRadius: width * 0.3, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.32), Color(white: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: width * 0.27, style: .continuous)
                    .fill(Color.black)
                    .padding(width * 0.035)
                TimelineView(.periodic(from: .now, by: live ? 1 : 60)) { context in
                    FaceView(design: design, data: data, date: context.date, night: night)
                }
                .frame(width: screenW, height: screenH)
                .clipShape(RoundedRectangle(cornerRadius: screenW * 0.22, style: .continuous))
            }
            .frame(width: width, height: height * 0.97)
            .overlay(alignment: .trailing) {
                Capsule().fill(LinearGradient(colors: [Color(white: 0.45), Color(white: 0.18)], startPoint: .top, endPoint: .bottom))
                    .frame(width: width * 0.05, height: height * 0.15)
                    .offset(x: width * 0.035, y: -height * 0.13)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vista previa de la esfera \(design.name)")
    }
}
