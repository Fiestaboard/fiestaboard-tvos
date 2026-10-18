import XCTest
import Network
@testable import FiestaBoardTV

final class HardeningTests: XCTestCase {
    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    private let host = URL(string: "http://board.local:4420")!

    private func connection(credentials: InMemoryCredentialStore = InMemoryCredentialStore()) async throws -> ConnectionStore {
        let store = ConnectionStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                    credentials: credentials,
                                    clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await store.connect(to: host, displayName: "Board")
        return store
    }

    @MainActor
    func testMatrixTransitionToggleSavesAndUpdatesThePanel() async throws {
        let model = SettingsModel(app: AppModel(connection: try await connection()))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(Fixtures.panelJSON.utf8)) as? [String: Any])
        json["render_style"] = "led_matrix"
        json["animations_enabled"] = false
        let panel = try JSONDecoder().decode(Panel.self, from: JSONSerialization.data(withJSONObject: json))
        model.panels = [panel]
        json["animations_enabled"] = true
        let response = try JSONSerialization.data(withJSONObject: json)
        StubURLProtocol.enqueue(.json(String(decoding: response, as: UTF8.self)), for: "/api/panels/")
        await model.setAnimationEnabled(true, for: panel)
        XCTAssertTrue(model.animationEnabled(for: panel))
        let request = try XCTUnwrap(StubURLProtocol.requests.first { $0.method == "PATCH" })
        let body = try XCTUnwrap(request.body)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: Bool], ["animations_enabled": true])
    }

    func testNonFiniteScreenDimensionsAreRejected() {
        XCTAssertThrowsError(try BoardGeometry.screenDimensionsIn(diagonal: .infinity))
        XCTAssertThrowsError(try BoardGeometry.screenDimensionsIn(diagonal: 65, aspectW: .infinity))
    }

    func testHugeFiniteScreenSizeClampsBeforeIntegerConversion() throws {
        let grid = try BoardGeometry.computeAutofitGrid(diagonal: 1e30)
        XCTAssertEqual(grid.notesWide, 8)
        XCTAssertEqual(grid.notesTall, 8)
    }

    @MainActor
    func testInfiniteCustomDiagonalIsRejectedBeforeSaving() async throws {
        let model = SettingsModel(app: AppModel(connection: try await connection()))
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        model.setCustomDiagonal("inf")
        // Validation must not enter geometry (which cannot convert infinity to Int).
        await model.resize(panel: panel)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(StubURLProtocol.requests.contains { $0.method == "PATCH" })
    }

    @MainActor
    func testCustomSizeOutsideServerRangeKeepsTheLastValidSize() async throws {
        let model = SettingsModel(app: AppModel(connection: try await connection()))
        model.setCustomDiagonal("75")
        for invalid in ["1e30", "201", "2", "nan", "inf"] {
            model.setCustomDiagonal(invalid)
            XCTAssertEqual(model.resizeDiagonal, 75, invalid)
            XCTAssertEqual(model.previewGrid, "—", invalid)
        }
    }

    func testManualIPv6UsesTheBoardsDefaultPort() {
        XCTAssertEqual(ManualAddress.parse("[::1]")?.absoluteString, "http://[::1]:4420")
        XCTAssertEqual(ManualAddress.parse("[::1]:8080")?.port, 8080)
    }

    func testManualAddressRejectsComponentsThatBreakAPIRequests() {
        for input in ["ftp://board.local", "http://board.local:70000", "http://board.local?x=1",
                      "http://board.local#panels", "http://user:password@board.local", "/panels"] {
            XCTAssertNil(ManualAddress.parse(input), input)
        }
    }

    func testDroppingPanelStoreReleasesItsPollLoop() async {
        StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/api/panel/1")
        StubURLProtocol.enqueue(.json(Fixtures.frameJSON), for: "/frame")
        var store: PanelStore? = PanelStore(client: FiestaClient(baseURL: host, session: StubURLProtocol.makeSession()), ref: "1")
        weak var released = store
        var iterator = store!.snapshots().makeAsyncIterator()
        _ = await iterator.next()
        store = nil
        XCTAssertNil(released, "the suspended poll task must not own its store forever")
        released?.stop()
        released = nil
    }

    @MainActor
    func testBackDuringSignInDoesNotNavigateWhenTheReplyArrives() async throws {
        let app = AppModel(connection: try await connection())
        app.route = .signIn
        let model = SignInModel(app: app)
        model.username = "a"
        model.password = "secret"
        let started = expectation(description: "login started")
        let reply = ReplyGate()
        var stub = StubURLProtocol.Stub.json(Fixtures.loginOK)
        stub.beforeReply = { finish in reply.store(finish); started.fulfill() }
        StubURLProtocol.enqueue(stub, for: "/api/auth/login")
        let login = Task { await model.submit() }
        await fulfillment(of: [started], timeout: 2)
        model.back()
        reply.finish()
        await login.value
        XCTAssertEqual(app.route, .connect)
    }

    func testSignOutDiscardsAnAuthorizedResponseAlreadyInFlight() async throws {
        let store = try await connection()
        let started = expectation(description: "panel request started")
        let reply = ReplyGate()
        var stub = StubURLProtocol.Stub.json(Fixtures.panelsList)
        stub.beforeReply = { finish in reply.store(finish); started.fulfill() }
        StubURLProtocol.enqueue(stub, for: "/api/panels")
        let request = Task { try await store.authorized { try await $0.panels() } }
        await fulfillment(of: [started], timeout: 2)
        store.signOut()
        reply.finish()
        do {
            _ = try await request.value
            XCTFail("signed-out requests must not return data to the old screen")
        } catch is CancellationError {}
    }

    func testSignedOutStoreDoesNotSendAuthorizedRequests() async throws {
        let store = try await connection()
        store.signOut()
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/api/panels")
        do {
            _ = try await store.authorized { try await $0.panels() }
            XCTFail("expected unauthorized")
        } catch FiestaError.unauthorized {}
        XCTAssertFalse(StubURLProtocol.requests.contains { $0.url.path == "/api/panels" })
    }

    func testConfigUnauthorizedCannotBeHiddenByAFrameFailure() async throws {
        StubURLProtocol.enqueue(.json("{}", status: 401), for: "/api/panel/1")
        let store = PanelStore(client: FiestaClient(baseURL: host, session: StubURLProtocol.makeSession()), ref: "1")
        defer { store.stop() }
        var iterator = store.snapshots().makeAsyncIterator()
        let snapshot = await iterator.next()
        XCTAssertEqual(snapshot?.connection, .unauthorized)
        XCTAssertFalse(StubURLProtocol.requests.contains { $0.url.path.hasSuffix("/frame") })
    }

    func testTemporaryLoginOutageDoesNotRejectTheStoredPassword() async throws {
        let credentials = InMemoryCredentialStore()
        let store = try await connection(credentials: credentials)
        try credentials.save(StoredCredential(username: "a", password: "valid"), for: host.absoluteString)
        StubURLProtocol.enqueue(.json("{}", status: 401), for: "/api/panels")
        StubURLProtocol.enqueue(.json("{}", status: 503), for: "/api/auth/login")
        do {
            _ = try await store.authorized { try await $0.panels() }
            XCTFail("expected the temporary outage")
        } catch FiestaError.unavailable {}
        StubURLProtocol.enqueue(.json("{}", status: 401), for: "/api/panels")
        StubURLProtocol.enqueue(.json(Fixtures.loginOK), for: "/api/auth/login")
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/api/panels")
        let panels = try await store.authorized { try await $0.panels() }
        XCTAssertEqual(panels.count, 1)
    }

    func testSignOutCannotBeUndoneByALateSignInReply() async throws {
        let credentials = InMemoryCredentialStore()
        let store = try await connection(credentials: credentials)
        let started = expectation(description: "login started")
        let reply = ReplyGate()
        var stub = StubURLProtocol.Stub.json(Fixtures.loginOK)
        stub.beforeReply = { finish in reply.store(finish); started.fulfill() }
        StubURLProtocol.enqueue(stub, for: "/api/auth/login")
        let login = Task { try await store.signIn(username: "a", password: "secret") }
        await fulfillment(of: [started], timeout: 2)
        store.signOut()
        reply.finish()
        _ = try? await login.value
        XCTAssertTrue(store.isSignedOut)
        XCTAssertNil(credentials.load(for: host.absoluteString))
    }

    func testLateLoginCookieCannotAuthenticateAfterSignOutOrForget() async throws {
        for forget in [false, true] {
            let started = expectation(description: "real HTTP login started")
            let replies = ReplyGate()
            let server = try LoginCookieServer { reply in replies.store(reply); started.fulfill() }
            defer { server.stop() }
            let store = ConnectionStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                        credentials: InMemoryCredentialStore())
            _ = try await store.connect(to: server.url, displayName: "Test")
            let login = Task { try await store.signIn(username: "a", password: "secret") }
            await fulfillment(of: [started], timeout: 3)
            if forget { store.forget() } else { store.signOut() }
            replies.finish()
            _ = try? await login.value
            if let client = store.client {
                let status = try await client.authStatus()
                XCTAssertFalse(status.authenticated, "the signed-out client must have a fresh cookie jar")
            }
            let result = try await store.connect(to: server.url, displayName: "Test")
            XCTAssertEqual(result, .needsSignIn, "an obsolete response must not restore a cookie")
            store.forget()
        }
    }

    func testReplacingSnapshotStreamDoesNotLetOldTerminationStopNewPolling() async {
        let entered = expectation(description: "old poll suspended")
        let gate = PollGate(entered: entered)
        let client = FiestaClient(baseURL: host, session: StubURLProtocol.makeSession())
        let runner = GatedRunner(client: client, gate: gate)
        for _ in 0..<5 {
            StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/api/panel/1")
            StubURLProtocol.enqueue(.json(Fixtures.frameJSON), for: "/frame")
        }
        let store = PanelStore(runner: runner, ref: "1", frameInterval: 0.1)
        let old = store.snapshots()
        await fulfillment(of: [entered], timeout: 2)
        let continued = expectation(description: "replacement produces two snapshots")
        let consumer = Task {
            var count = 0
            for await _ in store.snapshots() {
                count += 1
                if count == 1 { await gate.release() }
                if count == 2 { continued.fulfill(); break }
            }
        }
        await fulfillment(of: [continued], timeout: 2)
        store.stop()
        consumer.cancel()
        withExtendedLifetime(old) {}
    }
}

