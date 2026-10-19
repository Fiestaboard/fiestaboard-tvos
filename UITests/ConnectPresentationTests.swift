import XCTest

@MainActor
final class ConnectPresentationTests: XCTestCase {
    private var server: FixtureHTTPServer?

    override func tearDown() {
        server = nil
        super.tearDown()
    }

    /// Release discovery only after the remote is on manual entry. This
    /// reproduces a first result arriving while someone uses the fallback.
    func testFirstDiscoveredBoardDoesNotTakeFocusFromTheAddressField() throws {
        continueAfterFailure = false
        let server = try FixtureHTTPServer()
        self.server = server
        let app = XCUIApplication()
        // Override persisted pairing through UserDefaults' argument domain.
        app.launchArguments = ["-fiestaboard.connection", "<>", "-fiestaboard.signedOut", "NO",
                               "-fiestaboard.discoveryFixture",
                               "http://127.0.0.1:\(server.port)/__fixtures/discovery"]
        app.launch()
        defer { app.terminate() }

        let address = app.textFields["FiestaBoard address"]
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        for _ in 0..<4 {
            if address.hasFocus { break }
            XCUIRemote.shared.press(.down)
            XCUIRemote.shared.press(.left)
        }
        XCTAssertTrue(address.hasFocus, "The remote must start on the manual address field")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", ",")).count, 0,
                       "The fixture must be the first discovered board for this regression")

        let name = "FiestaBoard Focus"
        server.releaseDiscoveredBoard(name: name)
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "The held discovery result must reach the screen")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Connect — discovery during manual entry"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(address.hasFocus, "A Bonjour result must preserve the address field's focus")
        XCTAssertFalse(card.hasFocus, "Discovery must not move the remote to the new board card")
    }
}
