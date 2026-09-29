import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import HealthAPI

/// Transporte simulado: responde según la ruta y registra las peticiones.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    var handler: (URLRequest) -> (Int, String, [String: String])
    var requests: [URLRequest] = []
    let lock = NSLock()

    init(_ handler: @escaping (URLRequest) -> (Int, String, [String: String])) { self.handler = handler }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { requests.append(request) }
        let (status, body, headers) = handler(request)
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        return (Data(body.utf8), resp)
    }
}

@Suite struct OAuthTests {
    @Test func sha256KnownVector() {
        let h = SHA256.hash(Array("abc".utf8)).map { String(format: "%02x", $0) }.joined()
        #expect(h == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let empty = SHA256.hash([]).map { String(format: "%02x", $0) }.joined()
        #expect(empty == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    /// Vector del RFC 7636, apéndice B.
    @Test func pkceChallengeRFCVector() {
        #expect(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func authorizationURL() {
        let config = OAuthConfig(clientID: "123-abc.apps.googleusercontent.com", reversedClientID: "com.googleusercontent.apps.123-abc")
        let pkce = PKCE(verifier: "v" + String(repeating: "x", count: 50), state: "st")
        let url = OAuthFlow.authorizationURL(config: config, pkce: pkce)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(items.first { $0.name == "redirect_uri" }?.value == "com.googleusercontent.apps.123-abc:/oauth2redirect")
        #expect(items.first { $0.name == "code_challenge_method" }?.value == "S256")
        #expect(items.first { $0.name == "scope" }?.value?.contains("googlehealth.sleep.readonly") == true)
        let code = try? OAuthFlow.code(fromCallback: URL(string: "com.googleusercontent.apps.123-abc:/oauth2redirect?state=st&code=4/abc")!, expectedState: "st")
        #expect(code == "4/abc")
        #expect(throws: HealthAPIError.stateMismatch) {
            try OAuthFlow.code(fromCallback: URL(string: "x:/cb?state=zz&code=1")!, expectedState: "st")
        }
    }

    @Test func invalidGrantRequiresReauthorization() {
        #expect(throws: HealthAPIError.reauthorizationRequired) {
            try OAuthFlow.parseTokenResponse(Data(#"{"error":"invalid_grant"}"#.utf8), status: 400, previousRefreshToken: "r")
        }
    }
}

@Suite struct ClientTests {
    let config = OAuthConfig(clientID: "c", reversedClientID: "r")

    @Test func filters() {
        let from = Date(timeIntervalSince1970: 1_790_000_000)
        let to = from.addingTimeInterval(86_400)
        #expect(HealthFilter.make(.heartRate, from: from, to: to, utcOffsetSeconds: 0).hasPrefix("heart_rate.sample_time.physical_time >= \""))
        #expect(HealthFilter.make(.dailyHeartRateVariability, from: from, to: to, utcOffsetSeconds: 7200).contains("daily_heart_rate_variability.date >= \"2026-"))
        #expect(HealthFilter.make(.sleep, from: from, to: to, utcOffsetSeconds: 0).hasPrefix("sleep.interval.end_time >= "))
        #expect(HealthFilter.make(.exercise, from: from, to: to, utcOffsetSeconds: 0).hasPrefix("exercise.interval.civil_start_time >= "))
        #expect(HealthFilter.make(.steps, from: from, to: to, utcOffsetSeconds: 0).hasPrefix("steps.interval.start_time >= "))
    }

