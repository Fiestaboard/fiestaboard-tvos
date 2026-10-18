import XCTest

@MainActor
final class FiestaBotPresentationTests: XCTestCase {
    private var server: FixtureHTTPServer?
    override func tearDown() { server = nil; super.tearDown() }

    func testRemoteCanOpenChatAnswerAChoiceAndReturnToViewer() throws {
        continueAfterFailure = false
        let question = """
        event: tool_call
        data: {"id":"question-1","name":"ask_user","args":{},"title":"Choose a page"}

        event: elicitation
        data: {"id":"question-1","message":"Which page?","allow_free_text":true,"requested_schema":{"properties":{"answer":{"type":"string","enum":["Weather","Welcome"]}}}}

        event: done
        data: {"reason":"awaiting_input","pending_tool_call_id":"question-1"}


        """
        let answer = """
        event: status
        data: {"phase":"thinking","message":"Thinking"}

        event: text
        data: {"delta":"Weather is ready for this panel."}

        event: done
        data: {"reason":"complete"}


        """
        let frameLoaded = expectation(description: "Viewer loaded")
        server = try FixtureHTTPServer(chatResponses: [question, answer], onFrame: { frameLoaded.fulfill() })
        let app = XCUIApplication()
        let connection = "{\"host\":\"http://127.0.0.1:\(server!.port)\",\"displayName\":\"Test Board\",\"defaultPanelRef\":\"1\"}"
        let encoded = Data(connection.utf8).map { String(format: "%02x", $0) }.joined()
        app.launchArguments = ["-fiestaboard.connection", "<\(encoded)>", "-fiestaboard.signedOut", "NO"]
        app.launch()
        wait(for: [frameLoaded], timeout: 10)
        XCTAssertTrue(app.progressIndicators.firstMatch.waitForNonExistence(timeout: 5))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Panels"].waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.right)
        XCUIRemote.shared.press(.right)
        waitForFocus("FiestaBot", app: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.textFields["fiestabot.composer"].waitForExistence(timeout: 5))
        selectRow("What can I show?", app: app)
        XCTAssertTrue(app.buttons["Weather"].waitForExistence(timeout: 10))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "FiestaBot remote choices"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCUIRemote.shared.press(.right)
        selectRow("Weather", app: app)
        XCTAssertTrue(app.staticTexts["Weather is ready for this panel."].waitForExistence(timeout: 10))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.textFields["fiestabot.composer"].waitForNonExistence(timeout: 5))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Panels"].waitForExistence(timeout: 3))
    }

    private func focused(_ label: String, app: XCUIApplication) -> Bool {
        app.buttons[label].hasFocus || app.cells.containing(.button, identifier: label).firstMatch.hasFocus
    }
    private func waitForFocus(_ label: String, app: XCUIApplication) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in focused(label, app: app) }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }
    private func selectRow(_ label: String, app: XCUIApplication) {
        for _ in 0..<16 {
            if focused(label, app: app) { XCUIRemote.shared.press(.select); return }
            XCUIRemote.shared.press(.down)
        }
        XCTFail("Could not reach \(label) with the remote")
    }
}
