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
        app.launchArguments.append("-fiestaboard.connectFocusTrace")
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
        // The response updates the banner and card state. Observe the
        // settled native focus without
        // sending any remote movement that could hide a genuine focus loss.
        let retainedFocus = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let currentHub = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
            return currentHub.exists && currentHub.hasFocus
        }, object: nil)
        let focusResult = XCTWaiter.wait(for: [retainedFocus], timeout: 5)
        attachMilestoneEvidence("Connect — hub HTTP 500 error — post-response focus", app: app)
        if focusResult != .completed {
            // Preserve the original focus failure, then independently record
            // whether Select can still retry a control with no reported owner.
            let before = server.authStatusRequestCount
            XCUIRemote.shared.press(.select)
            let retried = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                server.authStatusRequestCount > before
            }, object: nil)
            let result = XCTWaiter.wait(for: [retried], timeout: 5)
            let diagnostic = XCTAttachment(string: "Select after missing native owner: result=\(result.rawValue), requestsBefore=\(before), requestsAfter=\(server.authStatusRequestCount)")
            diagnostic.name = "Connect focus diagnostic — Select after missing owner"
            diagnostic.lifetime = .keepAlways
            add(diagnostic)
        }
        XCTAssertEqual(focusResult, .completed, "A failed connection must leave the same hub focused for retry")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch.hasFocus)
        let beforeRetry = server.authStatusRequestCount
        XCUIRemote.shared.press(.select)
        waitForAuthRequests(beforeRetry + 1, server: server)
    }

    func testFailedHubRequestPreservesNewerManualFocus() throws {
        continueAfterFailure = false
        let server = try FixtureHTTPServer(failAuthStatus: true, holdAuthStatusFailures: true)
        self.server = server
        let app = XCUIApplication()
        app.launchArguments = ["-fiestaboard.connection", "<>", "-fiestaboard.signedOut", "NO",
                               "-fiestaboard.discoveryFixture",
                               "http://127.0.0.1:\(server.port)/__fixtures/discovery"]
        app.launchArguments.append("-fiestaboard.connectFocusTrace")
        app.launch()
        defer { app.terminate() }
        let address = app.textFields["FiestaBoard address"]
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        let name = "FiestaBoard Pending Fixture"
        server.releaseDiscoveredBoard(name: name)
        let hub = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(hub.waitForExistence(timeout: 10))
        for _ in 0..<6 { if hub.hasFocus { break }; XCUIRemote.shared.press(.up) }
        XCTAssertTrue(hub.hasFocus)
        let stableName = hub.label
        XCUIRemote.shared.press(.select)
        waitForAuthRequests(1, server: server)
        XCTAssertEqual(hub.label, stableName, "Connection status must not change the activated control's name")
        XCTAssertEqual(hub.value as? String, "Connecting", "In-flight status remains available to assistive technology")
        XCTAssertTrue(hub.hasFocus, "The held request must retain a reported native owner before manual movement")
        attachMilestoneEvidence("Connect — held request — stable hub identity and connecting value", app: app)
        for _ in 0..<6 {
            if address.hasFocus { break }
            XCUIRemote.shared.press(.down)
            XCUIRemote.shared.press(.left)
        }
        XCTAssertTrue(address.hasFocus)
        server.releaseAuthStatusFailures()
        let alert = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@",
            "Alert. Your FiestaBoard hub answered with an error (HTTP 500). Check its logs.")).firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        let preserved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in address.hasFocus }, object: nil)
        let result = XCTWaiter.wait(for: [preserved], timeout: 5)
        attachMilestoneEvidence("Connect — failed hub preserves newer manual focus", app: app)
        XCTAssertEqual(result, .completed)
        XCTAssertFalse(hub.hasFocus, "A delayed failure must not take focus back from manual entry")
    }

    private func waitForAuthRequests(_ count: Int, server: FixtureHTTPServer) {
        let received = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            server.authStatusRequestCount >= count
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [received], timeout: 5), .completed,
                       "A real request must reach the same fixture hub")
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
        app.launchArguments.append("-fiestaboard.connectFocusTrace")
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
