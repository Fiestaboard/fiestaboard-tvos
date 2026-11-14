import XCTest

/// A8b (`248:110205`): OLED care is one page of summary rows, each opening its
/// own choice page (DD23: no OLED question, preview or disclaimer).
@MainActor
final class OLEDCareUITests: XCTestCase {
    private var server: FixtureHTTPServer?

    private func focused(_ label: String, app: XCUIApplication) -> Bool {
        let row = app.buttons[label]
        let cell = app.cells.containing(.button, identifier: label).firstMatch
        return row.exists && (row.hasFocus || (cell.exists && cell.hasFocus))
    }
    private func select(_ label: String, app: XCUIApplication) {
        for _ in 0..<30 {
            if focused(label, app: app) {
                attachMilestoneEvidence("OLED care — focused \(label)", app: app)
                XCUIRemote.shared.press(.select)
                return
            }
            XCUIRemote.shared.press(.down)
        }
        XCTFail("Remote could not reach \(label)")
    }
    private func openCare(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        for _ in 0..<6 { XCUIRemote.shared.press(.up) }
        for _ in 0..<6 {
            if focused("Settings", app: app) { break }
            XCUIRemote.shared.press(.right)
        }
        XCTAssertTrue(focused("Settings", app: app))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        select("This Apple TV", app: app)
        XCUIRemote.shared.press(.right)
        select("settings.oledCare", app: app)
        XCTAssertTrue(app.buttons["oled.brightness"].waitForExistence(timeout: 5))
    }
    private func brightness(_ app: XCUIApplication) -> String { app.buttons["oled.brightness"].value as? String ?? "" }

    func testSummaryRowsBrightnessPersistenceAndBack() throws {
        continueAfterFailure = false
        server = try FixtureHTTPServer()
        defer { server = nil }
        let app = XCUIApplication()
        let connection = "{\"host\":\"http://127.0.0.1:\(server!.port)\",\"displayName\":\"Test Board\"}"
        let encoded = Data(connection.utf8).map { String(format: "%02x", $0) }.joined()
        app.launchArguments = ["-fiestaboard.connection", "<\(encoded)>", "-fiestaboard.signedOut", "NO"]
        app.launch()
        openCare(app)
        for row in ["oled.brightness", "oled.movement", "oled.night", "oled.rest", "oled.breaks", "oled.rotation",
                    "oled.disconnected", "oled.screensaver"] {
            XCTAssertTrue(app.buttons[row].exists, row)
        }
        XCTAssertFalse(app.staticTexts["oled.question"].exists, "DD23: no OLED question")
        XCTAssertFalse(app.staticTexts["Preview — app output only"].exists, "DD23: no preview")
        attachMilestoneEvidence("OLED care — summary focused", app: app)
        // Each summary row opens a native choice page. Capture before editing,
        // and return with Menu so this walk does not change local preferences.
        for (id, title, rightColumn) in [
            ("oled.movement", "Movement", false),
            ("oled.night", "Night dimming", false),
            ("oled.rest", "Scheduled rest", false),
            ("oled.breaks", "Periodic breaks", true),
            ("oled.rotation", "Layout rotation", true),
            ("oled.disconnected", "When disconnected", true),
            ("oled.screensaver", "Screen saver", true)
        ] {
            for _ in 0..<5 { XCUIRemote.shared.press(.up) }
            XCUIRemote.shared.press(.left)
            for _ in 0..<5 { XCUIRemote.shared.press(.up) }
            if rightColumn { XCUIRemote.shared.press(.right) }
            select(id, app: app)
            XCTAssertTrue(app.buttons["oled.brightness"].waitForNonExistence(timeout: 5))
            if id == "oled.movement" {
                XCTAssertTrue(app.staticTexts["Shifts the board a few pixels over 20 min"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.staticTexts["Larger shifts for long, static days"].exists)
            }
            attachMilestoneEvidence("OLED care — \(title) choices focused", app: app)
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(app.buttons["oled.brightness"].waitForExistence(timeout: 5))
        }
        for _ in 0..<5 { XCUIRemote.shared.press(.up) }
        XCUIRemote.shared.press(.left)
        for _ in 0..<5 { XCUIRemote.shared.press(.up) }
        select("oled.brightness", app: app)
        XCTAssertTrue(app.buttons["50 %"].waitForExistence(timeout: 5))
        attachMilestoneEvidence("OLED care — brightness choices focused", app: app)
        select("50 %", app: app)
        XCTAssertTrue(app.buttons["oled.brightness"].waitForExistence(timeout: 5))
        XCTAssertEqual(brightness(app), "50 %")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["settings.oledCare"].value as? String, "On · only this Apple TV")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Your FiestaPanel displays. OLED TV? Optional setup in Settings → OLED care."].exists,
                       "opening OLED care dismisses the optional invitation")
        app.terminate(); app.launch()
        openCare(app)
        XCTAssertEqual(brightness(app), "50 %", "persists on this TV")
        // Leave device defaults clean for other native presentation tests.
        select("oled.brightness", app: app)
        for _ in 0..<6 { XCUIRemote.shared.press(.down) }
        select("100 %", app: app)
        XCTAssertTrue(app.buttons["oled.brightness"].waitForExistence(timeout: 5))
        XCTAssertEqual(brightness(app), "100 %")
    }
}
