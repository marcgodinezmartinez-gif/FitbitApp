import AuthenticationServices
import UIKit
import HealthAPI

/// Consentimiento de Google en el navegador del sistema con PKCE (doc. 10 §4). No se usa ningún *web view* propio.
@MainActor
final class GoogleAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func authorize(config: OAuthConfig) async throws -> (code: String, pkce: PKCE) {
        let pkce = PKCE()
        let url = OAuthFlow.authorizationURL(config: config, pkce: pkce)
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            // La continuación solo puede reanudarse una vez aunque lleguen el error de `start()` y el del manejador.
            let once = ResumeOnce()
            let s = ASWebAuthenticationSession(url: url, callback: .customScheme(config.callbackScheme)) { url, error in
                guard once.claim() else { return }
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: HealthAPIError.authorizationDenied("cancelado"))
                } else {
                    continuation.resume(throwing: HealthAPIError.authorizationDenied(error?.localizedDescription ?? "sin respuesta"))
                }
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = false
            self.session = s
            if !s.start(), once.claim() {
                continuation.resume(throwing: HealthAPIError.authorizationDenied("no se pudo abrir el navegador"))
            }
        }
        session = nil
        let code = try OAuthFlow.code(fromCallback: callback, expectedState: pkce.state)
        return (code, pkce)
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return window }
            if let scene = scenes.first { return UIWindow(windowScene: scene) }
            return ASPresentationAnchor()
        }
    }
}

/// Marca de «ya se reanudó» compartida entre el manejador de la sesión y `start()`.
final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    /// Devuelve `true` solo la primera vez.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
