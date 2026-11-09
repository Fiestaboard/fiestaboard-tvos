import XCTest

@MainActor
final class HomeTopShelfUITests: XCTestCase {
    private var server: FixtureHTTPServer?

    override func tearDown() {
        server = nil
        super.tearDown()
    }

    /// A static brand poster must not pass for working Top Shelf content.
    /// Exercise the real Home carousel (A7) and open a panel with Play and
    /// Panels with More Info.
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
        let pineboard = XCUIApplication(bundleIdentifier: "com.apple.PineBoard")
        // Menu returns before Home's asynchronous foreground transition ends.
        // Selecting a host from that instantaneous state can lock this test
        // onto PineBoard even when HeadBoard owns the visible icon grid.
        var readyHome: XCUIApplication?
        let homeReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            readyHome = [headboard, pineboard].first { $0.icons["FiestaBoard"].exists }
            return readyHome != nil
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [homeReady], timeout: 5), .completed,
                       "Home must expose FiestaBoard's icon before choosing its accessibility host")
        let home = try XCTUnwrap(readyHome)
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

        // A7 (07b A9 `166:207117`, DD2): a full-screen carousel, one item
        // per panel. HeadBoard exposes each item as a Cell labelled with
        // the item's title, and the `.actions` buttons as Play / More Info.
        let livingRoom = home.cells.matching(NSPredicate(format: "label == %@", "Living Room")).firstMatch
        let kitchenItem = home.cells.matching(NSPredicate(format: "label == %@", "Kitchen Review")).firstMatch
        XCTAssertTrue(kitchenItem.waitForExistence(timeout: 15), "The extension must load one carousel item per panel")
        XCTAssertTrue(livingRoom.exists)
        XCTAssertEqual(livingRoom.frame.size, CGSize(width: 1920, height: 1080),
                       "carousel items are full screen (HIG), not a row of cards")
        Thread.sleep(forTimeInterval: 1)
        attach("Apple TV Home — Top Shelf carousel (07b A9 166:207117)")

        // Swipe up: the carousel goes full screen with the system actions.
        XCUIRemote.shared.press(.up)
        let play = livingRoom.buttons["Play"]
        let moreInfo = livingRoom.buttons["More Info"]
        XCTAssertTrue(play.waitForExistence(timeout: 5), "`.actions` style: the system Play button")
        XCTAssertTrue(moreInfo.exists, "`.actions` style: the system More Info button")
        XCTAssertTrue(play.hasFocus, "Play takes focus when the carousel goes full screen")
        Thread.sleep(forTimeInterval: 1)
        attach("Apple TV Home — carousel full screen, Play / More Info")
        let tree = XCTAttachment(string: home.debugDescription)
        tree.name = "Top Shelf carousel accessibility"
        tree.lifetime = .keepAlways
        add(tree)
        holdForReview()

        // Play opens that panel's viewer directly.
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Living Room"].waitForExistence(timeout: 10),
                      "Play must open the panel's viewer")
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertFalse(app.staticTexts["Panels"].exists, "Play opens the viewer, not Panels")
        attach("Top Shelf Play opened Living Room")
        holdForReview()

        // More Info opens Panels.
        XCUIRemote.shared.press(.home)
        XCTAssertTrue(icon.waitForExistence(timeout: 5))
        for _ in 0..<10 where !icon.hasFocus {
            if let focused = home.icons.allElementsBoundByIndex.first(where: { $0.hasFocus }) {
                XCUIRemote.shared.press(focused.frame.midX < icon.frame.midX ? .right : .left)
            } else {
                XCUIRemote.shared.press(.down)
            }
        }
        XCTAssertTrue(icon.hasFocus)
        XCUIRemote.shared.press(.up)
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(moreInfo.hasFocus, "Down moves from Play to More Info")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Panels"].waitForExistence(timeout: 10), "More Info must open Panels")
        attach("Top Shelf More Info opened Panels")
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func holdForReview() {
        if ProcessInfo.processInfo.environment["FIESTA_RECORD_REVIEW"] == "1" {
            Thread.sleep(forTimeInterval: 2)
        }
    }
}
