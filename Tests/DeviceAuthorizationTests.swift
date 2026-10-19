import XCTest
@testable import FiestaBoardTV

final class DeviceAuthorizationTests: XCTestCase {
    override func setUp() { StubURLProtocol.reset() }
    private let host = URL(string: "https://board.example:4420/fiesta")!
    static let token = #"{"access_token":"fb_tv_test-only","token_type":"Bearer","expires_in":31536000,"session_id":"session-test","scope":"tv_panels"}"#
    static let enabled = #"{"enabled":true,"setup_required":false,"authenticated":false,"username":null,"mode":"required","first_run":false,"tv_sign_in":{"supported":true,"enabled":true,"protocol_version":1}}"#
    static let challenge = #"{"device_code":"private-test-code","user_code":"WDJB-MJHT","verification_path":"/activate","verification_path_complete":"/activate?user_code=WDJB-MJHT","expires_in":600,"interval":5}"#

    func testCapabilityMissingDisabledAndUnknownVersionDoNotEnroll() throws {
        let old = try JSONDecoder().decode(AuthStatus.self, from: Data(Fixtures.authStatusEnabled.utf8))
        XCTAssertFalse(old.tvSignIn?.isEnabled ?? false)
        for replacement in ["\"enabled\":false,\"protocol_version\":1", "\"enabled\":true,\"protocol_version\":2"] {
            let json = Self.enabled.replacingOccurrences(of: "\"enabled\":true,\"protocol_version\":1", with: replacement)
            XCTAssertFalse(try JSONDecoder().decode(AuthStatus.self, from: Data(json.utf8)).tvSignIn!.isEnabled)
        }
    }

    func testURLsUseChosenAuthorityAndPrefixAndContainOnlyPublicCode() throws {
        let challenge = try JSONDecoder().decode(DeviceChallenge.self, from: Data(Self.challenge.utf8))
        let urls = try challenge.verificationURLs(baseURL: host)
        XCTAssertEqual(urls.manual.absoluteString, "https://board.example:4420/fiesta/activate")
        XCTAssertEqual(urls.complete.absoluteString, "https://board.example:4420/fiesta/activate?user_code=WDJB-MJHT")
        XCTAssertFalse(urls.complete.absoluteString.contains(challenge.deviceCode))
        for hostile in ["//evil.example/activate", "https://evil.example/activate", "/%2f%2fevil.example", "/activate?device_code=private-test-code"] {
            let json = Self.challenge.replacingOccurrences(of: "/activate?user_code=WDJB-MJHT", with: hostile)
            let bad = try JSONDecoder().decode(DeviceChallenge.self, from: Data(json.utf8))
            XCTAssertThrowsError(try bad.verificationURLs(baseURL: host))
        }
    }

    func testDevicePasswordAndPollingDecodeIdenticalTokenAndMetadata() async throws {
        let client = FiestaClient(baseURL: host, session: StubURLProtocol.makeSession())
        StubURLProtocol.enqueue(.json(Self.token), for: "/auth/device/login")
        StubURLProtocol.enqueue(.json(Self.token), for: "/auth/device/token")
        let password = try await client.loginDevice(username: "user", password: "secret", deviceName: "Apple TV", appVersion: "1")
        let polling = try await client.pollDeviceSignIn(deviceCode: "private-test-code")
        XCTAssertEqual(password, polling)
        let body = try XCTUnwrap(StubURLProtocol.requests.first?.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json["client_id"], "fiestaboard-tvos")
        XCTAssertEqual(json["password"], "secret")
    }

