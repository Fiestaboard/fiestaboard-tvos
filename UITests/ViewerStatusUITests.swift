import XCTest

/// A6b on a device-shaped run: the chip comes from the hub's status, is never
/// a focus target, and an outage reads "Hub unreachable", then "Reconnected".
@MainActor
final class ViewerStatusUITests: XCTestCase {
    private var server: FixtureHTTPServer?

    override func tearDown() {
        server = nil
        super.tearDown()
    }

    /// An override with no end, so the copy is fixed: "Holds until canceled".
    private static let override = #"{"mode":"override","schedule_enabled":false,"override_active":true,"override_expires_at":null,"override_started_at":"2026-11-08T02:18:00+00:00","silenced":false,"silenced_until":null,"silence_mode":null,"paused":false,"next_change_at":null,"next_change_reason":null}"#

    private func launch() throws -> XCUIApplication {
        let frameLoaded = expectation(description: "The viewer requested its frame")
        let server = try FixtureHTTPServer(onFrame: { frameLoaded.fulfill() })
        server.setPanelStatus(Self.override)
        self.server = server
        let app = XCUIApplication()
        let saved = #"{"host":"http://127.0.0.1:\#(server.port)","displayName":"Test Board","defaultPanelRef":"1"}"#
        let encoded = Data(saved.utf8).map { String(format: "%02x", $0) }.joined()
        app.launchArguments = ["-fiestaboard.connection", "<\(encoded)>", "-fiestaboard.signedOut", "NO"]
        app.launch()
        wait(for: [frameLoaded], timeout: 10)
        return app
    }

    private func chip(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "status-chip").firstMatch
    }

    private func waitForChip(_ app: XCUIApplication, label: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        let element = app.descendants(matching: .any).matching(identifier: "status-chip").matching(predicate).firstMatch
        return element.waitForExistence(timeout: timeout)
    }

    func testTheChipShowsTheHubStatusAndIsNeverFocused() throws {
        let app = try launch()
        defer { app.terminate() }
        XCTAssertTrue(waitForChip(app, label: "Override, Holds until canceled", timeout: 5),
                      "a new status shows the chip on its own")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Panels"].waitForExistence(timeout: 3))
        XCTAssertTrue(waitForChip(app, label: "Override, Holds until canceled", timeout: 3), "the chip sits in the bar")
        // The chip is left of Panels in the bar; a press left must not land on it.
        XCUIRemote.shared.press(.left)
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertTrue(app.buttons["Panels"].hasFocus, "read-only: the chip is never a focus target")
        XCTAssertFalse(chip(app).hasFocus)
    }

    func testAnOutageThenRecovery() throws {
        let app = try launch()
        defer { app.terminate() }
        XCTAssertTrue(waitForChip(app, label: "Override, Holds until canceled", timeout: 5))
        server?.setDropped(true)
        XCTAssertTrue(waitForChip(app, label: "Hub unreachable · showing the last update", timeout: 15))
        Thread.sleep(forTimeInterval: 7)
        XCTAssertTrue(chip(app).exists, "hub unreachable persists past the 6 s window")
        server?.setDropped(false)
        XCTAssertTrue(waitForChip(app, label: "Reconnected", timeout: 15))
    }
}