    @Test func refreshesOn401AndRetriesOn429() async throws {
        var calls = 0
        let t = MockTransport { req in
            let path = req.url!.path
            if path.contains("token") { return (200, #"{"access_token":"new","expires_in":3600}"#, [:]) }
            calls += 1
            if calls == 1 { return (401, "{}", [:]) }
            if calls == 2 { return (429, "{}", ["Retry-After": "0"]) }
            return (200, #"{"healthUserId":"u1"}"#, [:])
        }
        let store = InMemoryTokenStore(TokenSet(accessToken: "old", refreshToken: "rt", expiresAt: .distantFuture, scope: nil))
        let client = GoogleHealthClient(config: config, transport: t, tokens: store, sleep: { _ in })
        let id = try await client.identity()
        #expect(id.healthUserId == "u1")
        #expect(await store.load()?.accessToken == "new")
        #expect(await store.load()?.refreshToken == "rt")
    }

    @Test func http412MeansNoHealthProfile() async {
        let t = MockTransport { _ in (412, #"{"error":{"message":"no profile"}}"#, [:]) }
        let client = GoogleHealthClient(config: config, transport: t,
                                        tokens: InMemoryTokenStore(TokenSet(accessToken: "a", refreshToken: nil, expiresAt: .distantFuture, scope: nil)),
                                        sleep: { _ in })
        await #expect(throws: HealthAPIError.noHealthProfile) { try await client.identity() }
    }

    @Test func decodesDataPointsAndPaginates() async throws {
        let page1 = """
        {"dataPoints":[{"name":"users/me/dataTypes/sleep/dataPoints/1","dataSource":{"platform":"FITBIT","device":{"formFactor":"FITNESS_BAND","displayName":"Fitbit Air"}},
         "sleep":{"interval":{"startTime":"2026-09-27T21:10:00Z","endTime":"2026-09-28T05:02:30.123Z","startUtcOffset":"7200s","endUtcOffset":"7200s"},
          "metadata":{"mainSleep":true,"nap":false},"summary":{"minutesAsleep":"431","minutesAwake":"41"},
          "stages":[{"type":"LIGHT","startTime":"2026-09-27T21:10:00Z","endTime":"2026-09-27T22:00:00Z"},{"type":"DEEP","startTime":"2026-09-27T22:00:00Z","endTime":"2026-09-27T22:40:00Z"}]}}],
         "nextPageToken":"p2"}
        """
        let page2 = """
        {"dataPoints":[{"dailyHeartRateVariability":{"date":{"year":2026,"month":9,"day":28},"averageHeartRateVariabilityMilliseconds":48.2,"deepSleepRootMeanSquareOfSuccessiveDifferencesMilliseconds":55.1,"nonRemHeartRateBeatsPerMinute":"51"}}]}
        """
        let t = MockTransport { req in
            req.url!.query!.contains("pageToken=p2") ? (200, page2, [:]) : (200, page1, [:])
        }
        let client = GoogleHealthClient(config: config, transport: t,
                                        tokens: InMemoryTokenStore(TokenSet(accessToken: "a", refreshToken: nil, expiresAt: .distantFuture, scope: nil)),
                                        sleep: { _ in })
        let points = try await client.list(.sleep, filter: "x")
        #expect(points.count == 2)
        let s = points[0].sleep!
        #expect(s.summary?.minutesAsleep?.value == 431)
        #expect(GoogleTime.date(s.interval?.endTime) != nil)
        #expect(GoogleTime.seconds(s.interval?.startUtcOffset) == 7200)
        #expect(points[1].dailyHeartRateVariability?.nonRemHeartRateBeatsPerMinute?.value == 51)
        #expect(points[0].dataSource?.platform == "FITBIT")
    }

    @Test func rollUpBodyUsesGoogleWearables() async throws {
        let t = MockTransport { _ in
            (200, #"{"rollupDataPoints":[{"startTime":"2026-09-28T10:00:00Z","endTime":"2026-09-28T10:01:00Z","heartRate":{"beatsPerMinuteAvg":72.5,"beatsPerMinuteMin":70,"beatsPerMinuteMax":75}}]}"#, [:])
        }
        let client = GoogleHealthClient(config: config, transport: t,
                                        tokens: InMemoryTokenStore(TokenSet(accessToken: "a", refreshToken: nil, expiresAt: .distantFuture, scope: nil)),
                                        sleep: { _ in })
        let from = Date(timeIntervalSince1970: 1_790_000_000)
        let r = try await client.rollUp(.heartRate, from: from, to: from.addingTimeInterval(3600))
        #expect(r.first?.heartRate?.beatsPerMinuteAvg == 72.5)
        let body = String(data: t.requests.last!.httpBody!, encoding: .utf8)!
        #expect(body.contains("google-wearables") && body.contains("\"windowSize\":\"60s\""))
        #expect(t.requests.last!.url!.path.hasSuffix("heart-rate/dataPoints:rollUp"))
    }
}
