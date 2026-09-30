import Foundation
import WatchConnectivity
import FaceKit

/// Recibe del iPhone tus esferas y los datos del día (contexto de la app: siempre lo último).
final class PhoneLink: NSObject, WCSessionDelegate {
    static let shared = PhoneLink()

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        handle(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handle(applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handle(userInfo)
    }

    private func handle(_ dictionary: [String: Any]) {
        guard let raw = dictionary[WatchPayload.key] as? Data, let payload = WatchPayload.decode(raw) else { return }
        Task { @MainActor in FaceStore.shared.receive(payload, raw: raw) }
    }
}