private final class ReplyGate: @unchecked Sendable {
    private let lock = NSLock()
    private var reply: (() -> Void)?
    func store(_ value: @escaping () -> Void) { lock.withLock { reply = value } }
    func finish() { lock.withLock { reply }?() }
}

private actor PollGate {
    let entered: XCTestExpectation
    var first = true
    var continuation: CheckedContinuation<Void, Never>?
    init(entered: XCTestExpectation) { self.entered = entered }
    func waitOnce() async {
        guard first else { return }
        first = false
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            entered.fulfill()
        }
    }
    func release() { continuation?.resume(); continuation = nil }
}

private struct GatedRunner: AuthorizedRunner {
    let client: FiestaClient
    let gate: PollGate
    func authorized<T>(_ operation: (FiestaClient) async throws -> T) async throws -> T {
        await gate.waitOnce()
        return try await operation(client)
    }
}

/// Uses a real socket because URLProtocol stubs do not exercise URLSession's
/// automatic cookie handling. The response is held across Sign Out/Forget.
private final class LoginCookieServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "HardeningTests.loginCookie")
    private let onLogin: (@escaping () -> Void) -> Void
    private let cookieName = "hardening_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
    var url: URL { URL(string: "http://127.0.0.1:\(listener.port!.rawValue)")! }

    init(onLogin: @escaping (@escaping () -> Void) -> Void) throws {
        self.onLogin = onLogin
        listener = try NWListener(using: .tcp, on: .any)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed: ready.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 3) == .success, listener.port != nil else {
            listener.cancel()
            throw URLError(.cannotConnectToHost)
        }
    }

    func stop() {
        listener.cancel()
        for cookie in HTTPCookieStorage.shared.cookies ?? [] where cookie.name == cookieName {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, accumulated: Data())
    }

    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, done, _ in
            guard let self, let data else { connection.cancel(); return }
            let requestData = accumulated + data
            let request = String(decoding: requestData, as: UTF8.self)
            guard request.contains("\r\n\r\n") else {
                if done { connection.cancel() }
                else { self.receive(connection, accumulated: requestData) }
                return
            }
            let isLogin = request.hasPrefix("POST /api/auth/login ")
            let authenticated = request.contains("\(self.cookieName)=accepted")
            let body = isLogin ? Fixtures.loginOK : Fixtures.authStatusEnabled
                .replacingOccurrences(of: "\"authenticated\":false", with: "\"authenticated\":\(authenticated)")
            let payload = Data(body.utf8)
            let cookie = isLogin ? "Set-Cookie: \(self.cookieName)=accepted; Path=/; HttpOnly\r\n" : ""
            let response = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\(cookie)Content-Length: \(payload.count)\r\nConnection: close\r\n\r\n".utf8) + payload
            let reply = {
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            }
            if isLogin { self.onLogin(reply) } else { reply() }
        }
    }
}
