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

    // MARK: A board left on a wall

    private func freshSignage() -> SignageSettings {
        SignageSettings(defaults: UserDefaults(suiteName: "tv.signage.\(UUID().uuidString)")!)
    }

    /// The override is this TV's. Nothing about it is sent to the board:
    /// the window belongs to the panel and the web viewer reads the same
    /// field, so writing it from here would darken screens in other rooms.
    func testTheDimOverrideIsDeviceSideAndSendsNothing() async {
        let app = await makeApp()
        let signage = freshSignage()
        let model = SettingsModel(app: app, signage: signage)

        model.setAutoDimOverride(.neverDim)

        XCTAssertEqual(signage.autoDimOverride, .neverDim)
        XCTAssertEqual(model.autoDimOverride, .neverDim)
        XCTAssertTrue(StubURLProtocol.requests.filter { $0.method == "PATCH" }.isEmpty,
                      "the panel's own schedule must not be edited from the TV")
    }

    func testTheDimOverrideSurvivesReopeningSettings() async {
        let app = await makeApp()
        let signage = freshSignage()
        SettingsModel(app: app, signage: signage).setAutoDimOverride(.neverDim)
        XCTAssertEqual(SettingsModel(app: app, signage: signage).autoDimOverride, .neverDim)
    }

    /// The gap this closes: a board goes dim at ten at night and the person
    /// in front of it has no way to learn why.
    func testTheSummaryNamesThePanelAndItsWindow() async throws {
        let app = await makeApp()
        let atElevenPM = Calendar(identifier: .gregorian)
            .date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 23))!
        let model = SettingsModel(app: app, signage: freshSignage(), clock: { atElevenPM })
        model.panels = [try dimmingPanel(named: "Kitchen", start: "22:00", end: "07:00")]

        let summary = model.autoDimSummary
        XCTAssertTrue(summary.contains("Kitchen"), summary)
        XCTAssertTrue(summary.contains(SettingsModel.clockLabel("22:00")), summary)
        XCTAssertTrue(summary.contains(SettingsModel.clockLabel("07:00")), summary)
        XCTAssertTrue(summary.lowercased().contains("dimmed right now"),
                      "at 11pm inside a 22:00-07:00 window it should say so: \(summary)")

        model.setAutoDimOverride(.neverDim)
        XCTAssertFalse(model.autoDimSummary.lowercased().contains("dimmed right now"))
        XCTAssertTrue(model.autoDimSummary.contains("ignoring"), model.autoDimSummary)
    }

    /// Two of the three things that dim a wall-mounted TV are not this app.
    /// Saying so is the difference between a setting and an answer.
    func testTheSummarySaysWhenFiestaBoardIsNotTheCause() async throws {
        let app = await makeApp()
        let model = SettingsModel(app: app, signage: freshSignage())
        model.panels = [try panel(named: "Kitchen", dimming: false)]
        XCTAssertFalse(model.panels[0].autoDim.enabled)

        let summary = model.autoDimSummary
        XCTAssertTrue(summary.contains("screen saver"), summary)
        XCTAssertTrue(summary.lowercased().contains("panel protection"), summary)
    }

    func testClockLabelsAreReadableTimesNotRawStrings() {
        // Compared loosely on the separator: modern ICU puts a narrow
        // no-break space before the meridiem, which is correct typography
        // and none of this test's business.
        let evening = SettingsModel.clockLabel("22:00", locale: Locale(identifier: "en_US"))
        XCTAssertTrue(evening.hasPrefix("10:00"), evening)
        XCTAssertTrue(evening.hasSuffix("PM"), evening)

        let morning = SettingsModel.clockLabel("07:00", locale: Locale(identifier: "en_US"))
        XCTAssertTrue(morning.hasPrefix("7:00"), morning)
        XCTAssertTrue(morning.hasSuffix("AM"), morning)

        XCTAssertEqual(SettingsModel.clockLabel("nonsense"), "nonsense")
    }

    /// Off by default: it moves the picture, and most people are not running
    /// a wall display.
    func testDriftIsOffByDefaultAndOptIn() async {
        let app = await makeApp()
        let signage = freshSignage()
        let model = SettingsModel(app: app, signage: signage)
        XCTAssertFalse(model.driftEnabled)

        model.setDriftEnabled(true)
        XCTAssertTrue(signage.driftEnabled)
        XCTAssertTrue(SettingsModel(app: app, signage: signage).driftEnabled)
    }

    private func dimmingPanel(named name: String, start: String, end: String) throws -> Panel {
        try panel(named: name, dimming: true, start: start, end: end)
    }

    private func panel(named name: String, dimming: Bool,
                       start: String = "22:00", end: String = "07:00") throws -> Panel {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(Fixtures.panelJSON.utf8)) as? [String: Any])
        object["name"] = name
        object["auto_dim"] = ["enabled": dimming, "start": start, "end": end]
        return try JSONDecoder().decode(
            Panel.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testScreenRenders() async {
        let app = await makeApp()
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/api/panels")
        RenderHarness.render(SettingsScreen().environment(app))
    }
}
