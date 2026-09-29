import ActivityKit
import Foundation
import Observation
import MetricsKit

/// Entrenamiento en curso iniciado en la app, con su Live Activity (RF-WID-03). Sobrevive a cerrar la app.
@MainActor
@Observable
final class LiveWorkout {
    struct Session: Codable, Equatable {
        var kind: ActivityKind
        var start: Date
    }

    /// Entrenamiento terminado, pendiente de guardar con su RPE.
    struct Finished: Identifiable, Equatable {
        var kind: ActivityKind
        var start: Date
        var end: Date
        var id: Date { start }
        var minutes: Double { end.timeIntervalSince(start) / 60 }
    }

    private(set) var session: Session?
    private static let storageKey = "recupera.liveWorkout"
    /// En las capturas automáticas no se guarda nada entre lanzamientos.
    private let ephemeral = ProcessInfo.processInfo.arguments.contains("-RecuperaScreenshots")

    init() {
        if !ephemeral, let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(Session.self, from: data) {
            session = saved
        }
    }

    var isRunning: Bool { session != nil }

    func start(kind: ActivityKind, dayStrain: Double?, target: TargetBand?) {
        let s = Session(kind: kind, start: Date())
        session = s
        persist()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = WorkoutActivityAttributes(kindName: kind.displayName, symbolName: kind.symbolName)
        let state = WorkoutActivityAttributes.ContentState(startedAt: s.start, dayStrain: dayStrain, targetLow: target?.low,
                                                           targetHigh: target?.high)
        _ = try? Activity<WorkoutActivityAttributes>.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil),
                                                             pushType: nil)
    }

    /// Para el cronómetro y cierra la Live Activity. Devuelve el entrenamiento para guardarlo.
    func finish() async -> Finished? {
        guard let s = session else { return nil }
        let end = Date()
        session = nil
        persist()
        await endActivities()
        return Finished(kind: s.kind, start: s.start, end: end)
    }

    /// Descarta el entrenamiento en curso.
    func discard() async {
        session = nil
        persist()
        await endActivities()
    }

    private func endActivities() async {
        for activity in Activity<WorkoutActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func persist() {
        guard !ephemeral else { return }
        if let session, let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.storageKey)
        }
    }
}
