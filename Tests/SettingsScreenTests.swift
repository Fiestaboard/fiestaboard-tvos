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

    func testMatrixTransitionStylePersistsLocallyAndReachesANewViewer() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let signage = SignageSettings(defaults: defaults)
        let app = await makeApp()
        let model = SettingsModel(app: app, signage: signage)
        XCTAssertEqual(model.matrixTransitionStyle, .characterWipe)
        let requestCount = StubURLProtocol.requests.count
        for style in MatrixTransitionStyle.allCases {
            model.setMatrixTransitionStyle(style)
            XCTAssertEqual(model.matrixTransitionStyle, style, "the picker must show the choice immediately")
            XCTAssertEqual(defaults.string(forKey: "fiestaboard.matrix.transitionStyle"), style.rawValue)
            let restored = SignageSettings(defaults: defaults)
            XCTAssertEqual(SettingsModel(app: app, signage: restored).matrixTransitionStyle, style)
            XCTAssertEqual(ViewerModel(app: app, ref: "1", signage: restored).matrixTransitionStyle, style)
        }
        XCTAssertEqual(StubURLProtocol.requests.count, requestCount,
                       "Choosing an effect on this Apple TV must not edit the shared panel")
    }

    func testUnknownMatrixTransitionPreferenceFallsBackWithoutChangingSizing() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let signage = SignageSettings(defaults: defaults)
        signage.matrixPresentation = .init(sizing: .trueSize, diagonalInches: 75, pitchMillimeters: 5)
        XCTAssertEqual(signage.matrixTransitionStyle, .characterWipe)
        defaults.set("futureEffect", forKey: "fiestaboard.matrix.transitionStyle")
        XCTAssertEqual(SignageSettings(defaults: defaults).matrixTransitionStyle, .characterWipe)
        signage.matrixTransitionStyle = .rowScan
        XCTAssertEqual(signage.matrixPresentation, .init(sizing: .trueSize, diagonalInches: 75, pitchMillimeters: 5))
    }

    func testMatrixSizingPersistsOnThisTVAndReachesTheViewerWithoutServerWrites() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let signage = SignageSettings(defaults: defaults)
        let app = await makeApp()
        let model = SettingsModel(app: app, signage: signage)
        XCTAssertEqual(model.matrixPresentation.sizing, .fillTV)
        model.setMatrixSizing(.trueSize)
        model.setMatrixDiagonal(75)
        model.setMatrixPitch(5)
        let restored = SettingsModel(app: app, signage: SignageSettings(defaults: defaults))
        XCTAssertEqual(restored.matrixPresentation.sizing, .trueSize)
        XCTAssertEqual(restored.matrixPresentation.diagonalInches, 75)
        XCTAssertEqual(restored.matrixPresentation.pitchMillimeters, 5)
        let viewer = ViewerModel(app: app, ref: "1", signage: SignageSettings(defaults: defaults))
        XCTAssertEqual(viewer.matrixPresentation, restored.matrixPresentation)
        XCTAssertFalse(StubURLProtocol.requests.contains { $0.method == "PATCH" })
    }

    func testInvalidStoredMatrixSizingUsesSafeDefaults() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(Data(#"{"sizing":"future","diagonalInches":-1,"pitchMillimeters":0}"#.utf8), forKey: "fiestaboard.matrix.presentation")
        let settings = SignageSettings(defaults: defaults)
        XCTAssertEqual(settings.matrixPresentation.sizing, .fillTV)
        XCTAssertGreaterThan(settings.matrixPresentation.diagonalInches, 0)
        XCTAssertGreaterThan(settings.matrixPresentation.pitchMillimeters, 0)
    }

    func testRenderStyleSavesOnlyStyleAndUpdatesLoadedPanel() async throws {
        let model = SettingsModel(app: await makeApp())
        let panel = try MatrixDisplayTests.panel(["render_style": "split_flap"])
        model.panels = [panel]
        let updated = try MatrixDisplayTests.matrixPanel()
        let json = String(decoding: try JSONEncoder().encode(updated), as: UTF8.self)
        StubURLProtocol.enqueue(.json("{\"panel\":\(json)}"), for: "/api/panels/")
        await model.setRenderStyle(.ledMatrix, for: panel)
        XCTAssertEqual(model.renderStyle(for: panel), .ledMatrix, "stale row reads the saved state")
        XCTAssertTrue(model.flapPanels.isEmpty)
        let patch = try XCTUnwrap(StubURLProtocol.requests.first { $0.method == "PATCH" })
        let fields = try JSONSerialization.jsonObject(with: XCTUnwrap(patch.body)) as! [String: String]
        XCTAssertEqual(fields, ["render_style": "led_matrix"])
    }

    func testRenderStyleFailureKeepsSavedStyleAndReportsError() async throws {
        let model = SettingsModel(app: await makeApp())
        let panel = try MatrixDisplayTests.panel(["render_style": "split_flap"])
        model.panels = [panel]
        await model.setRenderStyle(.ledMatrix, for: panel)
        XCTAssertEqual(model.renderStyle(for: panel), .splitFlap)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.flapPanels.map(\.id), [panel.id])
        XCTAssertFalse(model.isSavingRenderStyle(for: panel))
    }

    func testLegacyPanelCannotSendRenderStylePatch() async throws {
        let model = SettingsModel(app: await makeApp())
        let panel = try MatrixDisplayTests.panel()
        model.panels = [panel]
        XCTAssertTrue(model.stylePanels.isEmpty)
        await model.setRenderStyle(.ledMatrix, for: panel)
        XCTAssertFalse(StubURLProtocol.requests.contains { $0.method == "PATCH" })
    }

    func testMatrixPanelRefusesFlapActionsEvenFromAStaleRow() async throws {
        let model = SettingsModel(app: await makeApp())
        let stale = try MatrixDisplayTests.panel(["render_style": "split_flap"])
        model.panels = [try MatrixDisplayTests.matrixPanel()]
        await model.resize(panel: stale)
        await model.saveCalibration(panel: stale)
        XCTAssertFalse(StubURLProtocol.requests.contains { $0.method == "PATCH" })
    }

    func testPendingStyleSaveBlocksCompetingFlapWrites() async throws {
        let model = SettingsModel(app: await makeApp())
        let panel = try MatrixDisplayTests.panel(["render_style": "split_flap"])
        model.panels = [panel]
        let updated = try MatrixDisplayTests.matrixPanel()
        let json = String(decoding: try JSONEncoder().encode(updated), as: UTF8.self)
        let received = expectation(description: "style PATCH held before response")
        var release: (() -> Void)?
        var stub = StubURLProtocol.Stub.json("{\"panel\":\(json)}")
        stub.beforeReply = { reply in
            Task { @MainActor in release = reply; received.fulfill() }
        }
        StubURLProtocol.enqueue(stub, for: "/api/panels/")
        let saving = Task { await model.setRenderStyle(.ledMatrix, for: panel) }
        await fulfillment(of: [received], timeout: 2)
        XCTAssertTrue(model.isSavingRenderStyle(for: panel))
        await model.resize(panel: panel)
        await model.saveCalibration(panel: panel)
        await model.setAnimationEnabled(true, for: panel)
        release?()
        await saving.value
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.method == "PATCH" }.count, 1)
        XCTAssertEqual(model.renderStyle(for: panel), .ledMatrix)
    }

    func testPendingFlapWriteBlocksStyleSaveUntilItsResponse() async throws {
        let model = SettingsModel(app: await makeApp())
        let panel = try MatrixDisplayTests.panel(["render_style": "split_flap"])
        model.panels = [panel]
        let json = String(decoding: try JSONEncoder().encode(panel), as: UTF8.self)
        let received = expectation(description: "animation PATCH held before response")
        var release: (() -> Void)?
        var stub = StubURLProtocol.Stub.json("{\"panel\":\(json)}")
        stub.beforeReply = { reply in
            Task { @MainActor in release = reply; received.fulfill() }
        }
        StubURLProtocol.enqueue(stub, for: "/api/panels/")
        let saving = Task { await model.setAnimationEnabled(true, for: panel) }
        await fulfillment(of: [received], timeout: 2)
        await model.setRenderStyle(.ledMatrix, for: panel)
        release?()
        await saving.value
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.method == "PATCH" }.count, 1)
        XCTAssertEqual(model.renderStyle(for: panel), .splitFlap)
    }

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

    func testResizeUpdatesOnlyItsPanelAndPreservesAnotherSavedStyle() async throws {
        let model = SettingsModel(app: await makeApp())
        let first = try MatrixDisplayTests.panel(["id": "first", "render_style": "split_flap"])
        let second = try MatrixDisplayTests.panel(["id": "second", "render_style": "led_matrix"])
        model.panels = [first, second]
        let resized = try MatrixDisplayTests.panel(["id": "first", "render_style": "split_flap", "rows": 18, "cols": 45])
        let data = try JSONEncoder().encode(resized)
        StubURLProtocol.enqueue(.json("{\"panel\":\(String(decoding: data, as: UTF8.self))}"), for: "/api/panels/first")
        // A whole-list refresh can have been cached before the other style
        // save. A resize response already contains the updated panel.
        let staleSecond = try MatrixDisplayTests.panel(["id": "second", "render_style": "split_flap"])
        let staleList = String(decoding: try JSONEncoder().encode([resized, staleSecond]), as: UTF8.self)
        StubURLProtocol.enqueue(.json("{\"panels\":\(staleList)}"), for: "/api/panels")
        await model.resize(panel: first)
        XCTAssertEqual(model.panels.first?.rows, 18)
        XCTAssertEqual(model.panels.first?.cols, 45)
        XCTAssertEqual(model.renderStyle(for: second), .ledMatrix)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.method == "GET" && $0.url.path == "/api/panels" }.count, 0)
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
        model.hasLoaded = true

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
        model.hasLoaded = true
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

    /// The failure that made this screen lie. Every error path in `load()`
    /// leaves `panels` empty, which used to read as "nothing on this board
    /// dims" — told confidently to someone standing in front of a board that
    /// had gone dim, by the screen written to explain exactly that.
    func testAFailedLoadLeavesTheDimScheduleUnknownRatherThanDenyingIt() async {
        let app = await makeApp()
        let model = SettingsModel(app: app, signage: freshSignage())

        await model.load()   // nothing enqueued

        XCTAssertFalse(model.hasLoaded)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.autoDimSummary, SettingsModel.dimScheduleUnknown)
        XCTAssertFalse(model.autoDimSummary.contains("No panel on this board is set to dim"),
                       model.autoDimSummary)
    }

    func testTheSummarySaysItIsStillCheckingWhileTheListIsInFlight() async {
        let app = await makeApp()
        let model = SettingsModel(app: app, signage: freshSignage())
        model.isLoading = true
        XCTAssertEqual(model.autoDimSummary, SettingsModel.dimScheduleLoading)
    }

    /// The flag is the point: a board that genuinely has no panels must keep
    /// the old, correct answer. Keying on `panels.isEmpty` would not.
    func testABoardWithGenuinelyNoPanelsStillSaysFiestaBoardIsNotTheCause() async {
        let app = await makeApp()
        let model = SettingsModel(app: app, signage: freshSignage())
        StubURLProtocol.enqueue(.json(#"{"panels":[],"total":0}"#), for: "/api/panels")

        await model.load()

        XCTAssertTrue(model.hasLoaded)
        XCTAssertTrue(model.panels.isEmpty)
        XCTAssertTrue(model.autoDimSummary.contains("screen saver"), model.autoDimSummary)
    }

    /// A bare `catch` blamed the resize for everything, so a board that
    /// answered with an error looked the same as one that refused the grid.
    func testResizeFailureRepeatsWhatTheBoardSaid() async throws {
        let app = await makeApp()
        let model = SettingsModel(app: app)
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))

        StubURLProtocol.enqueue(.json(#"{"detail":"nope"}"#, status: 400), for: "/api/panels/")
        await model.resize(panel: panel)

        let message = try XCTUnwrap(model.errorMessage)
        XCTAssertTrue(message.hasPrefix("Couldn't resize this panel."), message)
        XCTAssertTrue(message.contains("400"), message)
    }

    func testAnInvalidCustomSizeIsRejectedBeforeAnyRequest() async throws {
        let app = await makeApp()
        let model = SettingsModel(app: app)
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        model.setCustomDiagonal("not a size")

        await model.resize(panel: panel)

        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(StubURLProtocol.requests.filter { $0.method == "PATCH" }.isEmpty)
    }

    // MARK: What the copy is allowed to promise

    /// The privacy statement must not out-promise the app.
    ///
    /// It used to open "Nothing you enter here leaves this Apple TV" while
    /// `SignInScreen.credentialsFooter`, two screens away, said the password
    /// crosses an unencrypted LAN on every sign-in — which it does. Guideline
    /// 5.1.1(i) is why the section exists, and a claim the app contradicts
    /// elsewhere is worse than no claim at all. The honest scope is servers
    /// and third parties.
    func testThePrivacyStatementDoesNotClaimNothingLeavesTheDevice() {
        let body = SettingsScreen.privacyBody
        XCTAssertFalse(body.contains("leaves this Apple TV"), body)
        XCTAssertFalse(body.lowercased().contains("never leaves"), body)
        XCTAssertFalse(body.lowercased().contains("stays on this apple tv"), body)
        XCTAssertTrue(body.contains("FiestaBoard's servers"), body)
        XCTAssertTrue(body.contains("third party"), body)
        XCTAssertTrue(body.contains("the board you chose"), body)
    }

    /// The copy and the parser have to agree on what a board can be.
    ///
    /// The statement used to read "to the board you chose, on your own local
    /// network, and nowhere else". `ManualAddress.parse` accepts an explicit
    /// `https://` address on purpose, and `ConnectModel` advertises that path
    /// in the error it shows when parsing fails — so for anyone who typed a
    /// remote board the app promised a scope it does not keep. The claim that
    /// survives both paths is about who receives the data.
    func testThePrivacyStatementIsNotScopedToTheLocalNetwork() throws {
        let remote = try XCTUnwrap(ManualAddress.parse("https://board.example.com"))
        XCTAssertEqual(remote.scheme, "https")
        XCTAssertEqual(remote.host(), "board.example.com",
                       "a typed https board is supported and need not be on this network")

        let body = SettingsScreen.privacyBody.lowercased()
        XCTAssertFalse(body.contains("local network"), body)
        XCTAssertFalse(body.contains("same network"), body)
        XCTAssertFalse(body.contains("this network"), body)
        XCTAssertFalse(body.contains("never leaves your network"), body)
    }

    /// The other half of the same rule: dropping the network scope must not
    /// leave the section vague. The recipient claim is the reassuring part a
    /// 5.1.1(i) reviewer reads, and a broadening — another recipient, or a
    /// "we may share" hedge — has to fail here.
    func testThePrivacyStatementNamesTheBoardAsTheOnlyRecipient() {
        let body = SettingsScreen.privacyBody
        XCTAssertTrue(body.contains("the board you chose and to no one else"), body)
        XCTAssertTrue(body.contains("the address you typed"),
                      "the typed-address path is one of the two ways to reach a board: \(body)")
        XCTAssertFalse(body.lowercased().contains("may share"), body)
        XCTAssertFalse(body.lowercased().contains("such as"), body)
    }

    /// The Keychain sentence is only honest next to where the password goes.
    /// Stating storage and saying nothing about transmission is how the old
    /// copy read as "it never travels".
    func testThePrivacyStatementSaysThePasswordIsSentToTheBoard() {
        let body = SettingsScreen.privacyBody
        XCTAssertTrue(body.contains("Keychain"), body)
        XCTAssertTrue(body.contains("sent to that board"), body)
    }

    /// `CFBundleDisplayName` is exactly "FiestaBoard", so "in the FiestaBoard
    /// app" sends the reader to the icon they are already inside. The panel's
    /// schedule is edited on the board's own web page. Same rule, and same
    /// wording, as `AppModelTests`' setup-required message.
    func testTheDimSummaryNamesTheBoardsWebPageRatherThanThisApp() async throws {
        let app = await makeApp()
        let model = SettingsModel(app: app, signage: freshSignage())
        model.panels = [try dimmingPanel(named: "Kitchen", start: "22:00", end: "07:00")]
        model.hasLoaded = true

        let summary = model.autoDimSummary
        XCTAssertFalse(summary.contains("in the FiestaBoard app"),
                       "this IS the FiestaBoard app: \(summary)")
        XCTAssertTrue(summary.contains("board's web page"), summary)
    }

    func testTheStrandedPagesWarningNamesTheBoardsWebPageRatherThanThisApp() async throws {
        let app = await makeApp()
        let model = SettingsModel(app: app)
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))

        let response = """
        {"status":"success","panel":\(Fixtures.panelJSON),
         "incompatible_references":[{"type":"page","id":"p1","name":"Welcome"}]}
        """
        StubURLProtocol.enqueue(.json(response), for: "/api/panels/")
        await model.resize(panel: panel)

        let warning = try XCTUnwrap(model.warningMessage)
        XCTAssertFalse(warning.contains("in the FiestaBoard app"),
                       "this IS the FiestaBoard app: \(warning)")
        XCTAssertTrue(warning.contains("board's web page"), warning)
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

    /// The Reduce Motion branch swaps the animation footer and disables the
    /// switches. It is a separate `body` path and this is the only thing that
    /// walks it — `SettingsScreen.swift` has blown the type checker's budget
    /// once already, and an unrendered branch is where that hides.
    func testScreenRendersWithReduceMotionOn() async {
        let app = await makeApp()
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/api/panels")
        RenderHarness.render(
            SettingsScreen()
                .environment(app)
                // `\.accessibilityReduceMotion` is get-only; `SwiftUICore`
                // exposes the writable half as the underscored key path, and
                // it is the only way to drive this branch without a device
                // with the setting turned on.
                .environment(\._accessibilityReduceMotion, true))
    }

    /// Guards the line above. `\._accessibilityReduceMotion` is the writable
    /// half of a value `SettingsScreen` reads through the public, read-only
    /// `\.accessibilityReduceMotion`; if the two ever stop being the same
    /// storage the test above would quietly render the ordinary branch and
    /// still pass.
    func testTheReduceMotionInjectionReachesTheReadOnlyKeyPath() {
        var seen: Bool?
        RenderHarness.render(
            ReduceMotionProbe { seen = $0 }
                .environment(\._accessibilityReduceMotion, true))
        XCTAssertEqual(seen, true)
    }
}

private struct ReduceMotionProbe: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let report: (Bool) -> Void

    var body: some View {
        Color.clear.onAppear { report(reduceMotion) }
    }
}
