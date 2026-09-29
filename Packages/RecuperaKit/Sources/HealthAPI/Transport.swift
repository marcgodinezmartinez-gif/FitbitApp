import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum HealthAPIError: Error, Equatable, Sendable, LocalizedError {
    case notConfigured
    case notConnected
    case authorizationDenied(String)
    case stateMismatch
    case reauthorizationRequired
    case noHealthProfile                 // HTTP 412 (RF-CON-08)
    case rateLimited(retryAfter: Double?)
    case http(status: Int, message: String?)
    case decoding(String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "Falta configurar el cliente OAuth de Google en la app."
        case .notConnected: return "Google Health no está conectado."
        case .authorizationDenied(let r): return "No se concedió el acceso a Google Health (\(r))."
        case .stateMismatch: return "La respuesta de inicio de sesión no es válida."
        case .reauthorizationRequired: return "Vuelve a conectar Google Health para seguir recibiendo datos."
        case .noHealthProfile: return "Configura primero tu perfil en la app Google Health."
        case .rateLimited: return "Google ha limitado temporalmente las peticiones. Se reintentará."
        case .http(let s, let m): return "Error \(s) de Google Health\(m.map { ": \($0)" } ?? "")."
        case .decoding(let m): return "Respuesta inesperada de Google Health (\(m))."
        case .network(let m): return "Sin conexión con Google Health (\(m))."
        }
    }
}

/// Transporte HTTP inyectable (URLSession en la app; simulado en los tests).
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { cont in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    cont.resume(throwing: HealthAPIError.network(error.localizedDescription))
                } else if let http = response as? HTTPURLResponse {
                    cont.resume(returning: (data ?? Data(), http))
                } else {
                    cont.resume(throwing: HealthAPIError.network("respuesta no HTTP"))
                }
            }
            task.resume()
        }
    }
}
