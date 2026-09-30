import SwiftUI
import FaceKit

/// Tus esferas a pantalla completa: deslizando pasas de una a otra y girando la corona pones el modo noche (todo en rojo,
/// como en el Ultra). Con la muñeca bajada se ven atenuadas y sin segundero.
struct FacesPager: View {
    @State private var store = FaceStore.shared
    @State private var selection = ""
    @State private var crown = 0.0
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.scenePhase) private var phase

    private var designs: [FaceDesign] { WatchScreenshot.isActive ? WatchScreenshot.designs : store.designs }
    private var current: FaceDesign? { designs.first { $0.id == selection } ?? designs.first }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(designs) { design in
                FaceScreen(design: design, data: WatchScreenshot.isActive ? WatchScreenshot.data : store.data,
                           night: WatchScreenshot.isActive ? WatchScreenshot.night : store.isNight(design), dimmed: dimmed)
                    .tag(design.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        .focusable()
        .digitalCrownRotation($crown, from: 0, through: 1, by: 1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: crown) { _, value in
            guard let current else { return }
            store.night[current.id] = value > 0.5
        }
        .onChange(of: selection) { _, _ in
            crown = current.map { store.isNight($0) ? 1 : 0 } ?? 0
        }
        .onAppear {
            if selection.isEmpty || !designs.contains(where: { $0.id == selection }) { selection = designs.first?.id ?? "" }
            crown = current.map { store.isNight($0) ? 1 : 0 } ?? 0
        }
        .task(id: phase) {
            guard !WatchScreenshot.isActive else { return }
            guard phase == .active else {
                WatchSensors.shared.pause()
                return
            }
            while !Task.isCancelled {
                await WatchSensors.shared.refresh(designs: store.designs)
                try? await Task.sleep(for: .seconds(60))
            }
        }
        ._statusBarHidden(true)
    }
}

/// Una esfera: se redibuja cada segundo (cada minuto con la pantalla atenuada).
struct FaceScreen: View {
    let design: FaceDesign
    let data: FaceData
    let night: Bool
    let dimmed: Bool

    var body: some View {
        if WatchScreenshot.isActive {
            FaceView(design: design, data: data, date: WatchScreenshot.date, night: night, calendar: WatchScreenshot.calendar)
                .ignoresSafeArea()
        } else {
            TimelineView(.periodic(from: .now, by: dimmed ? 60 : 1)) { context in
                FaceView(design: design, data: data, date: context.date, night: night, dimmed: dimmed)
            }
            .ignoresSafeArea()
        }
    }
}

/// Capturas en el simulador (`scripts/screenshots.sh`): una plantilla con datos de ejemplo a las 10:09:30.
enum WatchScreenshot {
    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains("-RecuperaScreenshots") }
    static var night: Bool { ProcessInfo.processInfo.arguments.contains("-RecuperaNight") }

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Madrid") ?? .current
        return c
    }

    static var date: Date { ISO8601DateFormatter().date(from: "2026-09-30T08:09:30Z") ?? Date() }
    static var data: FaceData { .demo(now: date) }

    static var designs: [FaceDesign] {
        let all = FaceLibrary.starter(now: date).designs
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-RecuperaFace"), i + 1 < args.count,
              let template = FaceTemplate(rawValue: args[i + 1]) else { return all }
        return all.filter { $0.template == template }
    }
}
