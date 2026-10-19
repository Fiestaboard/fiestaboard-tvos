import XCTest

@MainActor
final class DeviceSignInUITests: XCTestCase {
    private var server: FixtureHTTPServer?
    override func tearDown() { server = nil; super.tearDown() }

    func testRemoteCanShowCodeAndReturnToPasswordWithoutLosingBoard() throws {
        continueAfterFailure = false
        server = try FixtureHTTPServer(tvSignInEnabled: true)
        let app = XCUIApplication()
        let connection = "{\"host\":\"http://127.0.0.1:\(server!.port)\",\"displayName\":\"Activation Test Board\"}"
        let encoded = Data(connection.utf8).map { String(format: "%02x", $0) }.joined()
        app.launchArguments = ["-fiestaboard.connection", "<\(encoded)>", "-fiestaboard.signedOut", "YES"]
        app.launch()
        defer { app.terminate() }
        let phone = app.buttons["device-sign-in"]
        XCTAssertTrue(phone.waitForExistence(timeout: 10))
        for _ in 0..<8 {
            if phone.hasFocus || app.cells.containing(.button, identifier: "device-sign-in").firstMatch.hasFocus { break }
            XCUIRemote.shared.press(.up)
        }
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["device-new-code"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "W D J B")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "/activate")).firstMatch.exists)
        capture("TV sign-in — QR and manual code", app: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.secureTextFields["Password"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Activation Test Board"].exists)
    }
    func testEnrollmentDisabledShowsRecoveryWithoutAnEndlessSpinner() throws {
        try checkTerminalFailure(server: FixtureHTTPServer(tvSignInEnabled: true, deviceAuthorizationError: "feature_disabled"),
                                 expected: "TV sign-in is disabled.", screenshot: "TV sign-in — enrollment disabled")
    }

    func testDeniedCodeRemovesTheUnusableQRAndCountdown() throws {
        try checkTerminalFailure(server: FixtureHTTPServer(tvSignInEnabled: true, devicePollError: "access_denied"),
                                 expected: "This sign-in was denied.", screenshot: "TV sign-in — denied")
    }

    private func checkTerminalFailure(server: FixtureHTTPServer, expected: String, screenshot: String) throws {
        continueAfterFailure = false
        self.server = server
        let app = XCUIApplication()
        let connection = "{\"host\":\"http://127.0.0.1:\(server.port)\",\"displayName\":\"Activation Test Board\"}"
        let encoded = Data(connection.utf8).map { String(format: "%02x", $0) }.joined()
        app.launchArguments = ["-fiestaboard.connection", "<\(encoded)>", "-fiestaboard.signedOut", "YES"]
        app.launch()
        defer { app.terminate() }
        let phone = app.buttons["device-sign-in"]
        XCTAssertTrue(phone.waitForExistence(timeout: 10))
        for _ in 0..<8 {
            if phone.hasFocus || app.cells.containing(.button, identifier: "device-sign-in").firstMatch.hasFocus { break }
            XCUIRemote.shared.press(.up)
        }
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", expected)).firstMatch.waitForExistence(timeout: 10))
        capture(screenshot, app: app)
        XCTAssertEqual(app.progressIndicators.count, 0, "A terminal failure must not look like ongoing work")
        XCTAssertFalse(app.descendants(matching: .any)["device-code-loading"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "W D J B")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Code expires")).firstMatch.exists)
        XCTAssertTrue(app.buttons["device-new-code"].exists)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.secureTextFields["Password"].waitForExistence(timeout: 5))
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

}
