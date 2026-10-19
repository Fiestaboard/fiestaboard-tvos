import XCTest
@testable import FiestaBoardTV

@MainActor
final class PanelDisplaySettingsTests: XCTestCase {
    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    private func model(deviceCredential: Bool = false) async throws -> SettingsModel {
        let app = AppModel(connection: ConnectionStore(
            defaults: UserDefaults(suiteName: UUID().uuidString)!, credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) }))
        StubURLProtocol.enqueue(.json(deviceCredential ? DeviceAuthorizationTests.enabled : Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await app.connection.connect(to: URL(string: "http://host:4420")!, displayName: "Board")
        if deviceCredential {
            StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.token), for: "/auth/device/login")
            StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.enabled.replacingOccurrences(of: "\"authenticated\":false", with: "\"authenticated\":true")), for: "/api/auth/status")
            try await app.connection.signIn(username: "user", password: "test-password")
        }
        return SettingsModel(app: app)
    }

    func testTVSignInSavesAllSixPermittedPresentationFields() async throws {
        let model = try await model(deviceCredential: true)
        var original = try JSONSerialization.jsonObject(with: Data(Fixtures.panelJSON.utf8)) as! [String: Any]
        original["render_style"] = "split_flap"
        let panel = try JSONDecoder().decode(Panel.self, from: JSONSerialization.data(withJSONObject: original))
        model.panels = [panel]
        var draft = PanelSettingsDraft(panel: panel)
        draft.diagonalText = "75"
        draft.aspectWidthText = "21"
        draft.aspectHeightText = "10"
        draft.calibrationText = "1.1"
        draft.animationsEnabled = !panel.animationsEnabled
        draft.renderStyle = .ledMatrix
        let expected: [String: Any] = ["screen_diagonal_inches": 75.0, "screen_aspect_w": 21.0,
                                      "screen_aspect_h": 10.0, "calibration_scale": 1.1,
                                      "animations_enabled": !panel.animationsEnabled, "render_style": "led_matrix"]
        original.merge(expected) { _, new in new }
        StubURLProtocol.enqueue(.json(String(decoding: try JSONSerialization.data(withJSONObject: original), as: UTF8.self)), for: "/api/panels/")
        let result = await model.saveDisplaySettings(draft)
        XCTAssertNotNil(result)
        XCTAssertNil(model.errorMessage)
        let request = try XCTUnwrap(StubURLProtocol.requests.last { $0.method == "PATCH" })
        XCTAssertEqual(request.authorization, "Bearer fb_tv_test-only")
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as! [String: Any]
        XCTAssertTrue(NSDictionary(dictionary: body).isEqual(to: expected))
        XCTAssertEqual(model.panels.first?.screenDiagonalInches, 75)
    }

    func testTVSignInStillRejectsMixedUnsupportedEditsWithoutSendingAPatch() async throws {
        let model = try await model(deviceCredential: true)
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        model.panels = [panel]
        var draft = PanelSettingsDraft(panel: panel)
        draft.name = "Kitchen"
        draft.diagonalText = "75"
        let result = await model.saveDisplaySettings(draft)
        XCTAssertNil(result)
        XCTAssertTrue(model.errorMessage?.contains("403") == true)
        XCTAssertEqual(model.panels, [panel])
        XCTAssertFalse(StubURLProtocol.requests.contains { $0.method == "PATCH" })
    }

    func testTVSignInDimSummaryDirectsScheduleEditsToTheWeb() async throws {
        let model = try await model(deviceCredential: true)
        var object = try JSONSerialization.jsonObject(with: Data(Fixtures.panelJSON.utf8)) as! [String: Any]
        object["auto_dim"] = ["enabled": true, "start": "22:00", "end": "07:00"]
        model.panels = [try JSONDecoder().decode(Panel.self, from: JSONSerialization.data(withJSONObject: object))]
        model.hasLoaded = true
        XCTAssertTrue(model.autoDimSummary.contains("board's web page"), model.autoDimSummary)
        XCTAssertFalse(model.autoDimSummary.contains("All display settings"), model.autoDimSummary)
    }

    func testFailedSaveRetainsLoadedPanelAndDraftForRetry() async throws {
        let model = try await model()
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        model.panels = [panel]
        var draft = PanelSettingsDraft(panel: panel)
        draft.name = "Kitchen"
        StubURLProtocol.enqueue(.json("{}", status: 500), for: "/api/panels/")
        let failed = await model.saveDisplaySettings(draft)
        XCTAssertNil(failed)
        XCTAssertEqual(model.panels.first?.name, "Living Room")
        XCTAssertEqual(draft.name, "Kitchen")
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isSavingPanel(panel))
        StubURLProtocol.enqueue(.json(Fixtures.panelJSON.replacingOccurrences(of: "Living Room", with: "Kitchen")), for: "/api/panels/")
        let retried = await model.saveDisplaySettings(draft)
        XCTAssertEqual(retried?.panel.name, "Kitchen")
        XCTAssertEqual(model.panels.first?.name, "Kitchen")
        XCTAssertNil(model.errorMessage)
        let request = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertEqual(request.url.path, "/api/panels/abc123def456")
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as! [String: String]
        XCTAssertEqual(body, ["name": "Kitchen"])
    }

    func testValidationFailureMakesNoRequestAndLeavesPanelAvailable() async throws {
        let model = try await model()
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        model.panels = [panel]
        var draft = PanelSettingsDraft(panel: panel)
        draft.diagonalText = "NaN"
        let count = StubURLProtocol.requests.count
        let result = await model.saveDisplaySettings(draft)
        XCTAssertNil(result)
        XCTAssertEqual(StubURLProtocol.requests.count, count)
        XCTAssertEqual(model.panels, [panel])
        XCTAssertNotNil(model.errorMessage)
    }

    func testResizeUpdatesOnlyTargetPanelAndReportsIncompatibleReferences() async throws {
        let model = try await model()
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        let other = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.replacingOccurrences(of: "abc123def456", with: "other").utf8))
        model.panels = [other, panel]
        var draft = PanelSettingsDraft(panel: panel)
        draft.diagonalText = "75"
        var response = try JSONSerialization.jsonObject(with: Data(Fixtures.panelJSON.utf8)) as! [String: Any]
        response["screen_diagonal_inches"] = 75
        response["cols"] = 45
        response["incompatible_references"] = [["surface": "page", "page_id": "p1", "page_name": "Welcome"]]
        StubURLProtocol.enqueue(.json(String(decoding: try JSONSerialization.data(withJSONObject: response), as: UTF8.self)), for: "/api/panels/")
        let result = await model.saveDisplaySettings(draft)
        XCTAssertEqual(result?.panel.cols, 45)
        XCTAssertEqual(model.panels.first, other)
        XCTAssertEqual(model.panels.last?.screenDiagonalInches, 75)
        XCTAssertEqual(result?.incompatibleReferences.first?.id, "p1")
        XCTAssertNotNil(model.warningMessage)
    }
}
