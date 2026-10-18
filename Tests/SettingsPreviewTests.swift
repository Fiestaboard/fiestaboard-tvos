import XCTest
import CoreGraphics
@testable import FiestaBoardTV

@MainActor
final class SettingsPreviewTests: XCTestCase {
    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    private func makeApp() async throws -> AppModel {
        let connection = ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.settings-preview.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await connection.connect(to: URL(string: "http://host:4420")!, displayName: "Board")
        return AppModel(connection: connection)
    }

    func testSelectedPreviewPreservesRichCellsFrameDimensionsAndCode62() async throws {
        let model = SettingsModel(app: try await makeApp())
        let panel = try MatrixDisplayTests.panel(["render_style": "led_matrix"])
        model.panels = [panel, try MatrixDisplayTests.panel(["id": "other"])]
        StubURLProtocol.enqueue(.json(#"{"rows":1,"cols":2,"characters":[[62,1]],"message":"A heart","cells":[[{"type":"char","value":"a","color":"red"},{"type":"char","value":"B"}]]}"#), for: "/api/panel/")
        await model.loadPreview(for: panel)
        guard case .ready(let preview) = model.previewState(for: panel) else {
            return XCTFail("Expected the selected panel's frame")
        }
        XCTAssertEqual(preview.rows, 1)
        XCTAssertEqual(preview.cols, 2)
        XCTAssertEqual(preview.message, "A heart")
        XCTAssertEqual(preview.cells[0][0], .character("♥"))
        XCTAssertEqual(preview.richCells?[0][0].value, "a")
        XCTAssertEqual(preview.richCells?[0][0].color, "red")
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.url.path.hasPrefix("/api/panel/") }.map { $0.url.path },
                       ["/api/panel/\(panel.id)/frame"])
    }

    func testMissingBoardDoesNotRequestAFrame() async throws {
        let model = SettingsModel(app: try await makeApp())
        let panel = try MatrixDisplayTests.panel(["board_missing": true])
        await model.loadPreview(for: panel)
        XCTAssertEqual(model.previewState(for: panel), .unavailable)
        XCTAssertFalse(StubURLProtocol.requests.contains { $0.url.path.hasPrefix("/api/panel/") })
    }

    func testPreviewFailurePreservesSaveErrorAndRetryCanRecover() async throws {
        let model = SettingsModel(app: try await makeApp())
        let panel = try MatrixDisplayTests.panel()
        model.errorMessage = "Couldn't save the display style."
        await model.loadPreview(for: panel)
        XCTAssertEqual(model.previewState(for: panel), .unavailable)
        XCTAssertEqual(model.errorMessage, "Couldn't save the display style.")
        StubURLProtocol.enqueue(.json(Fixtures.frameJSON), for: "/api/panel/")
        await model.loadPreview(for: panel)
        guard case .ready(let preview) = model.previewState(for: panel) else {
            return XCTFail("Retry should recover the preview")
        }
        XCTAssertEqual(preview.message, "HI")
        XCTAssertEqual(model.errorMessage, "Couldn't save the display style.")
    }

