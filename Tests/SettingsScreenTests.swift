import SwiftUI
import Observation
import XCTest
@testable import FiestaBoardTV

@MainActor
final class SettingsScreenTests: XCTestCase {

    private func makeApp() async -> AppModel {
        let app = AppModel(connection: ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.settings.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) }))
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
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

    func testDefaultPanelSelectionNotifiesTheSettingsScreen() async {
        let app = await makeApp()
        let model = SettingsModel(app: app)
        let changed = expectation(description: "default panel selection changed")
        withObservationTracking({ _ = model.defaultPanelRef }, onChange: { changed.fulfill() })

        model.setDefaultPanel("abc123def456")
        await fulfillment(of: [changed], timeout: 1)
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

    func testCustomDiagonalUpdatesThePreview() async {
        let model = SettingsModel(app: await makeApp())
        model.setCustomDiagonal("58.5")
        XCTAssertEqual(model.resizeDiagonal, 58.5)
        XCTAssertNotEqual(model.previewGrid, "—")
        model.setCustomDiagonal("not a size")
        XCTAssertEqual(model.previewGrid, "—")
    }

    func testCalibrationIsLimitedToFifteenPercentAndPatched() async throws {
        let app = await makeApp()
        let model = SettingsModel(app: app)
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        model.setCalibration(1.5, for: panel)
        XCTAssertEqual(model.calibration(for: panel), 1.15, accuracy: 0.0001)

        StubURLProtocol.enqueue(.json(#"{"status":"success","panel":\#(Fixtures.panelJSON)}"#), for: "/api/panels/")
        await model.saveCalibration(panel: panel)
        let patch = try XCTUnwrap(StubURLProtocol.requests.first { $0.method == "PATCH" })
        let body = try XCTUnwrap(patch.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(try XCTUnwrap(json["calibration_scale"] as? Double), 1.15, accuracy: 0.0001)
    }

    func testResizePatchesTheDiagonal() async throws {
        let app = await makeApp()
        let model = SettingsModel(app: app)
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))

        StubURLProtocol.enqueue(.json(#"{"status":"success","panel":\#(Fixtures.panelJSON)}"#),
                                for: "/api/panels/")
        model.resizeDiagonal = 85
        await model.resize(panel: panel)

        let patch = StubURLProtocol.requests.first { $0.method == "PATCH" }
        let body = try XCTUnwrap(patch?.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["screen_diagonal_inches"] as? Double, 85)
    }

    func testAnimationTogglePatchesOnlyTheSelectedPanel() async throws {
        let app = await makeApp()
        let model = SettingsModel(app: app)
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        model.panels = [panel]
        var updated = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(Fixtures.panelJSON.utf8)) as? [String: Any])
        updated["animations_enabled"] = true
        let response = ["panel": updated]
        let data = try JSONSerialization.data(withJSONObject: response)
        StubURLProtocol.enqueue(.json(String(decoding: data, as: UTF8.self)), for: "/api/panels/")

        await model.setAnimationEnabled(true, for: panel)

        let patch = try XCTUnwrap(StubURLProtocol.requests.first { $0.method == "PATCH" })
        let body = try XCTUnwrap(patch.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["animations_enabled"] as? Bool, true)
        XCTAssertEqual(json.count, 1)
        XCTAssertEqual(model.panels.first?.animationsEnabled, true)
    }

    /// The row must read the loaded list, not a Panel value captured when
    /// the row was built. A captured copy goes stale the moment anything
    /// updates the list, and the switch then sits on the old state forever.
    func testAnimationStateIsReadFromTheLoadedListNotACapturedCopy() async throws {
        let app = await makeApp()
        let model = SettingsModel(app: app)
        let stale = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        XCTAssertFalse(stale.animationsEnabled)

        var enabled = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(Fixtures.panelJSON.utf8)) as? [String: Any])
        enabled["animations_enabled"] = true
        let fresh = try JSONDecoder().decode(
            Panel.self, from: JSONSerialization.data(withJSONObject: enabled))
        model.panels = [fresh]

        XCTAssertTrue(model.animationEnabled(for: stale),
                      "asking with a stale copy should still report the loaded state")
    }

    /// A switch on a TV must move when it is pressed. Waiting for a network
    /// round trip before it moves reads as "the control does not work".
    func testTheAnimationSwitchMovesBeforeTheSaveCompletes() async throws {
        let app = await makeApp()
        let model = SettingsModel(app: app)
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        model.panels = [panel]
        XCTAssertFalse(model.animationEnabled(for: panel))

        // Nothing enqueued, so the save fails — but only after a moment.
        let saving = Task { await model.setAnimationEnabled(true, for: panel) }
        await Task.yield()
        XCTAssertTrue(model.animationEnabled(for: panel),
                      "the switch should show the new state while the save is in flight")

        await saving.value
        XCTAssertFalse(model.animationEnabled(for: panel),
                       "a save that failed must put the switch back")
        XCTAssertNotNil(model.errorMessage)
    }

    func testResizeOfAPortraitPanelSendsThePreviewedTVAspect() async throws {
        let app = await makeApp()
        let model = SettingsModel(app: app)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(Fixtures.panelJSON.utf8)) as? [String: Any])
        object["screen_aspect_w"] = 9.0
        object["screen_aspect_h"] = 16.0
        let panel = try JSONDecoder().decode(Panel.self, from: JSONSerialization.data(withJSONObject: object))
        model.resizeDiagonal = 85
        XCTAssertEqual(model.previewGrid, "45 × 18")

        StubURLProtocol.enqueue(.json(#"{"status":"success","panel":\#(Fixtures.panelJSON)}"#), for: "/api/panels/")
        await model.resize(panel: panel)

        let patch = try XCTUnwrap(StubURLProtocol.requests.first { $0.method == "PATCH" })
        let body = try XCTUnwrap(patch.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["screen_aspect_w"] as? Double, 16)
        XCTAssertEqual(json["screen_aspect_h"] as? Double, 9)
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
        StubURLProtocol.enqueue(.json(response), for: "/api/panels/")
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
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/api/panels")
        RenderHarness.render(SettingsScreen().environment(app))
    }
}