    func testDeviceErrorsKeepStableCodeAndRetryAfterInsteadOfSetupMapping() async throws {
        let client = FiestaClient(baseURL: host, session: StubURLProtocol.makeSession())
        for (status, code) in [(400, "authorization_pending"), (400, "slow_down"), (400, "access_denied"), (400, "expired_token"), (400, "invalid_grant"), (403, "feature_disabled"), (409, "session_limit")] {
            StubURLProtocol.enqueue(.json("{\"error\":\"\(code)\",\"detail\":\"safe\"}", status: status), for: "/auth/device/token")
            do { _ = try await client.pollDeviceSignIn(deviceCode: "test"); XCTFail("expected error") }
            catch let error as DevicePollError { XCTAssertEqual(error.code, code) }
        }
        StubURLProtocol.enqueue(.init(status: 429, body: Data(#"{"error":"rate_limited"}"#.utf8), headers: ["Retry-After": "17"]), for: "/auth/device/token")
        do { _ = try await client.pollDeviceSignIn(deviceCode: "test"); XCTFail("expected error") }
        catch let error as DevicePollError { XCTAssertEqual(error.retryAfter, 17) }
    }

    func testTaggedCredentialHasNoPasswordAndOldJSONStillDecodes() throws {
        let old = try JSONDecoder().decode(StoredCredential.self, from: Data(#"{"username":"u","password":"p"}"#.utf8))
        XCTAssertEqual(old.username, "u")
        let credential = StoredCredential.deviceToken(accessToken: "fb_tv_test", sessionID: "test", expiresAt: Date(timeIntervalSince1970: 2_000_000_000))
        let data = try JSONEncoder().encode(credential)
        XCTAssertEqual(try JSONDecoder().decode(StoredCredential.self, from: data), credential)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("password"))
    }

    func testBearerIsSentOnlyToScopedRequestsAndNeverChatOrDiscovery() async throws {
        let client = FiestaClient(baseURL: host, session: StubURLProtocol.makeSession())
        client.setDeviceToken("fb_tv_test")
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/api/panels")
        _ = try await client.panels()
        XCTAssertEqual(StubURLProtocol.requests.last?.authorization, "Bearer fb_tv_test")
        do { _ = try await client.aiAvailability(); XCTFail("scoped credential cannot access AI") }
        catch FiestaError.http(403) {}
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }
}

extension DeviceAuthorizationTests {
    func testRedirectsNeverForwardCopiedCookiesTokensOrPasswords() async throws {
        let delegate = NoCredentialRedirects()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URL(string: "https://board.test/api/auth/device/login")!)
        for target in ["https://attacker.test/api/panels", "http://board.test/api/panels", "https://board.test/other/api/panels"] {
            var redirected = URLRequest(url: URL(string: target)!)
            redirected.setValue("Bearer fb_tv_test", forHTTPHeaderField: "Authorization")
            redirected.setValue("fiestaboard_session=test", forHTTPHeaderField: "Cookie")
            redirected.httpBody = Data("password=test".utf8)
            let response = HTTPURLResponse(url: task.originalRequest!.url!, statusCode: 307, httpVersion: nil, headerFields: ["Location": target])!
            let result: URLRequest? = await withCheckedContinuation { continuation in
                delegate.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: redirected) { continuation.resume(returning: $0) }
            }
            XCTAssertNil(result)
        }
    }
    func testNormalizedKeyPreservesServerPrefixAndPort() {
        XCTAssertEqual(FiestaClient.normalizedBaseURL(URL(string: "HTTPS://BOARD.test:443/fiesta/api/")!).absoluteString, "https://board.test/fiesta")
        XCTAssertEqual(FiestaClient.normalizedBaseURL(URL(string: "http://[::1]:4420/fiesta/")!).absoluteString, "http://[::1]:4420/fiesta")
    }
    func testDeviceBearerRejectsOutOfScopePatchFieldsLocally() async throws {
        let client = FiestaClient(baseURL: URL(string: "http://board.test")!, session: StubURLProtocol.makeSession())
        client.setDeviceToken("fb_tv_test")
        do {
            _ = try await client.send(method: "PATCH", path: "/panels/one", body: ["render_style": "matrix", "name": "not-permitted"])
            XCTFail("mixed fields must fail closed")
        } catch FiestaError.http(403) {}
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }
}

extension DeviceAuthorizationTests {
    func testCanonicalServerFixtureDecodesAndBuildsAllDeploymentURLs() throws {
        let url = Bundle(for: Self.self).url(forResource: "tv-sign-in-v1", withExtension: "json") ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/tv-sign-in-v1.json")
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        func data(_ key: String) throws -> Data { try JSONSerialization.data(withJSONObject: fixture[key]!) }
        let status = try JSONDecoder().decode(AuthStatus.self, from: data("status"))
        XCTAssertTrue(status.tvSignIn?.isEnabled == true)
        let old = try JSONDecoder().decode(AuthStatus.self, from: data("old_server_status"))
        XCTAssertNil(old.tvSignIn)
        let challenge = try JSONDecoder().decode(DeviceChallenge.self, from: data("challenge"))
        let token = try JSONDecoder().decode(DeviceTokenResult.self, from: data("token"))
        XCTAssertNotNil(try token.credential(now: Date()).accessToken)
        let urls = try XCTUnwrap(fixture["url_examples"] as? [[String: String]])
        for entry in urls {
            let base = try XCTUnwrap(URL(string: entry["base"]!))
            let actual = try challenge.verificationURLs(baseURL: base)
            XCTAssertEqual(actual.manual.absoluteString, entry["base"]! + "/activate")
            XCTAssertEqual(actual.complete.absoluteString, entry["activation"])
        }
    }
}
