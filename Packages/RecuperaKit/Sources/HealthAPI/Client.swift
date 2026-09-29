import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Tipos de datos que lee la app (doc. 03 §4).
public enum HealthDataType: String, CaseIterable, Sendable {
    case heartRate = "heart-rate"
    case dailyRestingHeartRate = "daily-resting-heart-rate"
    case dailyHeartRateVariability = "daily-heart-rate-variability"
    case dailyOxygenSaturation = "daily-oxygen-saturation"
    case dailyRespiratoryRate = "daily-respiratory-rate"
    case dailySleepTemperatureDerivations = "daily-sleep-temperature-derivations"
    case sleep
    case exercise
    case steps
    case distance
    case totalCalories = "total-calories"
    case dailyVo2Max = "daily-vo2-max"
    case runVo2Max = "run-vo2-max"

    public enum RecordKind: Sendable { case interval, sample, daily, exercise, sleep }

    /// En los filtros el nombre va en snake_case (en la ruta, en kebab-case).
    public var filterName: String { rawValue.replacingOccurrences(of: "-", with: "_") }

    public var recordKind: RecordKind {
        switch self {
        case .heartRate, .runVo2Max: return .sample
        case .dailyRestingHeartRate, .dailyHeartRateVariability, .dailyOxygenSaturation, .dailyRespiratoryRate,
             .dailySleepTemperatureDerivations, .dailyVo2Max: return .daily
        case .sleep: return .sleep
        case .exercise: return .exercise
        case .steps, .distance, .totalCalories: return .interval
        }
    }
}

public enum DataSourceFamily {
    /// Solo pulseras y relojes de Google y Fitbit: excluye lo importado de Salud (ALG-FUS-08).
    public static let googleWearables = "users/me/dataSourceFamilies/google-wearables"
}

/// Filtros AIP-160 (solo `>=` y `<`, unidos con AND; doc. «Filter data»).
public enum HealthFilter {
    public static func make(_ type: HealthDataType, from: Date, to: Date, utcOffsetSeconds: Int) -> String {
        let n = type.filterName
        switch type.recordKind {
        case .sample:
            return "\(n).sample_time.physical_time >= \"\(GoogleTime.string(from))\" AND \(n).sample_time.physical_time < \"\(GoogleTime.string(to))\""
        case .interval:
            return "\(n).interval.start_time >= \"\(GoogleTime.string(from))\" AND \(n).interval.start_time < \"\(GoogleTime.string(to))\""
        case .daily:
            return "\(n).date >= \"\(civilDate(from, utcOffsetSeconds))\" AND \(n).date < \"\(civilDate(to, utcOffsetSeconds))\""
        case .exercise:
            return "exercise.interval.civil_start_time >= \"\(civil(from, utcOffsetSeconds))\" AND exercise.interval.civil_start_time < \"\(civil(to, utcOffsetSeconds))\""
        case .sleep:
            return "sleep.interval.end_time >= \"\(GoogleTime.string(from))\" AND sleep.interval.end_time < \"\(GoogleTime.string(to))\""
        }
    }

    static func civilDate(_ d: Date, _ offset: Int) -> String { String(civil(d, offset).prefix(10)) }

    static func civil(_ d: Date, _ offset: Int) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: offset)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.string(from: d)
    }
}

