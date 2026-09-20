import XCTest
@testable import FiestaBoardTV

final class FiestaClientTests: XCTestCase {

    private var client: FiestaClient!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        client = FiestaClient(baseURL: URL(string: "http://192.168.1.50:4420")!,
                              session: StubURLProtocol.makeSession())
    }

    override func tearDown() {
        StubURLProtocol.reset()
        client = nil
        super.tearDown()
    }

    func testAuthStatusDecodesSnakeCase() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/auth/status")
        let status = try await client.authStatus()
        XCTAssertTrue(status.enabled)
        XCTAssertFalse(status.authenticated)
        XCTAssertEqual(status.mode, "enabled")
        XCTAssertFalse(status.setupRequired)
    }

    func testLoginPostsCredentialsAndAlwaysAsksToBeRemembered() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.loginOK), for: "/auth/login")
        try await client.login(username: "jeffre", password: "hunter2")

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.path, "/auth/login")

        let body = try XCTUnwrap(request.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["username"] as? String, "jeffre")
        XCTAssertEqual(json["password"] as? String, "hunter2")
        // A TV that re-prompts for a password every week gets unplugged.
        XCTAssertEqual(json["remember_me"] as? Bool, true)
    }

    func testLoginMapsA401ToUnauthorized() async {
        StubURLProtocol.enqueue(.json(#"{"detail":"Invalid username or password"}"#, status: 401),
                                for: "/auth/login")
        do {
            try await client.login(username: "jeffre", password: "wrong")
            XCTFail("expected unauthorized")
        } catch FiestaError.unauthorized {
            // expected
        } catch {
            XCTFail("expected .unauthorized, got \(error)")
        }
    }

    /// A 409 from any endpoint means no user exists yet — the app must send
    /// the user to the web UI rather than offer a sign-in form that cannot work.
    func testSetupRequiredIsItsOwnError() async {
        StubURLProtocol.enqueue(.json(#"{"detail":"Setup required","setup_required":true}"#, status: 409),
                                for: "/panels")
        do {
            _ = try await client.panels()
            XCTFail("expected setupRequired")
        } catch FiestaError.setupRequired {
            // expected
        } catch {
            XCTFail("expected .setupRequired, got \(error)")
        }
    }

    func testPanelsDecodesTheListEnvelope() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/panels")
        let panels = try await client.panels()
        XCTAssertEqual(panels.count, 1)
        let panel = try XCTUnwrap(panels.first)
        XCTAssertEqual(panel.id, "abc123def456")
        XCTAssertEqual(panel.shortCode, 1)
        XCTAssertEqual(panel.name, "Living Room")
        XCTAssertEqual(panel.rows, 12)
        XCTAssertEqual(panel.cols, 30)
        XCTAssertEqual(panel.deviceType, "note_array")
        XCTAssertEqual(panel.code62Glyph, .heart)
        XCTAssertEqual(panel.autoDim.start, "22:00")
        XCTAssertTrue(panel.autoDim.enabled)
        XCTAssertFalse(panel.animationsEnabled)
    }

    func testPanelsMapsA401ToUnauthorized() async {
        StubURLProtocol.enqueue(.json(#"{"detail":"Not authenticated"}"#, status: 401), for: "/panels")
        do {
            _ = try await client.panels()
            XCTFail("expected unauthorized")
        } catch FiestaError.unauthorized {
        } catch {
            XCTFail("expected .unauthorized, got \(error)")
        }
    }

    /// The viewer surface takes an id OR a short code, so /panel/1 must work.
    func testPanelAcceptsAShortCodeRef() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/panel/")
        _ = try await client.panel(ref: "1")
        XCTAssertEqual(StubURLProtocol.requests.first?.url.path, "/panel/1")
    }

    func testFrameDecodesCharactersAndTimestamp() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.frameJSON), for: "/frame")
        let frame = try await client.frame(ref: "abc123def456")
        XCTAssertEqual(frame.characters?.count, 2)
        XCTAssertEqual(frame.characters?[0], [8, 9, 0])
        XCTAssertEqual(frame.rows, 2)
        XCTAssertEqual(frame.cols, 3)
        XCTAssertNotNil(frame.updatedAt)
    }

    /// A board nothing has been sent to yet is blank, not broken.
    func testFrameToleratesNullCharacters() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.emptyFrameJSON), for: "/frame")
        let frame = try await client.frame(ref: "abc123def456")
        XCTAssertNil(frame.characters)
        XCTAssertNil(frame.updatedAt)
        XCTAssertEqual(frame.cols, 30)
    }

    func testDeletedPanelIsNotFound() async {
        StubURLProtocol.enqueue(.json(Fixtures.panelNotFound, status: 404), for: "/panel/")
        do {
            _ = try await client.panel(ref: "gone")
            XCTFail("expected notFound")
        } catch FiestaError.notFound {
        } catch {
            XCTFail("expected .notFound, got \(error)")
        }
    }

    func testUpdatePanelPatchesOnlyTheFieldsGiven() async throws {
        let response = #"{"status":"success","panel":\#(Fixtures.panelJSON)}"#
        StubURLProtocol.enqueue(.json(response), for: "/panels/")
        _ = try await client.updatePanel(id: "abc123def456", diagonal: 55, aspectW: 16, aspectH: 9)

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.method, "PATCH")
        XCTAssertEqual(request.url.path, "/panels/abc123def456")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body!) as? [String: Any])
        XCTAssertEqual(json["screen_diagonal_inches"] as? Double, 55)
        XCTAssertEqual(json["screen_aspect_w"] as? Double, 16)
        XCTAssertNil(json["name"], "an unset field must not be sent")
        XCTAssertNil(json["calibration_scale"], "an unset field must not be sent")
    }

    /// Reshaping a grid can strand pages authored for the old one. The server
    /// warns; the app must carry that warning rather than swallow it.
    func testUpdatePanelSurfacesIncompatibleReferences() async throws {
        let response = """
        {"status":"success","panel":\(Fixtures.panelJSON),
         "incompatible_references":[{"type":"page","id":"p1","name":"Welcome"}]}
        """
        StubURLProtocol.enqueue(.json(response), for: "/panels/")
        let result = try await client.updatePanel(id: "abc123def456", diagonal: 85)
        XCTAssertEqual(result.incompatibleReferences.count, 1)
        XCTAssertEqual(result.incompatibleReferences.first?.name, "Welcome")
    }

    func testTransportFailuresAreWrapped() async {
        // Nothing enqueued: the stub fails the request.
        do {
            _ = try await client.authStatus()
            XCTFail("expected transport error")
        } catch FiestaError.transport {
        } catch {
            XCTFail("expected .transport, got \(error)")
        }
    }

    func testBaseURLPathsAreJoinedWithoutDoubleSlashes() async throws {
        let trailing = FiestaClient(baseURL: URL(string: "http://host:4420/")!,
                                    session: StubURLProtocol.makeSession())
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/auth/status")
        _ = try await trailing.authStatus()
        XCTAssertEqual(StubURLProtocol.requests.first?.url.absoluteString,
                       "http://host:4420/auth/status")
    }
}
