import SwiftUI
import XCTest
@testable import FiestaBoardTV

@MainActor
final class SettingsScreenTests: XCTestCase {

    private func makeApp() async -> AppModel {
        let app = AppModel(connection: ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.settings.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) }))
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/auth/status")
        _ = try? await app.connection.connect(to: URL(string: "http://host:4420")!, displayName: "Board")
        return app
    }

    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    func testSettingADefaultPanelPersists() async {
        let app = await makeApp()
        let model = SettingsModel(app: app)
        model.setDefaultPanel("abc123def456")
        XCTAssertEqual(app.connection.saved?.defaultPanelRef, "abc123def456")
    }

    func testClearingTheDefaultPanelPersists() async {
        let app = await makeApp()
        let model = SettingsModel(app: app)
        model.setDefaultPanel("abc123def456")
        model.setDefaultPanel(nil)
        XCTAssertNil(app.connection.saved?.defaultPanelRef)
    }

    /// The preview is what makes the re-fit safe to accept: you see the new
    /// grid before the server reshapes anything.
    func testPreviewShowsTheGridADiagonalWouldProduce() async {
        let app = await makeApp()
        let model = SettingsModel(app: app)
        model.resizeDiagonal = 65
        XCTAssertEqual(model.previewGrid, "30 × 12", "65\" 16:9 is a 2x4 block grid")
        model.resizeDiagonal = 85
        XCTAssertEqual(model.previewGrid, "45 × 18", "85\" 16:9 is a 3x6 block grid")
    }

    func testResizePatchesTheDiagonal() async throws {
        let app = await makeApp()
        let model = SettingsModel(app: app)
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))

        StubURLProtocol.enqueue(.json(#"{"status":"success","panel":\#(Fixtures.panelJSON)}"#),
                                for: "/panels/")
        model.resizeDiagonal = 85
        await model.resize(panel: panel)

        let patch = StubURLProtocol.requests.first { $0.method == "PATCH" }
        let body = try XCTUnwrap(patch?.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["screen_diagonal_inches"] as? Double, 85)
    }

    /// Reshaping can strand pages authored for the old grid. The server
    /// warns; swallowing that would be rude.
    func testResizeSurfacesStrandedPages() async throws {
        let app = await makeApp()
        let model = SettingsModel(app: app)
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))

        let response = """
        {"status":"success","panel":\(Fixtures.panelJSON),
         "incompatible_references":[{"type":"page","id":"p1","name":"Welcome"},
                                    {"type":"page","id":"p2","name":"Hours"}]}
        """
        StubURLProtocol.enqueue(.json(response), for: "/panels/")
        await model.resize(panel: panel)

        let warning = try XCTUnwrap(model.warningMessage)
        XCTAssertTrue(warning.contains("2"), "the count of stranded pages must be stated")
    }

    func testResizeFailureIsReported() async throws {
        let app = await makeApp()
        let model = SettingsModel(app: app)
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        await model.resize(panel: panel)   // nothing enqueued
        XCTAssertNotNil(model.errorMessage)
    }

    func testSigningOutClearsTheCredentialAndAsksToSignIn() async {
        let app = await makeApp()
        let model = SettingsModel(app: app)
        model.signOut()
        XCTAssertEqual(app.route, .signIn)
    }

    func testForgettingTheBoardReturnsToConnect() async {
        let app = await makeApp()
        let model = SettingsModel(app: app)
        model.forget()
        XCTAssertNil(app.connection.saved)
        XCTAssertEqual(app.route, .connect)
    }

    func testPresetsCoverCommonTVSizes() {
        XCTAssertTrue(SettingsModel.presetDiagonals.contains(55))
        XCTAssertTrue(SettingsModel.presetDiagonals.contains(65))
        XCTAssertTrue(SettingsModel.presetDiagonals.contains(85))
        XCTAssertEqual(SettingsModel.presetDiagonals.first, 32)
    }

    func testScreenRenders() async {
        let app = await makeApp()
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/panels")
        RenderHarness.render(SettingsScreen().environment(app))
    }
}
