import SwiftUI
import XCTest
@testable import FiestaBoardTV

@MainActor
final class OLEDCareIntegrationTests: XCTestCase {
    private func app() -> AppModel {
        let defaults = UserDefaults(suiteName: "oled.integration.\(UUID().uuidString)")!
        return AppModel(connection: ConnectionStore(defaults: defaults, credentials: InMemoryCredentialStore()),
                        oledStore: OLEDCareStore(defaults: defaults))
    }
    func testScreensaverPreferenceAndBackgroundReleaseIdleRequest() {
        let app = app(); var requests: [Bool] = []
        app.screenAwake.sink = { requests.append($0) }
        app.openPanel(ref: "1")
        XCTAssertTrue(app.screenAwake.isHeld)
        app.screenAwake.onBackground?()
        XCTAssertFalse(app.screenAwake.isHeld)
        app.screenAwake.onForeground?()
        XCTAssertTrue(app.screenAwake.isHeld)
        var c = app.oledCare; c.allowScreensaver = true; app.saveOLEDCare(c)
        XCTAssertFalse(app.screenAwake.isHeld)
        app.screenAwake.onForeground?()
        XCTAssertFalse(app.screenAwake.isHeld)
        XCTAssertEqual(requests.suffix(2), [false, false])
    }
    func testUnavailableSnapshotDimsAndRecoveryRestoresOutput() {
        let app = app(); app.screenAwake.sink = { _ in }
        var c = app.oledCare; c.disconnected = .dim; c.disconnectDelay = 1; c.brightness = 50
        app.saveOLEDCare(c); app.openPanel(ref: "1")
        let viewer = ViewerModel(app: app, ref: "1")
        viewer.apply(.empty)
        let now = ProcessInfo.processInfo.systemUptime
        app.updateOLEDCare(now: now + 60)
        XCTAssertEqual(app.oledOutput.brightness, 0.175)
        viewer.apply(PanelSnapshot(panel: nil, cells: [], rows: 0, cols: 0, connection: .live, dimmed: false, deleted: false))
        XCTAssertEqual(app.oledOutput.brightness, 0.5)
    }
    func testRestRendersOnlyOpaqueBlackAndWakePressIsConsumed() throws {
        let app = app(); app.screenAwake.sink = { _ in }
        var c = app.oledCare; c.restEnabled = true
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let minute = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        c.restStart = minute; c.restEnd = (minute + 60) % 1440
        app.saveOLEDCare(c); app.openPanel(ref: "1")
        let viewer = ViewerModel(app: app, ref: "1")
        viewer.showOverlay(); viewer.resizeOfferVisible = true
        let image = RenderHarness.image(ViewerScreen(ref: "1", model: viewer).environment(app))
        XCTAssertTrue(app.oledOutput.resting)
        XCTAssertFalse(app.screenAwake.isHeld)
        for y in stride(from: 0, to: 1080, by: 60) {
            for x in stride(from: 0, to: 1920, by: 60) {
                let pixel = try XCTUnwrap(image.pixel(x: x, y: y))
                XCTAssertLessThanOrEqual(pixel.r, 2); XCTAssertLessThanOrEqual(pixel.g, 2)
                XCTAssertLessThanOrEqual(pixel.b, 2); XCTAssertGreaterThanOrEqual(pixel.a, 250)
            }
        }
        XCTAssertTrue(app.interactWithOLED())
        XCTAssertFalse(app.oledOutput.resting)
        XCTAssertEqual(app.route, .viewer("1"))
        XCTAssertFalse(app.interactWithOLED())
    }
    func testAnswerAndAllSettingsRemainDeviceLocalAcrossDisconnect() {
        let app = app()
        var c = app.oledCare; c.answer = .yes; c.brightness = 50
        c.allowScreensaver = true; c.rotationEnabled = true; c.placements = [.upperLeft, .lowerRight]
        app.saveOLEDCare(c)
        app.disconnect()
        XCTAssertEqual(app.oledCare, c)
    }
}
