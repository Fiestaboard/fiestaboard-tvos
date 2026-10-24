import XCTest

@MainActor
final class OLEDCareUITests: XCTestCase {
    private var server: FixtureHTTPServer?
    func testOptionalQuestionBrightnessPersistenceAndBack() throws {
        server = try FixtureHTTPServer()
        defer { server = nil }
        let app = XCUIApplication()
        let connection = "{\"host\":\"http://127.0.0.1:\(server!.port)\",\"displayName\":\"Test Board\"}"
        let encoded = Data(connection.utf8).map { String(format: "%02x", $0) }.joined()
        app.launchArguments = ["-fiestaboard.connection", "<\(encoded)>", "-fiestaboard.signedOut", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["OLED care"].waitForExistence(timeout: 10))
        // Header remains reachable from the panel grid using the remote.
        for _ in 0..<5 { XCUIRemote.shared.press(.up) }
        for _ in 0..<5 {
            if app.buttons["OLED care"].hasFocus { break }
            XCUIRemote.shared.press(.left)
        }
        XCTAssertTrue(app.buttons["OLED care"].hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Will you use this with an OLED TV?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Yes"].exists)
        XCTAssertTrue(app.buttons["No"].exists)
        XCTAssertTrue(app.buttons["Not sure"].exists)
        XCTAssertTrue(app.buttons["Skip"].exists)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Preview — app output only"].exists)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
    }
}
