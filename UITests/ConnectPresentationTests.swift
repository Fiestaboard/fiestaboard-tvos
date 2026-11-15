import XCTest

@MainActor
final class ConnectPresentationTests: XCTestCase {
    private var server: FixtureHTTPServer?

    override func tearDown() {
        server = nil
        super.tearDown()
    }

    func testLookingThenHubErrorKeepsTheHubReachable() throws {
        continueAfterFailure = false
        let server = try FixtureHTTPServer(failAuthStatus: true)
        self.server = server
        let app = XCUIApplication()
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
        XCTAssertTrue(address.hasFocus)
        XCTAssertTrue(app.staticTexts["Looking for FiestaBoard hubs on this network…"].exists)
        attachMilestoneEvidence("Connect — looking for hubs — manual address focused", app: app)
        let name = "FiestaBoard Error Fixture"
        server.releaseDiscoveredBoard(name: name)
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        for _ in 0..<6 {
            if card.hasFocus { break }
            XCUIRemote.shared.press(.up)
        }
        XCTAssertTrue(card.hasFocus)
        XCUIRemote.shared.press(.select)
        let message = "Alert. Your FiestaBoard hub answered with an error (HTTP 500). Check its logs."
        let alert = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", message)).firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Find your FiestaBoard hub"].exists)
        XCTAssertTrue(card.hasFocus, "A failed connection must leave the hub available to retry")
        attachMilestoneEvidence("Connect — hub HTTP 500 error — hub focused", app: app)
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
        // A2: hub vocabulary as VoiceOver and the remote meet it.
        XCTAssertTrue(app.staticTexts["Find your FiestaBoard hub"].exists, "A1 title")
        XCTAssertTrue(app.staticTexts["Or enter your hub’s address"].exists, "A1 manual-entry label")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "board's")).firstMatch.exists,
                       "no hub-sense 'board' on Connect")
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
        attachMilestoneEvidence("Connect — manual address focused", app: app)
        for _ in 0..<6 {
            if card.hasFocus { break }
            XCUIRemote.shared.press(.up)
        }
        XCTAssertTrue(card.hasFocus, "The discovered hub must remain reachable from manual entry")
        attachMilestoneEvidence("Connect — discovered hub focused", app: app)
        for _ in 0..<6 {
            if address.hasFocus { break }
            XCUIRemote.shared.press(.down)
        }
        XCTAssertTrue(address.hasFocus)
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(app.buttons["Connect to the address you entered"].hasFocus)
        attachMilestoneEvidence("Connect — manual Connect focused", app: app)
    }
}
