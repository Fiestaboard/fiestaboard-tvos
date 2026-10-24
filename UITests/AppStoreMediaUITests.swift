import XCTest

/// Opt-in capture of the shipping UI. The local HTTP fixture substitutes only
/// for a FiestaBoard server; navigation, sign-in, polling and rendering are real.
@MainActor
final class AppStoreMediaUITests: XCTestCase {
    private var server: FixtureHTTPServer?

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FIESTA_APP_STORE_MEDIA"] == "1",
                          "App Store media runs only in its dedicated capture workflow.")
    }

    override func tearDown() {
        server = nil
        super.tearDown()
    }

    func testReviewerWalkthroughAndScreenshots() throws {
        let names = ["Living Room", "Kitchen", "Studio", "Patio"]
        let messages = ["WELCOME TO FIESTABOARD", "GOOD FOOD GREAT COMPANY",
                        "MAKE EVERY DAY A FIESTA", "SEE YOU AT THE NEXT FIESTA"]
        var panels: [[String: Any]] = []
        var byID: [String: String] = [:]
        var frames: [String: String] = [:]
        for (index, name) in names.enumerated() {
            var panel = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(Fixtures.panelJSON.utf8)) as? [String: Any])
            let id = "app-store-\(index)"
            panel["id"] = id
            panel["short_code"] = index + 1
            panel["name"] = name
            panel["rows"] = 12
            panel["cols"] = 30
            panel["animations_enabled"] = true
            panel["auto_dim"] = ["enabled": false, "start": "22:00", "end": "07:00"]
            if index == 1 || index == 3 {
                panel["render_style"] = "led_matrix"
                panel["matrix_sizing"] = "fill_tv"
                panel["device_model_spec"] = [
                    "geometry": ["kind": "pixels", "width": 192, "height": 96],
                    "font": "5x7",
                    "appearance": ["pixelShape": index == 1 ? "square" : "round", "dotRatio": 0.82]
                ]
            }
            panels.append(panel)
            byID[id] = try json(panel)
            frames[id] = try frame(message: messages[index], phase: index)
        }
        let fixture = try FixtureHTTPServer(panelsBody: json(["panels": panels, "total": panels.count]),
                                            additionalPanels: byID, additionalFrames: frames,
                                            tvSignInEnabled: true, approveDeviceSignIn: true)
        server = fixture
        let app = XCUIApplication()
        app.launchArguments = ["-fiestaboard.connection", "<>", "-fiestaboard.signedOut", "NO",
                               "-fiestaboard.discoveryFixture", "http://127.0.0.1:\(fixture.port)/__fixtures/discovery",
                               "-fiestaboard.sizing", "fit"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.textFields["FiestaBoard address"].waitForExistence(timeout: 15))
        fixture.releaseDiscoveredBoard(name: "Home FiestaBoard")
        let discovered = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Home FiestaBoard,")).firstMatch
        XCTAssertTrue(discovered.waitForExistence(timeout: 10))
        capture("01-connect", app: app, hold: 3)
        focus(discovered, direction: .up, app: app)
        XCUIRemote.shared.press(.select)

        let phone = app.buttons["device-sign-in"]
        XCTAssertTrue(phone.waitForExistence(timeout: 10))
        capture("02-sign-in", app: app, hold: 3)
        focus(phone, direction: .up, app: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["device-new-code"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "W D J B")).firstMatch.waitForExistence(timeout: 3))
        // Approval is simulated by the fixture's next normal token poll.
        capture("03-tv-sign-in-code", app: app)

        let first = card(names[0], app: app)
        XCTAssertTrue(first.waitForExistence(timeout: 20))
        waitForValue("Board reads:", element: card(names[1], app: app), key: "label")
        capture("04-panels", app: app, hold: 4)
        focus(first, direction: .left, app: app)
        XCUIRemote.shared.press(.select)
        waitForViewer(names[0], message: messages[0], app: app)
        capture("05-split-flap", app: app, hold: 5)

        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Panels"].waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(app.buttons["Settings"].hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Applies to every viewer of this panel."].waitForExistence(timeout: 5))
        waitForValue(messages[0], element: app.otherElements["settings.panelPreview"])
        capture("06-panel-appearance", app: app, hold: 4)
        let local = app.buttons["This Apple TV"]
        focus(local, direction: .up, app: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Applies only to this Apple TV."].waitForExistence(timeout: 3))
        capture("07-this-apple-tv", app: app, hold: 4)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons[names[0]].waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.staticTexts["Panels"].waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(card(names[1], app: app).hasFocus)
        XCUIRemote.shared.press(.select)
        waitForViewer(names[1], message: messages[1], app: app)
        capture("08-square-led", app: app, hold: 5)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.staticTexts["Panels"].waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(card(names[3], app: app).hasFocus)
        XCUIRemote.shared.press(.select)
        waitForViewer(names[3], message: messages[3], app: app)
        capture("09-round-led", app: app, hold: 5)
        XCTAssertEqual(app.state, .runningForeground)
        capture("10-walkthrough-end", app: app, hold: 2)
    }

    private func card(_ name: String, app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + ",")).firstMatch
    }

    private func focus(_ element: XCUIElement, direction: XCUIRemote.Button, app: XCUIApplication) {
        for _ in 0..<8 {
            let cell = app.cells.containing(.button, identifier: element.identifier).firstMatch
            if element.hasFocus || (cell.exists && cell.hasFocus) { return }
            XCUIRemote.shared.press(direction)
        }
        XCTFail("Could not focus \(element.label)")
    }

    private func waitForValue(_ value: String, element: XCUIElement, key: String = "value") {
        let received = XCTNSPredicateExpectation(predicate: NSPredicate(format: "%K CONTAINS %@", key, value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [received], timeout: 15), .completed)
    }

    private func waitForViewer(_ name: String, message: String, app: XCUIApplication) {
        let board = app.buttons[name]
        XCTAssertTrue(board.waitForExistence(timeout: 10))
        waitForValue(message, element: board)
        // Receipt precedes completion of the actual renderer's transition.
        Thread.sleep(forTimeInterval: 6)
        XCTAssertFalse(app.buttons["Settings"].exists)
    }

    private func capture(_ name: String, app: XCUIApplication, hold: TimeInterval = 0) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "AppStore-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        if hold > 0 { Thread.sleep(forTimeInterval: hold) }
    }

    private func frame(message: String, phase: Int) throws -> String {
        var cells = Array(repeating: Array(repeating: 0, count: 30), count: 12)
        for col in 0..<30 {
            cells[1][col] = 63 + (col / 5 + phase) % 6
            cells[10][col] = 63 + (5 + col / 5 - phase + 6) % 6
        }
        let codes = message.utf8.map { (65...90).contains($0) ? Int($0 - 64) : 0 }
        let start = max(0, (30 - codes.count) / 2)
        for (index, code) in codes.prefix(30).enumerated() { cells[5][start + index] = code }
        return try json(["characters": cells, "message": message, "rows": 12, "cols": 30])
    }

    private func json(_ object: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
}
