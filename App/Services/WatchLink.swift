import Foundation
import Observation
import WatchConnectivity
import FaceKit
import MetricsKit
import Store
import Insights
import RunKit

/// Manda al Apple Watch tus esferas y los datos del día (doc. 19 §3). Va en el contexto de la app de WatchConnectivity,
/// que guarda solo lo último y llega al reloj en cuanto puede; si hay una complicación de Recupera en la esfera, además
/// se despierta al reloj para que la actualice.
@MainActor
@Observable
final class WatchLink: NSObject, WCSessionDelegate {
    static let shared = WatchLink()
    static let libraryKey = "watch_faces"

    /// Reloj emparejado y con la app de Recupera instalada.
    private(set) var isReady = false
    private(set) var isPaired = false
    private(set) var lastSentAt: Date?
    @ObservationIgnored private var lastData: Data?
    @ObservationIgnored private var pending: (() -> Void)?

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: Tus esferas (en la BD del iPhone)

    struct FacesState: Codable {
        var library: FaceLibrary?
    }

    static func library(db: AppDatabase?) -> FaceLibrary {
        guard let db, let saved = (try? db.readState(libraryKey, default: FacesState()))?.library else { return FaceLibrary.starter() }
        return saved
    }

    static func save(_ library: FaceLibrary, db: AppDatabase?) {
        try? db?.writeState(libraryKey, FacesState(library: library))
    }

    // MARK: Envío

    /// Manda tus esferas y los datos de ahora (si el reloj está listo; si no, en cuanto lo esté).
    func push(model: AppModel) {
        let library = Self.library(db: model.db)
        let data = Self.faceData(model: model)
        send(library: library, data: data)
    }

    func send(library: FaceLibrary, data: FaceData) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            pending = { [weak self] in self?.send(library: library, data: data) }
            return
        }
        guard session.isPaired, session.isWatchAppInstalled else { return }
        let payload = WatchPayload(library: library, data: data, sentAt: Date())
        guard let raw = try? payload.encoded() else { return }
        try? session.updateApplicationContext([WatchPayload.key: raw])
        lastSentAt = payload.sentAt
        // Solo si cambian los datos (no la hora de envío): el reloj tiene un cupo de despertares al día.
        let dataOnly = try? WatchPayload(library: library, data: data, sentAt: Date(timeIntervalSince1970: 0)).encoded()
        if dataOnly != lastData, session.isComplicationEnabled, session.remainingComplicationUserInfoTransfers > 0 {
            session.transferCurrentComplicationUserInfo([WatchPayload.key: raw])
        }
        lastData = dataOnly
    }

    /// Lo que enseñan las esferas y calcula el iPhone: recuperación, carga, sueño, variabilidad, reposo, hora de
    /// acostarte, el entreno de hoy y tu carrera objetivo.
    static func faceData(model: AppModel) -> FaceData {
        var d = FaceData(updatedAt: Date())
        if let cur = model.output?.current {
            d.recovery = cur.recovery.score
            d.recoveryZone = cur.recovery.zone?.rawValue
            d.strain = cur.strain.strain
            d.strainTargetLow = cur.target?.low
            d.strainTargetHigh = cur.target?.high
            d.sleepPerformance = cur.sleep.map { Int($0.performance.rounded()) }
            d.sleepMinutes = cur.sleep.map { Int($0.asleepMin.rounded()) }
            d.hrv = cur.night?.lnRmssd.map { exp($0) }
            d.restingHR = cur.night?.restingHR
        }
        if let bed = model.tonightBedtimeMinutes { d.bedtime = Format.clock(minutes: bed) }
        // El plan y la carrera: los de la pestaña Correr si ya se han cargado; si no, los guardados.
        let runs = model.runs
        let plan = runs.plan ?? model.db.flatMap { try? $0.readState(RunsModel.planKey, default: RunsModel.PlanState()) }?.plan
        let goal = runs.goal ?? model.db.flatMap { try? $0.readState(RunsModel.goalKey, default: RunsModel.GoalState()) }?.race
        if let plan, let session = plan.sessions(on: runs.today).first {
            var done = false
            if case .done = runs.status(of: session) { done = true }
            let w = session.workout
            d.workout = FaceWorkout(title: w.title,
                                    detail: RunFormat.distance(w.estimatedMeters) + " · " + Format.duration(minutes: w.estimatedSeconds / 60),
                                    symbol: w.kind.symbol, done: done)
        }
        if let goal, goal.date > Date().addingTimeInterval(-86_400) {
            d.race = FaceRace(name: goal.name, date: goal.date, distanceText: RunFormat.distance(goal.distanceM))
        }
        return d
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let paired = session.isPaired, installed = session.isWatchAppInstalled
        Task { @MainActor in
            self.isPaired = paired
            self.isReady = paired && installed
            let action = self.pending
            self.pending = nil
            action?()
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        let paired = session.isPaired, installed = session.isWatchAppInstalled
        Task { @MainActor in
            self.isPaired = paired
            self.isReady = paired && installed
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Al cambiar de reloj: se vuelve a activar con el nuevo.
        WCSession.default.activate()
    }
}