    func testOlderSamePanelResponseCannotReplaceTheNewerFrame() async throws {
        let model = SettingsModel(app: try await makeApp())
        let panel = try MatrixDisplayTests.panel()
        let received = expectation(description: "older frame request held")
        var release: (() -> Void)?
        var held = StubURLProtocol.Stub.json(Fixtures.frameJSON)
        held.beforeReply = { reply in
            Task { @MainActor in release = reply; received.fulfill() }
        }
        StubURLProtocol.enqueue(held, for: "/api/panel/")
        let older = Task { await model.loadPreview(for: panel) }
        await fulfillment(of: [received], timeout: 2)
        XCTAssertEqual(model.previewState(for: panel), .loading)
        StubURLProtocol.enqueue(.json(#"{"rows":1,"cols":1,"characters":[[2]],"message":"New frame"}"#), for: "/api/panel/")
        await model.loadPreview(for: panel)
        release?()
        await older.value
        guard case .ready(let preview) = model.previewState(for: panel) else {
            return XCTFail("Expected the newer preview")
        }
        XCTAssertEqual(preview.message, "New frame")
    }

    func testChangingSelectionRejectsThePreviousPanelsLateFrame() async throws {
        let model = SettingsModel(app: try await makeApp())
        let first = try MatrixDisplayTests.panel()
        let second = try MatrixDisplayTests.panel(["id": "second"])
        let received = expectation(description: "first panel frame held")
        var release: (() -> Void)?
        var held = StubURLProtocol.Stub.json(Fixtures.frameJSON)
        held.beforeReply = { reply in
            Task { @MainActor in release = reply; received.fulfill() }
        }
        StubURLProtocol.enqueue(held, for: "/api/panel/")
        let older = Task { await model.loadPreview(for: first) }
        await fulfillment(of: [received], timeout: 2)
        StubURLProtocol.enqueue(.json(Fixtures.emptyFrameJSON), for: "/api/panel/")
        await model.loadPreview(for: second)
        release?()
        await older.value
        guard case .ready(let preview) = model.previewState(for: second) else {
            return XCTFail("Expected the selected panel to remain visible")
        }
        XCTAssertNil(preview.message)
        XCTAssertEqual(preview.rows, 12)
    }

    func testCancelledSourceTaskDoesNotPublishAFrameOrNavigate() async throws {
        let app = try await makeApp()
        let model = SettingsModel(app: app)
        let originalRoute = app.route
        let panel = try MatrixDisplayTests.panel()
        let received = expectation(description: "frame request held")
        var held = StubURLProtocol.Stub.json(Fixtures.frameJSON)
        held.beforeReply = { _ in Task { @MainActor in received.fulfill() } }
        StubURLProtocol.enqueue(held, for: "/api/panel/")
        let loading = Task { await model.loadPreview(for: panel) }
        await fulfillment(of: [received], timeout: 2)
        loading.cancel()
        await loading.value
        XCTAssertEqual(model.previewState(for: panel), .unavailable)
        XCTAssertEqual(app.route, originalRoute)
        XCTAssertNil(model.errorMessage)
    }

    func testUnauthorizedPreviewRequiresSignIn() async throws {
        let app = try await makeApp()
        let model = SettingsModel(app: app)
        let panel = try MatrixDisplayTests.panel()
        StubURLProtocol.enqueue(.json(#"{"detail":"Unauthorized"}"#, status: 401), for: "/api/panel/")
        await model.loadPreview(for: panel)
        XCTAssertEqual(app.route, .signIn)
        XCTAssertEqual(model.previewState(for: panel), .unavailable)
    }

    func testCalibrationSaveUpdatesTheSelectedPanelFromTheResponse() async throws {
        let model = SettingsModel(app: try await makeApp())
        let panel = try MatrixDisplayTests.panel()
        model.panels = [panel]
        model.setCalibration(1.1, for: panel)
        let saved = try MatrixDisplayTests.panel(["calibration_scale": 1.1])
        let json = String(decoding: try JSONEncoder().encode(saved), as: UTF8.self)
        StubURLProtocol.enqueue(.json("{\"panel\":\(json)}"), for: "/api/panels/")
        let savedSuccessfully = await model.saveCalibration(panel: panel)
        XCTAssertTrue(savedSuccessfully)
        XCTAssertEqual(model.panels.first?.calibrationScale, 1.1)
    }

    func testRejectedOrFailedCalibrationDoesNotReportSuccess() async throws {
        let model = SettingsModel(app: try await makeApp())
        let matrix = try MatrixDisplayTests.matrixPanel()
        model.panels = [matrix]
        let rejected = await model.saveCalibration(panel: matrix)
        XCTAssertFalse(rejected)
        XCTAssertFalse(StubURLProtocol.requests.contains { $0.method == "PATCH" })
        let flap = try MatrixDisplayTests.panel()
        model.panels = [flap]
        let failed = await model.saveCalibration(panel: flap)
        XCTAssertFalse(failed)
        XCTAssertNotNil(model.errorMessage)
    }

    func testCancelledPanelListLoadDoesNotPublishOrNavigate() async throws {
        let app = try await makeApp()
        let model = SettingsModel(app: app)
        let originalRoute = app.route
        let received = expectation(description: "panel list held")
        var held = StubURLProtocol.Stub.json(Fixtures.panelsList)
        held.beforeReply = { _ in Task { @MainActor in received.fulfill() } }
        StubURLProtocol.enqueue(held, for: "/api/panels")
        let loading = Task { await model.load() }
        await fulfillment(of: [received], timeout: 2)
        loading.cancel()
        await loading.value
        XCTAssertFalse(model.hasLoaded)
        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(model.panels.isEmpty)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(app.route, originalRoute)
    }

    func testNewerPanelListWinsWhenAnEarlierLoadFinishesLate() async throws {
        let model = SettingsModel(app: try await makeApp())
        let received = expectation(description: "old panel list held")
        var release: (() -> Void)?
        var held = StubURLProtocol.Stub.json(Fixtures.panelsList)
        held.beforeReply = { reply in
            Task { @MainActor in release = reply; received.fulfill() }
        }
        StubURLProtocol.enqueue(held, for: "/api/panels")
        let older = Task { await model.load() }
        await fulfillment(of: [received], timeout: 2)
        StubURLProtocol.enqueue(.json(#"{"panels":[],"total":0}"#), for: "/api/panels")
        await model.load()
        release?()
        await older.value
        XCTAssertTrue(model.hasLoaded)
        XCTAssertTrue(model.panels.isEmpty)
        XCTAssertFalse(model.isLoading)
    }

    func testNormalPreviewFitsTheFrameRegardlessOfSavedCalibration() throws {
        let preview = PanelPreview(rows: 1, cols: 2, cells: [], message: nil)
        for savedScale in [0.85, 1.15] {
            let panel = try MatrixDisplayTests.panel(["calibration_scale": savedScale])
            let layout = try XCTUnwrap(SettingsPanelPreview.layout(
                panel: panel, preview: preview, in: CGSize(width: 960, height: 540),
                calibrationScale: nil))
            // Two 0.7-wide flaps plus one 0.145 gutter fit vertically first.
            XCTAssertEqual(layout.tileHeight, 540, accuracy: 0.001)
            XCTAssertEqual(layout.width, 834.3, accuracy: 0.001)
        }
    }

    func testCalibrationUsesTheFullViewportAndTracksTheDraftScale() throws {
        let panel = try MatrixDisplayTests.panel()
        let preview = PanelPreview(rows: 12, cols: 30, cells: [], message: nil)
        let full = CGSize(width: 1920, height: 1080)
        let baseline = try XCTUnwrap(SettingsPanelPreview.layout(
            panel: panel, preview: preview, in: full, calibrationScale: 1))
        let enlarged = try XCTUnwrap(SettingsPanelPreview.layout(
            panel: panel, preview: preview, in: full, calibrationScale: 1.15))
        let halfViewport = try XCTUnwrap(SettingsPanelPreview.layout(
            panel: panel, preview: preview, in: CGSize(width: 960, height: 540),
            calibrationScale: 1))
        XCTAssertEqual(enlarged.tileHeight / baseline.tileHeight, 1.15, accuracy: 0.0001)
        XCTAssertEqual(baseline.tileHeight / halfViewport.tileHeight, 2, accuracy: 0.0001)
        let viewer = try BoardLayout.fitting(
            rows: 12, cols: 30, cells: [], in: full, mode: .trueScale,
            diagonalInches: 65, calibration: 1, colPitchIn: 24.5 / 15)
        XCTAssertEqual(baseline.tileHeight, viewer.tileHeight, accuracy: 0.0001)
    }
}
