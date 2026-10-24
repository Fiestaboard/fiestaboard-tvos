import XCTest

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
            if focused(label, app: app) { XCUIRemote.shared.press(.select); return }
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
        let question = app.staticTexts["oled.question"]
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        XCTAssertEqual(question.label.lowercased(), "will you use this with an oled tv?")
    }
    func testQuestionBrightnessPersistenceAndBack() throws {
        continueAfterFailure = false
        server = try FixtureHTTPServer()
        defer { server = nil }
        let app = XCUIApplication()
        let connection = "{\"host\":\"http://127.0.0.1:\(server!.port)\",\"displayName\":\"Test Board\"}"
        let encoded = Data(connection.utf8).map { String(format: "%02x", $0) }.joined()
        app.launchArguments = ["-fiestaboard.connection", "<\(encoded)>", "-fiestaboard.signedOut", "NO"]
        app.launch()
        openCare(app)
        for label in ["Yes", "No", "Not sure", "Skip"] { XCTAssertTrue(app.buttons[label].exists) }
        select("Yes", app: app)
        XCTAssertTrue(app.staticTexts["Preview — app output only"].exists)
        select("oled.brightness", app: app)
        for _ in 0..<5 { XCUIRemote.shared.press(.up) }
        select("50%", app: app)
        // Picker selection may remain in its native choice screen until Back.
        if !app.buttons["oled.brightness"].exists { XCUIRemote.shared.press(.menu) }
        XCTAssertTrue(app.buttons["oled.brightness"].waitForExistence(timeout: 5))
        XCTAssertTrue((app.buttons["oled.brightness"].value as? String ?? "").contains("50"))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Choose a panel. OLED TV? Optional setup in Settings → OLED care."].exists, "Answer dismisses the optional invitation")
        app.terminate(); app.launch()
        openCare(app)
        XCTAssertEqual(app.buttons["Yes"].value as? String, "Selected")
        // Scroll the persisted brightness row into the accessibility viewport.
        for _ in 0..<8 {
            if focused("oled.brightness", app: app) { break }
            XCUIRemote.shared.press(.down)
        }
        XCTAssertTrue((app.buttons["oled.brightness"].value as? String ?? "").contains("50"))
        // Leave device defaults clean for other native presentation tests.
        select("oled.brightness", app: app)
        for _ in 0..<5 { XCUIRemote.shared.press(.up) }
        select("100%", app: app)
    }
}
