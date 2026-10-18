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
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/api/auth/status")
        let status = try await client.authStatus()
        XCTAssertTrue(status.enabled)
        XCTAssertFalse(status.authenticated)
        XCTAssertEqual(status.mode, "enabled")
        XCTAssertFalse(status.setupRequired)
    }

    func testPublicServerUsesTheAPIPrefix() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/api/auth/status")
        _ = try await client.authStatus()
        XCTAssertEqual(StubURLProtocol.requests.first?.url.path, "/api/auth/status")
    }

    func testLoginPostsCredentialsAndAlwaysAsksToBeRemembered() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.loginOK), for: "/api/auth/login")
        try await client.login(username: "jeffre", password: "hunter2")

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.path, "/api/auth/login")

        let body = try XCTUnwrap(request.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["username"] as? String, "jeffre")
        XCTAssertEqual(json["password"] as? String, "hunter2")
        // A TV that re-prompts for a password every week gets unplugged.
        XCTAssertEqual(json["remember_me"] as? Bool, true)
    }

    func testLoginMapsA401ToUnauthorized() async {
        StubURLProtocol.enqueue(.json(#"{"detail":"Invalid username or password"}"#, status: 401),
                                for: "/api/auth/login")
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
                                for: "/api/panels")
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
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/api/panels")
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
        StubURLProtocol.enqueue(.json(#"{"detail":"Not authenticated"}"#, status: 401), for: "/api/panels")
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
        StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/api/panel/")
        _ = try await client.panel(ref: "1")
        XCTAssertEqual(StubURLProtocol.requests.first?.url.path, "/api/panel/1")
    }

    func testFrameDecodesCharactersAndTimestamp() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.frameJSON), for: "/frame")
        let frame = try await client.frame(ref: "abc123def456")
        XCTAssertEqual(frame.characters?.count, 2)
        XCTAssertEqual(frame.characters?[0], [8, 9, 0])
        XCTAssertEqual(frame.rows, 2)
        XCTAssertEqual(frame.cols, 3)
        // The instant, not merely "something parsed": a formatter reading
        // that string as a different moment satisfied `XCTAssertNotNil` too.
        XCTAssertEqual(try XCTUnwrap(frame.updatedAt).timeIntervalSince1970,
                       1_789_813_800, accuracy: 0.001)  // 2026-09-19T10:30:00Z
    }

    /// `fiestaDate` tries a fractional-seconds formatter before a plain one
    /// because the server emits both spellings. Every fixture in this file is
    /// the plain one, so nothing entered the branch that exists for the other
    /// — deleting it would have left `updatedAt` nil on half the server's
    /// paths with the suite still green.
    func testAFractionalSecondsTimestampAlsoDecodes() async throws {
        StubURLProtocol.enqueue(
            .json(#"{"characters":null,"rows":1,"cols":1,"updated_at":"2026-09-19T10:30:00.250Z"}"#),
            for: "/frame")
        let frame = try await client.frame(ref: "abc123def456")
        XCTAssertEqual(try XCTUnwrap(frame.updatedAt).timeIntervalSince1970,
                       1_789_813_800.25, accuracy: 0.001)
    }

    /// A board nothing has been sent to yet is blank, not broken.
    func testFrameToleratesNullCharacters() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.emptyFrameJSON), for: "/frame")
        let frame = try await client.frame(ref: "abc123def456")
        XCTAssertNil(frame.characters)
        XCTAssertNil(frame.updatedAt)
        XCTAssertEqual(frame.cols, 30)
    }

    /// The server's grid dimensions are clamped where they are decoded,
    /// because that is the one point every consumer passes through — the
    /// panel-list preview builds straight off a decoded frame and never
    /// goes near `PanelStore`. Unclamped, `rows * cols` reached
    /// `reserveCapacity` as an unchecked multiply and took the app down on
    /// every launch, since a configured TV relaunches into the viewer.
    func testAbsurdFrameDimensionsAreClampedAtTheDecodeBoundary() async throws {
        StubURLProtocol.enqueue(.json(#"{"characters":null,"rows":100000,"cols":100000}"#),
                                for: "/frame")
        let frame = try await client.frame(ref: "abc123def456")
        XCTAssertEqual(frame.rows, PanelFrame.maxDimension)
        XCTAssertEqual(frame.cols, PanelFrame.maxDimension)
    }

    func testNegativeFrameDimensionsDecodeAsAnEmptyGrid() async throws {
        StubURLProtocol.enqueue(.json(#"{"rows":-4,"cols":-1}"#), for: "/frame")
        let frame = try await client.frame(ref: "abc123def456")
        XCTAssertEqual(frame.rows, 0)
        XCTAssertEqual(frame.cols, 0)
    }

    /// A real board stays under the ceiling, so nothing anyone owns is
    /// altered on the way in.
    func testRealBoardDimensionsPassThroughUntouched() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.emptyFrameJSON), for: "/frame")
        let frame = try await client.frame(ref: "abc123def456")
        XCTAssertEqual(frame.rows, 12)
        XCTAssertEqual(frame.cols, 30)
    }

    /// The viewer re-reads the panel config every ten seconds. Decoding
    /// `code62_glyph` as the enum threw on any value this build has never
    /// heard of and failed the whole `Panel`, so the day the server learns a
    /// new glyph every shipped TV would stop polling over a field it can
    /// already default.
    func testAnUnrecognisedCode62GlyphDoesNotFailTheWholePanel() async throws {
        let json = Fixtures.panelsList
            .replacingOccurrences(of: #""code62_glyph":"heart""#,
                                  with: #""code62_glyph":"sparkle""#)
            .replacingOccurrences(of: #""device_type":"note_array""#,
                                  with: #""device_type":"flagship""#)
        StubURLProtocol.enqueue(.json(json), for: "/api/panels")

        let panels = try await client.panels()
        let panel = try XCTUnwrap(panels.first)
        XCTAssertEqual(panel.name, "Living Room")
        XCTAssertNil(panel.code62Glyph)
        XCTAssertEqual(panel.effectiveCode62, .degree)
    }

    func testDeletedPanelIsNotFound() async {
        StubURLProtocol.enqueue(.json(Fixtures.panelNotFound, status: 404), for: "/api/panel/")
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
        StubURLProtocol.enqueue(.json(response), for: "/api/panels/")
        _ = try await client.updatePanel(id: "abc123def456", diagonal: 55, aspectW: 16, aspectH: 9)

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.method, "PATCH")
        XCTAssertEqual(request.url.path, "/api/panels/abc123def456")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body!) as? [String: Any])
        XCTAssertEqual(json["screen_diagonal_inches"] as? Double, 55)
        XCTAssertEqual(json["screen_aspect_w"] as? Double, 16)
        // `name` was the assertion here, and `updatePanel` takes no name —
        // no edit to it could have put one in the body. The keys it CAN send
        // are the ones worth pinning: a default sent for any of them clears a
        // setting on the board that nobody asked to change.
        XCTAssertEqual(Set(json.keys),
                       ["screen_diagonal_inches", "screen_aspect_w", "screen_aspect_h"],
                       "an unset field must not be sent: \(json.keys.sorted())")
    }

    func testCurrentNextPanelUpdateDecodesFlatResponseAndPageWarnings() async throws {
        var response = try JSONSerialization.jsonObject(with: Data(Fixtures.panelJSON.utf8)) as! [String: Any]
        response["render_style"] = "led_matrix"
        response["incompatible_references"] = [["page_id": "p1", "page_name": "Welcome", "surface": "schedule", "schedule_id": "s1"]]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: response), as: UTF8.self)
        StubURLProtocol.enqueue(.json(json), for: "/api/panels/")
        let result = try await client.updatePanel(id: "abc123def456", renderStyle: .ledMatrix)
        XCTAssertEqual(result.panel.id, "abc123def456")
        XCTAssertEqual(result.panel.renderStyle, .ledMatrix)
        XCTAssertEqual(result.incompatibleReferences.first?.id, "p1")
        XCTAssertEqual(result.incompatibleReferences.first?.name, "Welcome")
        XCTAssertEqual(result.incompatibleReferences.first?.type, "schedule")
    }

    func testCurrentNextPanelUpdateAcceptsNullWarnings() async throws {
        var response = try JSONSerialization.jsonObject(with: Data(Fixtures.panelJSON.utf8)) as! [String: Any]
        response["incompatible_references"] = NSNull()
        let json = String(decoding: try JSONSerialization.data(withJSONObject: response), as: UTF8.self)
        StubURLProtocol.enqueue(.json(json), for: "/api/panels/")
        let result = try await client.updatePanel(id: "abc123def456", calibration: 1.1)
        XCTAssertEqual(result.panel.name, "Living Room")
        XCTAssertTrue(result.incompatibleReferences.isEmpty)
    }

    func testMalformedPanelUpdateStillReportsDecodingFailure() async throws {
        StubURLProtocol.enqueue(.json(#"{"status":"success"}"#), for: "/api/panels/")
        do {
            _ = try await client.updatePanel(id: "abc123def456", calibration: 1.1)
            XCTFail("A response without a valid panel cannot confirm a save")
        } catch FiestaError.decoding { }
    }

    /// Reshaping a grid can strand pages authored for the old one. The server
    /// warns; the app must carry that warning rather than swallow it.
    func testUpdatePanelSurfacesIncompatibleReferences() async throws {
        let response = """
        {"status":"success","panel":\(Fixtures.panelJSON),
         "incompatible_references":[{"type":"page","id":"p1","name":"Welcome"}]}
        """
        StubURLProtocol.enqueue(.json(response), for: "/api/panels/")
        let result = try await client.updatePanel(id: "abc123def456", diagonal: 85)
        XCTAssertEqual(result.incompatibleReferences.count, 1)
        XCTAssertEqual(result.incompatibleReferences.first?.name, "Welcome")
    }

    /// nginx answers 503 for the 30-60s after a power cut, before FastAPI
    /// is listening. It is the most common failure anyone sees, and it is
    /// not the generic 5xx "check its logs" case.
    func testABootingBoardIsUnavailableRatherThanAServerError() async {
        StubURLProtocol.enqueue(
            .json(#"{"detail":"Service is starting up, please try again shortly"}"#, status: 503),
            for: "/api/auth/status")
        do {
            _ = try await client.authStatus()
            XCTFail("expected unavailable")
        } catch let error as FiestaError {
            // The exact case, not merely "a FiestaError": the regression this
            // guards is 503 falling through to `.http(503)`, and a bare
            // `catch FiestaError` would have been satisfied by that too.
            XCTAssertEqual(error, .unavailable)
            XCTAssertFalse(error.userMessage.contains("Check its logs"), error.userMessage)
        } catch {
            XCTFail("expected .unavailable, got \(error)")
        }
    }

    func testTheStartupMessageNeverSendsAnyoneToTheLogs() {
        XCTAssertEqual(FiestaError.unavailable.userMessage,
                       "Your FiestaBoard is still starting up. This usually takes under a minute.")
        // 503 must not be reached by the 500-range clause, and 429 must keep
        // matching ahead of it.
        XCTAssertTrue(FiestaError.http(500).userMessage.contains("Check its logs"))
        XCTAssertTrue(FiestaError.http(429).userMessage.contains("too many failed attempts"))
    }

    /// Every other 5xx still reaches `.http`, which several call sites
    /// pattern-match on by status.
    func testOtherServerErrorsKeepTheirStatusCode() async {
        StubURLProtocol.enqueue(.json(#"{"detail":"boom"}"#, status: 502), for: "/api/auth/status")
        do {
            _ = try await client.authStatus()
            XCTFail("expected http(502)")
        } catch FiestaError.http(let status) {
            XCTAssertEqual(status, 502)
        } catch {
            XCTFail("expected .http(502), got \(error)")
        }
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
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await trailing.authStatus()
        XCTAssertEqual(StubURLProtocol.requests.first?.url.absoluteString,
                       "http://host:4420/api/auth/status")
    }
    func testEditorPatchCannotReportSuccessWhenServerIgnoresFields() async throws {
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        var draft = PanelSettingsDraft(panel: panel)
        draft.name = "Kitchen"
        StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/api/panels/")
        do {
            _ = try await client.updatePanel(id: panel.id, patch: draft.patch())
            XCTFail("An HTTP 200 alone does not prove that settings saved")
        } catch PanelSettingsError.notApplied { }
    }

    func testEditorPatchPreservesExplicitNullForSizingReset() async throws {
        var json = try JSONSerialization.jsonObject(with: Data(Fixtures.panelJSON.utf8)) as! [String: Any]
        json["matrix_sizing"] = "true_size"
        json["matrix_pitch_mm"] = 5
        let panel = try JSONDecoder().decode(Panel.self, from: JSONSerialization.data(withJSONObject: json))
        var draft = PanelSettingsDraft(panel: panel)
        draft.matrixSizing = nil
        json["matrix_sizing"] = NSNull()
        StubURLProtocol.enqueue(.json(String(decoding: try JSONSerialization.data(withJSONObject: json), as: UTF8.self)), for: "/api/panels/")
        let result = try await client.updatePanel(id: panel.id, patch: draft.patch())
        XCTAssertNil(result.panel.matrixSizing)
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(StubURLProtocol.requests.last?.body)) as! NSDictionary
        XCTAssertEqual(body, ["matrix_sizing": NSNull()] as NSDictionary)
    }

}
