import XCTest

@MainActor
final class HomeTopShelfUITests: XCTestCase {
    private var server: FixtureHTTPServer?

    override func tearDown() {
        server = nil
        super.tearDown()
    }

    /// A static brand poster must not pass for working Top Shelf content.
    /// Exercise the real Home card row and open its second panel with Select.
    func testHomeTopShelfScreenshotForReview() throws {
        continueAfterFailure = false
        let panelsLoaded = expectation(description: "The app requested the available panels")
        var kitchenObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(Fixtures.panelJSON.utf8)) as? [String: Any])
        kitchenObject["id"] = "kitchen-review"
        kitchenObject["short_code"] = 2
        kitchenObject["name"] = "Kitchen Review"
        kitchenObject["render_style"] = "led_matrix"
        kitchenObject["matrix_sizing"] = "fill_tv"
        kitchenObject["device_model_spec"] = ["geometry": ["kind": "pixels", "width": 192, "height": 96],
                                               "font": "5x7", "appearance": ["pixelShape": "round", "dotRatio": 0.82]]
        let kitchen = String(decoding: try JSONSerialization.data(withJSONObject: kitchenObject), as: UTF8.self)
        let panels = "{\"panels\":[\(Fixtures.panelJSON),\(kitchen)],\"total\":2}"
        func frame(_ message: String) throws -> String {
            var cells = Array(repeating: Array(repeating: 0, count: 30), count: 12)
            for (offset, byte) in message.utf8.enumerated() {
                cells[5][(30 - message.count) / 2 + offset] = (65...90).contains(byte) ? Int(byte - 64) : 0
            }
            for column in 0..<30 {
                cells[1][column] = 63 + column / 5
                cells[10][column] = 68 - column / 5
            }
            return String(decoding: try JSONSerialization.data(withJSONObject: ["characters": cells, "rows": 12, "cols": 30, "message": message]), as: UTF8.self)
        }
        let server = try FixtureHTTPServer(frameBody: frame("LIVING ROOM"), panelsBody: panels,
                                           additionalPanels: ["kitchen-review": kitchen],
                                           additionalFrames: ["kitchen-review": frame("KITCHEN REVIEW")],
                                           onPanels: { panelsLoaded.fulfill() })
        self.server = server
        let connection = """
        {"host":"http://127.0.0.1:\(server.port)","displayName":"Test Board"}
        """
        let encoded = Data(connection.utf8).map { String(format: "%02x", $0) }.joined()
        let app = XCUIApplication()
        app.launchArguments = ["-fiestaboard.connection", "<\(encoded)>",
                               "-fiestaboard.signedOut", "NO",
                               // This checks navigation and actual board content.
                               // CI's timezone can put the fixture inside its night
                               // window, adding a dimming suffix to the spoken value.
                               "-fiestaboard.signage.autoDimOverride", "neverDim"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Panels"].waitForExistence(timeout: 5))
        wait(for: [panelsLoaded], timeout: 10)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Kitchen Review,")).firstMatch
            .waitForExistence(timeout: 5), "Both available panels must load before returning Home")

        for message in ["LIVING ROOM", "KITCHEN REVIEW"] {
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Board reads: \(message)"))
                .firstMatch.waitForExistence(timeout: 10), "The real frame must load before preview publication")
        }
        holdForReview()
        XCUIRemote.shared.press(.menu)
        // Recent tvOS versions host the icon grid and Top Shelf in HeadBoard;
        // PineBoard's accessibility tree contains only its scene containers.
        let headboard = XCUIApplication(bundleIdentifier: "com.apple.HeadBoard")
        let home = headboard.state == .runningForeground
            ? headboard : XCUIApplication(bundleIdentifier: "com.apple.PineBoard")
        let icon = home.icons["FiestaBoard"]
        XCTAssertTrue(icon.waitForExistence(timeout: 5))
        // Focus the app independently of asynchronous extension loading.
        // Walking based on a missing content label can leave the right icon
        // just as its cards arrive. Home exposes actual focus and geometry.
        for _ in 0..<10 {
            if icon.hasFocus { break }
            if let focused = home.icons.allElementsBoundByIndex.first(where: { $0.hasFocus }) {
                XCUIRemote.shared.press(focused.frame.midX < icon.frame.midX ? .right : .left)
            } else {
                XCUIRemote.shared.press(.down)
            }
        }
        XCTAssertTrue(icon.hasFocus, "FiestaBoard's icon should be focused while its Top Shelf loads")
        // HeadBoard exposes section headers as Other and cards as Cell.
        let section = home.otherElements["Available panels"]
        let livingRoom = home.cells.matching(NSPredicate(format: "label == %@", "Living Room")).firstMatch
        let kitchenCard = home.cells.matching(NSPredicate(format: "label == %@", "Kitchen Review")).firstMatch
        XCTAssertTrue(kitchenCard.waitForExistence(timeout: 15), "The extension must load both available panel cards")
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = "Apple TV Home — available panel cards"
        capture.lifetime = .keepAlways
        add(capture)
        let hierarchy = XCTAttachment(string: home.debugDescription)
        hierarchy.name = "Top Shelf card accessibility"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTAssertTrue(section.exists, "Home should show the extension's available-panel card row")
        XCTAssertTrue(livingRoom.exists)
        XCUIRemote.shared.press(.up)
        for _ in 0..<3 {
            if livingRoom.hasFocus { break }
            XCUIRemote.shared.press(.left)
        }
        XCTAssertTrue(livingRoom.hasFocus, "The first available panel card should accept remote focus")
        holdForReview()
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(kitchenCard.hasFocus, "Moving right must focus the second available panel card")
        let focusedCard = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        focusedCard.name = "Apple TV Home — Kitchen Review card selected"
        focusedCard.lifetime = .keepAlways
        add(focusedCard)
        holdForReview()
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Kitchen Review"].waitForExistence(timeout: 10),
                      "Selecting the second Home card must open that panel's viewer")
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertFalse(app.staticTexts["Panels"].exists,
                       "A Top Shelf card should open its panel directly")
        let boardReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasFocus == YES AND value == %@", "KITCHEN REVIEW"),
            object: app.buttons["Kitchen Review"])
        XCTAssertEqual(XCTWaiter.wait(for: [boardReady], timeout: 5), .completed)
        holdForReview()
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Kitchen Review"].waitForExistence(timeout: 3))
        holdForReview()
        let opened = XCTAttachment(screenshot: app.screenshot())
        opened.name = "Top Shelf opened Kitchen Review"
        opened.lifetime = .keepAlways
        add(opened)
    }

    private func holdForReview() {
        if ProcessInfo.processInfo.environment["FIESTA_RECORD_REVIEW"] == "1" {
            Thread.sleep(forTimeInterval: 2)
        }
    }
}
