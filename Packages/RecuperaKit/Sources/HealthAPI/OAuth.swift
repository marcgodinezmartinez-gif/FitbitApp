import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Ámbitos de solo lectura que usa la app (doc. 10 §3). Todos son restringidos.
public enum HealthScope {
    public static let prefix = "https://www.googleapis.com/auth/googlehealth."
    public static let healthMetrics = prefix + "health_metrics_and_measurements.readonly"
    public static let sleep = prefix + "sleep.readonly"
    public static let activity = prefix + "activity_and_fitness.readonly"
    public static let profile = prefix + "profile.readonly"
    public static let settings = prefix + "settings.readonly"
    public static let all = [healthMetrics, sleep, activity, profile, settings]
}

/// Configuración del cliente OAuth de tipo iOS (sin secreto de cliente).
public struct OAuthConfig: Sendable, Hashable {
    public var clientID: String
    public var reversedClientID: String
    public var scopes: [String]

    public init(clientID: String, reversedClientID: String, scopes: [String] = HealthScope.all) {
        self.clientID = clientID
        self.reversedClientID = reversedClientID
        self.scopes = scopes
    }

    public var redirectURI: String { "\(reversedClientID):/oauth2redirect" }
    public var callbackScheme: String { reversedClientID }
    public var isConfigured: Bool { !clientID.isEmpty && !reversedClientID.isEmpty && !clientID.hasPrefix("$(") }

    public static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    public static let revocationEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!
}

/// Reto PKCE (RFC 7636, método S256).
public struct PKCE: Sendable, Hashable {
    public var verifier: String
    public var challenge: String
    public var state: String

    public init(verifier: String? = nil, state: String? = nil) {
        let v = verifier ?? PKCE.randomString(length: 64)
        self.verifier = v
        self.challenge = PKCE.challenge(for: v)
        self.state = state ?? PKCE.randomString(length: 24)
    }

    public static func challenge(for verifier: String) -> String {
        base64URL(SHA256.hash(Array(verifier.utf8)))
    }

    static func randomString(length: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var rng = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in chars[Int(rng.next() % UInt64(chars.count))] })
    }

    static func base64URL(_ bytes: [UInt8]) -> String {
        Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public struct TokenSet: Codable, Sendable, Hashable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date
    public var scope: String?

    public init(accessToken: String, refreshToken: String?, expiresAt: Date, scope: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scope = scope
    }

    public var grantedScopes: [String] { scope?.split(separator: " ").map(String.init) ?? [] }

    public func isExpired(at now: Date = Date(), margin: TimeInterval = 60) -> Bool { now.addingTimeInterval(margin) >= expiresAt }
}

/// Dónde se guardan los *tokens* (el Llavero en la app; memoria en los tests).
public protocol TokenStore: Sendable {
    func load() async -> TokenSet?
    func save(_ tokens: TokenSet) async
    func clear() async
}

public actor InMemoryTokenStore: TokenStore {
    private var tokens: TokenSet?
    public init(_ tokens: TokenSet? = nil) { self.tokens = tokens }
    public func load() async -> TokenSet? { tokens }
    public func save(_ tokens: TokenSet) async { self.tokens = tokens }
    public func clear() async { tokens = nil }
}

public enum OAuthFlow {
    /// URL de autorización para `ASWebAuthenticationSession` (navegador del sistema, nunca WebView).
    public static func authorizationURL(config: OAuthConfig, pkce: PKCE, loginHint: String? = nil) -> URL {
        var c = URLComponents(url: OAuthConfig.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: pkce.state),
            URLQueryItem(name: "include_granted_scopes", value: "true"),
            URLQueryItem(name: "access_type", value: "offline"),
        ]
        if let loginHint { items.append(URLQueryItem(name: "login_hint", value: loginHint)) }
        c.queryItems = items
        return c.url!
    }

    /// Extrae el código de la URL de vuelta y comprueba el `state`.
    public static func code(fromCallback url: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let err = items.first(where: { $0.name == "error" })?.value { throw HealthAPIError.authorizationDenied(err) }
        guard items.first(where: { $0.name == "state" })?.value == expectedState else { throw HealthAPIError.stateMismatch }
        guard let code = items.first(where: { $0.name == "code" })?.value else { throw HealthAPIError.authorizationDenied("sin código") }
        return code
    }

    public static func exchangeRequest(code: String, config: OAuthConfig, pkce: PKCE) -> URLRequest {
        formRequest(OAuthConfig.tokenEndpoint, [
            "client_id": config.clientID, "code": code, "code_verifier": pkce.verifier,
            "grant_type": "authorization_code", "redirect_uri": config.redirectURI,
        ])
    }

    public static func refreshRequest(refreshToken: String, config: OAuthConfig) -> URLRequest {
        formRequest(OAuthConfig.tokenEndpoint, ["client_id": config.clientID, "grant_type": "refresh_token", "refresh_token": refreshToken])
    }

    public static func revokeRequest(token: String) -> URLRequest {
        formRequest(OAuthConfig.revocationEndpoint, ["token": token])
    }

    static func formRequest(_ url: URL, _ fields: [String: String]) -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        r.httpBody = fields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&").data(using: .utf8)
        return r
    }

    struct TokenResponse: Decodable {
        var access_token: String
        var expires_in: Double?
        var refresh_token: String?
        var scope: String?
    }

    struct TokenError: Decodable {
        var error: String
        var error_description: String?
    }

    public static func parseTokenResponse(_ data: Data, status: Int, previousRefreshToken: String?, now: Date = Date()) throws -> TokenSet {
        if !(200..<300).contains(status) {
            let err = try? JSONDecoder().decode(TokenError.self, from: data)
            if err?.error == "invalid_grant" { throw HealthAPIError.reauthorizationRequired }
            throw HealthAPIError.http(status: status, message: err?.error_description ?? err?.error)
        }
        let t = try JSONDecoder().decode(TokenResponse.self, from: data)
        return TokenSet(accessToken: t.access_token, refreshToken: t.refresh_token ?? previousRefreshToken,
                        expiresAt: now.addingTimeInterval(t.expires_in ?? 3600), scope: t.scope)
    }
}