/// Cliente de la Google Health API v4 con renovación de *tokens*, reintentos y límite de ritmo.
public actor GoogleHealthClient {
    public static let baseURL = URL(string: "https://health.googleapis.com/v4/users/me/")!

    let config: OAuthConfig
    let transport: HTTPTransport
    let tokens: TokenStore
    let sleep: @Sendable (Double) async -> Void
    private var lastRequest = Date.distantPast
    public private(set) var requestCount = 0
    /// Puntos ilegibles descartados desde que se creó el cliente (se anotan en el registro de sincronización).
    public private(set) var skippedPoints = 0

    public init(config: OAuthConfig, transport: HTTPTransport = URLSessionTransport(), tokens: TokenStore,
                sleep: @escaping @Sendable (Double) async -> Void = { s in try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }) {
        self.config = config
        self.transport = transport
        self.tokens = tokens
        self.sleep = sleep
    }

    // MARK: Conexión

    public func exchange(code: String, pkce: PKCE) async throws -> TokenSet {
        let (data, resp) = try await transport.send(OAuthFlow.exchangeRequest(code: code, config: config, pkce: pkce))
        let t = try OAuthFlow.parseTokenResponse(data, status: resp.statusCode, previousRefreshToken: nil)
        await tokens.save(t)
        return t
    }

    public func isConnected() async -> Bool { await tokens.load() != nil }

    /// Revoca el acceso en Google y borra los *tokens* (RF-CON-03).
    public func disconnect() async {
        if let t = await tokens.load() {
            _ = try? await transport.send(OAuthFlow.revokeRequest(token: t.refreshToken ?? t.accessToken))
        }
        await tokens.clear()
    }

    func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        guard var t = await tokens.load() else { throw HealthAPIError.notConnected }
        if forceRefresh || t.isExpired() {
            guard let refresh = t.refreshToken else { throw HealthAPIError.reauthorizationRequired }
            let (data, resp) = try await transport.send(OAuthFlow.refreshRequest(refreshToken: refresh, config: config))
            t = try OAuthFlow.parseTokenResponse(data, status: resp.statusCode, previousRefreshToken: refresh)
            await tokens.save(t)
        }
        return t.accessToken
    }

    // MARK: Peticiones

    func request(_ path: String, query: [URLQueryItem] = [], body: Data? = nil) async throws -> Data {
        var comps = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        // `+` en la query debe ir codificado para Google.
        comps.percentEncodedQuery = comps.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        var attempt = 0
        var refreshed = false
        while true {
            attempt += 1
            await throttle()
            var req = URLRequest(url: comps.url!)
            req.httpMethod = body == nil ? "GET" : "POST"
            if let body {
                req.httpBody = body
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            req.setValue("Bearer \(try await validAccessToken())", forHTTPHeaderField: "Authorization")
            let data: Data
            let resp: HTTPURLResponse
            do {
                (data, resp) = try await transport.send(req)
            } catch {
                if attempt < 4 { await backoff(attempt, retryAfter: nil); continue }
                throw error
            }
            requestCount += 1
            switch resp.statusCode {
            case 200..<300:
                return data
            case 401 where !refreshed:
                refreshed = true
                _ = try await validAccessToken(forceRefresh: true)
                continue
            case 401:
                throw HealthAPIError.reauthorizationRequired
            case 412:
                throw HealthAPIError.noHealthProfile
            case 429, 500..<600:
                let retryAfter = (resp.value(forHTTPHeaderField: "Retry-After")).flatMap(Double.init)
                if attempt < 4 { await backoff(attempt, retryAfter: retryAfter); continue }
                if resp.statusCode == 429 { throw HealthAPIError.rateLimited(retryAfter: retryAfter) }
                throw HealthAPIError.http(status: resp.statusCode, message: Self.errorMessage(data))
            default:
                throw HealthAPIError.http(status: resp.statusCode, message: Self.errorMessage(data))
            }
        }
    }

    /// ≤ 4 peticiones por segundo (RNF-DIS-04).
    func throttle() async {
        let wait = 0.25 - Date().timeIntervalSince(lastRequest)
        if wait > 0 { await sleep(wait) }
        lastRequest = Date()
    }

    func backoff(_ attempt: Int, retryAfter: Double?) async {
        let base = retryAfter ?? pow(2, Double(attempt - 1))
        await sleep(min(30, base + Double.random(in: 0...0.5)))
    }

    static func errorMessage(_ data: Data) -> String? {
        struct Wrapper: Decodable { struct E: Decodable { var message: String?; var status: String? }; var error: E? }
        let w = try? JSONDecoder().decode(Wrapper.self, from: data)
        return w?.error?.message ?? w?.error?.status
    }

    func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) } catch {
            throw HealthAPIError.decoding(String(describing: error).prefix(200).description)
        }
    }

    // MARK: Perfil y dispositivos

    public func identity() async throws -> Identity { try decode(Identity.self, await request("identity")) }
    public func settings() async throws -> UserSettings { try decode(UserSettings.self, await request("settings")) }
    public func profile() async throws -> UserProfileAPI { try decode(UserProfileAPI.self, await request("profile")) }

    public func pairedDevices() async throws -> [PairedDevice] {
        try decode(PairedDevicesResponse.self, await request("pairedDevices")).pairedDevices ?? []
    }

    // MARK: Datos

    public func list(_ type: HealthDataType, filter: String, pageSize: Int = 1000, maxPages: Int = 50) async throws -> [APIDataPoint] {
        var out: [APIDataPoint] = []
        var token: String?
        var pages = 0
        repeat {
            var q = [URLQueryItem(name: "filter", value: filter), URLQueryItem(name: "pageSize", value: String(pageSize))]
            if let token { q.append(URLQueryItem(name: "pageToken", value: token)) }
            let r = try decode(ListDataPointsResponse.self, await request("dataTypes/\(type.rawValue)/dataPoints", query: q))
            out += r.dataPoints ?? []
            skippedPoints += r.skipped
            token = r.nextPageToken?.isEmpty == false ? r.nextPageToken : nil
            pages += 1
        } while token != nil && pages < maxPages
        return out
    }

    public func reconcile(_ type: HealthDataType, filter: String, family: String = DataSourceFamily.googleWearables,
                          pageSize: Int = 1000, maxPages: Int = 50) async throws -> [APIDataPoint] {
        var out: [APIDataPoint] = []
        var token: String?
        var pages = 0
        repeat {
            var q = [URLQueryItem(name: "filter", value: filter), URLQueryItem(name: "dataSourceFamily", value: family),
                     URLQueryItem(name: "pageSize", value: String(pageSize))]
            if let token { q.append(URLQueryItem(name: "pageToken", value: token)) }
            let r = try decode(ListDataPointsResponse.self, await request("dataTypes/\(type.rawValue)/dataPoints:reconcile", query: q))
            out += r.dataPoints ?? []
            skippedPoints += r.skipped
            token = r.nextPageToken?.isEmpty == false ? r.nextPageToken : nil
            pages += 1
        } while token != nil && pages < maxPages
        return out
    }

    /// `rollUp` por ventanas (FC por minuto, pasos y distancia por minuto). Divide en tramos de ≤ 14 días.
    public func rollUp(_ type: HealthDataType, from: Date, to: Date, windowSeconds: Int = 60,
                       family: String = DataSourceFamily.googleWearables) async throws -> [RollupDataPoint] {
        var out: [RollupDataPoint] = []
        var start = from
        let chunk: TimeInterval = 14 * 86_400
        while start < to {
            let end = min(to, start.addingTimeInterval(chunk))
            var token: String?
            repeat {
                var body: [String: Any] = [
                    "range": ["startTime": GoogleTime.string(start), "endTime": GoogleTime.string(end)],
                    "windowSize": "\(windowSeconds)s", "pageSize": 10_000, "dataSourceFamily": family,
                ]
                if let token { body["pageToken"] = token }
                let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
                let r = try decode(RollUpResponse.self, await request("dataTypes/\(type.rawValue)/dataPoints:rollUp", body: data))
                out += r.rollupDataPoints ?? []
                skippedPoints += r.skipped
                token = r.nextPageToken?.isEmpty == false ? r.nextPageToken : nil
            } while token != nil
            start = end
        }
        return out
    }

    /// Totales diarios (pasos, distancia, calorías) por fecha civil.
    public func dailyRollUp(_ type: HealthDataType, from: (year: Int, month: Int, day: Int), to: (year: Int, month: Int, day: Int),
                            family: String = DataSourceFamily.googleWearables) async throws -> [RollupDataPoint] {
        let body: [String: Any] = [
            "range": ["start": ["date": ["year": from.year, "month": from.month, "day": from.day]],
                      "end": ["date": ["year": to.year, "month": to.month, "day": to.day]]],
            "windowSizeDays": 1, "pageSize": 1000, "dataSourceFamily": family,
        ]
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let r = try decode(RollUpResponse.self, await request("dataTypes/\(type.rawValue)/dataPoints:dailyRollUp", body: data))
        skippedPoints += r.skipped
        return r.rollupDataPoints ?? []
    }
}
