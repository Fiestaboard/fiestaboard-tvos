import XCTest
@testable import FiestaBoardTV

@MainActor
final class PanelDisplaySettingsTests: XCTestCase {
    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    private func model() async -> SettingsModel {
        let app = AppModel(connection: ConnectionStore(
            defaults: UserDefaults(suiteName: UUID().uuidString)!, credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) }))
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try? await app.connection.connect(to: URL(string: "http://host:4420")!, displayName: "Board")
        return SettingsModel(app: app)
    }

    func testFailedSaveRetainsLoadedPanelAndDraftForRetry() async throws {
        let model = await model()
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
        let model = await model()
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
        let model = await model()
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
