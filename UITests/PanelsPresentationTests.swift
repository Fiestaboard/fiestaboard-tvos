import XCTest

@MainActor
final class PanelsPresentationTests: XCTestCase {
    private var server: FixtureHTTPServer?

    override func tearDown() {
        server = nil
        super.tearDown()
    }

    /// Exercises the real safe area and focus movement; an offscreen render that
    /// ignores safe areas missed the old one-column layout on a real TV.
    func testTwoColumnsFitAndRemoteCanBrowseEveryRow() throws {
        continueAfterFailure = false
        var panels: [String] = []
        var byID: [String: String] = [:]
        let names = ["Living Room", "Kitchen", "Studio", "Patio", "Bedroom", "Office"]
        for (index, name) in names.enumerated() {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(Fixtures.panelJSON.utf8)) as? [String: Any])
            let id = "review-\(index)"
            object["id"] = id
            object["name"] = name
            if index % 3 != 0 {
                object["render_style"] = "led_matrix"
                object["device_model_spec"] = ["geometry": ["kind": "pixels", "width": 192, "height": 96],
                    "appearance": ["pixelShape": index % 3 == 1 ? "round" : "square"]]
            }
            let json = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
            panels.append(json)
            byID[id] = json
        }
        var cells = Array(repeating: Array(repeating: 0, count: 30), count: 12)
        for (offset, byte) in "HELLO FIESTABOARD".utf8.enumerated() {
            cells[5][7 + offset] = (65...90).contains(byte) ? Int(byte - 64) : 0
        }
        for col in 0..<30 { cells[1][col] = 63 + col / 5; cells[10][col] = 68 - col / 5 }
        let frame = String(decoding: try JSONSerialization.data(withJSONObject:
            ["characters": cells, "rows": 12, "cols": 30, "message": "HELLO FIESTABOARD"]), as: UTF8.self)
        let server = try FixtureHTTPServer(frameBody: frame,
            panelsBody: "{\"panels\":[\(panels.joined(separator: ","))],\"total\":6}", additionalPanels: byID)
        self.server = server
        let connection = "{\"host\":\"http://127.0.0.1:\(server.port)\",\"displayName\":\"Home FiestaBoard\"}"
        let encoded = Data(connection.utf8).map { String(format: "%02x", $0) }.joined()
        let app = XCUIApplication()
        app.launchArguments = ["-fiestaboard.connection", "<\(encoded)>", "-fiestaboard.signedOut", "NO"]
        app.launch()
        func card(_ name: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + ",")).firstMatch
        }
        let first = card("Living Room"), second = card("Kitchen")
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Board reads:"), object: second)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        capture(app, "Panel browser — first row")
        XCTAssertEqual(first.frame.midY, second.frame.midY, accuracy: 30,
                       "Two panels should share a row inside the TV safe area")
        XCTAssertGreaterThan(second.frame.minX, first.frame.midX)
        waitForFocus(first)
        let focusedSize = first.frame.size
        XCUIRemote.shared.press(.right)
        waitForFocus(second, "Right should reach the second card, not Settings")
        XCTAssertEqual(first.frame.width, focusedSize.width, accuracy: 1,
                       "Focus must not rescale the board preview")
        XCTAssertEqual(first.frame.height, focusedSize.height, accuracy: 1)
        XCUIRemote.shared.press(.down)
        waitForFocus(card("Patio"))
        XCUIRemote.shared.press(.down)
        waitForFocus(card("Office"))
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = card("Office").frame
            return frame.minY > 250 && frame.maxY < app.frame.maxY - 40
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed,
                       "The final focused card must scroll fully into view")
        capture(app, "Panel browser — final row")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Office"].waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.staticTexts["Panels"].waitForExistence(timeout: 5))
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == YES"), object: card("Office"))
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed,
                       "Returning from a panel should keep the user's place in the browser")
        for _ in 0..<6 {
            if app.buttons["Settings"].hasFocus { break }
            XCUIRemote.shared.press(.up)
        }
        waitForFocus(app.buttons["Settings"])
        let refreshed = panels.reversed().joined(separator: ",").replacingOccurrences(of: "Office", with: "Office updated")
        server.updatePanels("{\"panels\":[\(refreshed)],\"total\":6}")
        XCUIRemote.shared.press(.menu)
        app.activate()
        XCTAssertTrue(card("Office updated").waitForExistence(timeout: 10), "Foreground refresh must load the reordered panels")
        XCTAssertTrue(app.buttons["Settings"].hasFocus,
                      "A refreshed panel order must not steal intentional focus from Settings")
    }

    /// More panels than the thumbnail working set, mixing dense matrices and
    /// split-flap boards. Revisit evicted rows using the real remote focus engine.
    func testRemoteCanRevisitRowsBeyondThePreviewCacheCapacity() throws {
        continueAfterFailure = false
        var panels: [String] = []
        var byID: [String: String] = [:]
        for index in 0..<14 {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(Fixtures.panelJSON.utf8)) as? [String: Any])
            let id = "stress-\(index)"
            object["id"] = id
            object["name"] = "Stress \(index)"
            if index % 3 != 0 {
                object["render_style"] = "led_matrix"
                object["device_model_spec"] = ["geometry": ["kind": "pixels", "width": 636, "height": 352],
                    "appearance": ["pixelShape": index % 3 == 1 ? "round" : "square"]]
            }
            let json = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
            panels.append(json)
            byID[id] = json
        }
        let cells = Array(repeating: Array(repeating: 63, count: 30), count: 12)
        let frame = String(decoding: try JSONSerialization.data(withJSONObject:
            ["characters": cells, "rows": 12, "cols": 30, "message": "Stress preview"]), as: UTF8.self)
        let server = try FixtureHTTPServer(frameBody: frame,
            panelsBody: "{\"panels\":[\(panels.joined(separator: ","))],\"total\":14}", additionalPanels: byID)
        self.server = server
        let connection = "{\"host\":\"http://127.0.0.1:\(server.port)\",\"displayName\":\"Stress fixture\"}"
        let encoded = Data(connection.utf8).map { String(format: "%02x", $0) }.joined()
        let app = XCUIApplication()
        app.launchArguments = ["-fiestaboard.connection", "<\(encoded)>", "-fiestaboard.signedOut", "NO"]
        app.launch()
        func card(_ index: Int) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Stress \(index),")).firstMatch
        }
        func waitForPreviews(inRowStartingWith index: Int) {
            for item in index...(index + 1) {
                let ready = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "label CONTAINS %@", "Board reads:"), object: card(item))
                XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed,
                               "Navigation must exercise loaded previews, not placeholders")
            }
        }
        XCTAssertTrue(card(0).waitForExistence(timeout: 15))
        waitForFocus(card(0))
        waitForPreviews(inRowStartingWith: 0)
        XCUIRemote.shared.press(.right)
        waitForFocus(card(1))
        for index in stride(from: 3, through: 13, by: 2) {
            XCUIRemote.shared.press(.down)
            waitForFocus(card(index))
            waitForPreviews(inRowStartingWith: index - 1)
        }
        capture(app, "Panel browser — fourteen mixed panels")
        for index in stride(from: 11, through: 1, by: -2) {
            XCUIRemote.shared.press(.up)
            waitForFocus(card(index))
            waitForPreviews(inRowStartingWith: index - 1)
        }
        XCUIRemote.shared.press(.left)
        waitForFocus(card(0))

        // Restore a distant right-column card, whose lazy row is identified
        // by its left-column panel. Keep this after the full cache traversal.
        XCUIRemote.shared.press(.right)
        waitForFocus(card(1))
        for index in stride(from: 3, through: 13, by: 2) {
            XCUIRemote.shared.press(.down)
            waitForFocus(card(index))
        }
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Stress 13"].waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.staticTexts["Panels"].waitForExistence(timeout: 5))
        waitForFocus(card(13), "Returning should restore the distant right-column card")
        capture(app, "Panel browser — restored distant right-column card")
    }

    /// Remote presses can return while tvOS is still transferring focus and
    /// scrolling a lazy row into view. Assert the eventual target, without
    /// issuing extra presses that could hide a navigation regression.
    private func waitForFocus(_ element: XCUIElement, _ message: String = "Expected remote focus",
                              file: StaticString = #filePath, line: UInt = #line) {
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == YES"), object: element)
        let result = XCTWaiter.wait(for: [focused], timeout: 5)
        if result != .completed {
            let app = XCUIApplication()
            capture(app, "Panel browser — failed focus transition")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Panel browser — focus hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertEqual(result, .completed, message, file: file, line: line)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
