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
        app.launchArguments = ["-fiestaboard.connection", "<\(encoded)>", "-fiestaboard.signedOut", "NO", "-fiestaboard.panelProfile", "YES"]
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

    /// Fourteen panels, mixing dense matrices and split-flap boards: more
    /// than the thumbnail working set (`PanelPreviewImageCache`, 12).
    private func launchStressFixture() throws -> XCUIApplication {
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
        app.launchArguments = ["-fiestaboard.connection", "<\(encoded)>", "-fiestaboard.signedOut", "NO", "-fiestaboard.panelProfile", "YES"]
        app.launch()
        return app
    }

    /// Every card is a view, and so a focus target, before its row is ever
    /// scrolled to. In a `LazyVGrid` the rows below the viewport didn't exist
    /// yet: under CPU load, Down at that boundary found nothing, focus fell
    /// to nothing, and tvOS then ignored focus requests for seconds
    /// (`program/status/tv-panels-flake.md`). Deterministic: at launch the
    /// last row is several screens below the viewport.
    func testEveryCardIsAFocusTargetBeforeItsRowIsScrolledTo() throws {
        continueAfterFailure = false
        let app = try launchStressFixture()
        func card(_ index: Int) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Stress \(index),")).firstMatch
        }
        XCTAssertTrue(card(0).waitForExistence(timeout: 15))
        waitForFocus(card(0))
        for index in 0..<14 {
            XCTAssertTrue(card(index).exists, "Stress \(index) must exist before its row is scrolled to")
        }
        XCTAssertGreaterThan(card(13).frame.minY, app.frame.maxY,
                             "The last row should start below the screen, or this proves nothing")
    }

    /// The native focus engine, with no fallback of the app's, crosses the
    /// grid where nothing sits directly beneath: past a column of removed
    /// boards, and from the right column into an odd last row. Rows:
    /// [0, 1], [2 removed, 3 removed], [4, 5 removed], [6].
    func testRemoteCrossesRemovedBoardsAndReachesAnOddLastRow() throws {
        continueAfterFailure = false
        var panels: [String] = []
        var byID: [String: String] = [:]
        for index in 0..<7 {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(Fixtures.panelJSON.utf8)) as? [String: Any])
            let id = "odd-\(index)"
            object["id"] = id
            object["name"] = "Odd \(index)"
            object["board_missing"] = [2, 3, 5].contains(index)
            let json = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
            panels.append(json)
            byID[id] = json
        }
        let server = try FixtureHTTPServer(frameBody: Fixtures.frameJSON,
            panelsBody: "{\"panels\":[\(panels.joined(separator: ","))],\"total\":7}", additionalPanels: byID)
        self.server = server
        let connection = "{\"host\":\"http://127.0.0.1:\(server.port)\",\"displayName\":\"Odd fixture\"}"
        let encoded = Data(connection.utf8).map { String(format: "%02x", $0) }.joined()
        let app = XCUIApplication()
        app.launchArguments = ["-fiestaboard.connection", "<\(encoded)>", "-fiestaboard.signedOut", "NO", "-fiestaboard.panelProfile", "YES"]
        app.launch()
        func card(_ index: Int) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Odd \(index),")).firstMatch
        }
        XCTAssertTrue(card(0).waitForExistence(timeout: 15))
        waitForFocus(card(0))
        XCUIRemote.shared.press(.right)
        waitForFocus(card(1))
        XCUIRemote.shared.press(.down)
        waitForFocus(card(4), "Down past two removed boards should reach the next card")
        XCUIRemote.shared.press(.down)
        waitForFocus(card(6), "Down should reach the odd last row")
        XCUIRemote.shared.press(.up)
        waitForFocus(card(4))
        XCUIRemote.shared.press(.up)
        waitForFocus(card(0), "Up past the removed boards should reach the first row")
    }

    /// Launch `count` plain split-flap panels named "<prefix> <index>".
    private func launchPlainFixture(prefix: String, count: Int, arguments: [String] = [],
                                    fields: [Int: [String: Any]] = [:]) throws -> (XCUIApplication, FixtureHTTPServer, [String]) {
        var panels: [String] = []
        var byID: [String: String] = [:]
        for index in 0..<count {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(Fixtures.panelJSON.utf8)) as? [String: Any])
            let id = "\(prefix.lowercased())-\(index)"
            object["id"] = id
            object["name"] = "\(prefix) \(index)"
            object.merge(fields[index] ?? [:]) { _, new in new }
            let json = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
            panels.append(json)
            byID[id] = json
        }
        let server = try FixtureHTTPServer(frameBody: Fixtures.frameJSON,
            panelsBody: "{\"panels\":[\(panels.joined(separator: ","))],\"total\":\(count)}", additionalPanels: byID)
        self.server = server
        let connection = "{\"host\":\"http://127.0.0.1:\(server.port)\",\"displayName\":\"\(prefix) fixture\"}"
        let encoded = Data(connection.utf8).map { String(format: "%02x", $0) }.joined()
        let app = XCUIApplication()
        app.launchArguments = ["-fiestaboard.connection", "<\(encoded)>", "-fiestaboard.signedOut", "NO",
                               "-fiestaboard.panelProfile", "YES"] + arguments
        app.launch()
        return (app, server, panels)
    }

    /// A5 (07b Focused `154:6178`): focus draws a 6 pt primary outline
    /// outside the card and a shadow, and nothing else. The board is the
    /// frame's "stationary layer": its pixels are the same focused and not.
    func testTheFocusedCardKeepsItsBoardStill() throws {
        continueAfterFailure = false
        let (app, _, _) = try launchPlainFixture(prefix: "Still", count: 2)
        func card(_ index: Int) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Still \(index),")).firstMatch
        }
        XCTAssertTrue(card(0).waitForExistence(timeout: 15))
        waitForFocus(card(0))
        let drawn = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Preview drawn"), object: card(1))
        XCTAssertEqual(XCTWaiter.wait(for: [drawn], timeout: 15), .completed)
        Thread.sleep(forTimeInterval: 1)
        let frame = card(1).frame
        let board = CGRect(x: frame.minX + 20, y: frame.minY + 10, width: frame.width - 40, height: 430)
        func pixels(_ shot: XCUIScreenshot, _ rect: CGRect) throws -> [UInt8] {
            let image = try XCTUnwrap(shot.image.cgImage)
            let scale = CGFloat(image.width) / app.frame.width
            let crop = try XCTUnwrap(image.cropping(to: CGRect(x: rect.minX * scale, y: rect.minY * scale,
                                                               width: rect.width * scale, height: rect.height * scale)))
            var bytes = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
            let context = try XCTUnwrap(CGContext(data: &bytes, width: crop.width, height: crop.height, bitsPerComponent: 8,
                bytesPerRow: crop.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
            return bytes
        }
        // Across the card's left edge, halfway down: where the outline is.
        let ring = CGRect(x: frame.minX - 12, y: frame.midY, width: 24, height: 1)
        let unfocused = XCUIScreen.main.screenshot()
        XCUIRemote.shared.press(.right)
        waitForFocus(card(1))
        Thread.sleep(forTimeInterval: 1)
        let focused = XCUIScreen.main.screenshot()
        add(XCTAttachment(screenshot: focused))
        XCTAssertEqual(card(1).frame, frame, "focus must not move or resize the card")
        XCTAssertEqual(try pixels(unfocused, board), try pixels(focused, board),
                       "the board's pixels must not move between unfocused and focused")
        /// The most amber pixel in the band: red well above blue.
        func amber(_ bytes: [UInt8]) -> Int {
            stride(from: 0, to: bytes.count, by: 4).map { Int(bytes[$0]) - Int(bytes[$0 + 2]) }.max() ?? 0
        }
        XCTAssertLessThan(amber(try pixels(unfocused, ring)), 0x30, "no outline while unfocused")
        XCTAssertGreaterThan(amber(try pixels(focused, ring)), 0x80, "the primary outline at the focused card's edge")
        // And it's outside the board: the board band above is unchanged.
    }

    /// A5 (07b A3 `166:149722`): exactly one panel fits this TV (its grid is
    /// close to 16:9; "Only 1" is a 22 × 6 strip), nothing set to open at
    /// launch: Panels offers "Always open …?" in the side slot. Not now
    /// dismisses it for good, and focus goes to the card it was about as
    /// the grid goes back to two columns.
    func testTheOpenAtLaunchOfferIsAskedOnce() throws {
        continueAfterFailure = false
        let (app, _, _) = try launchPlainFixture(prefix: "Only", count: 2,
                                                 arguments: ["-fiestaboard.panels.openAtLaunchOffered", "NO"],
                                                 fields: [1: ["rows": 6, "cols": 22]])
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Only 0,")).firstMatch
        let strip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Only 1,")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Always open Only 0?"].waitForExistence(timeout: 5))
        let accept = app.buttons["Always open"], dismiss = app.buttons["Not now"]
        XCTAssertTrue(accept.exists && dismiss.exists)
        waitForFocus(card)
        capture(app, "Panels — open-at-launch offer")
        XCUIRemote.shared.press(.right)
        waitForFocus(accept, "Right from the card reaches the offer")
        XCUIRemote.shared.press(.right)
        waitForFocus(dismiss)
        XCUIRemote.shared.press(.select)
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == NO"),
                                             object: app.staticTexts["Always open Only 0?"])
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed, "Not now dismisses the offer")
        waitForFocus(card, "focus goes to the card the offer was about")
        XCTAssertGreaterThan(strip.frame.minX, card.frame.maxX, "two columns again: the strip beside it")

        // Asked once: a relaunch (the answer persisted) doesn't ask again.
        app.terminate()
        app.launchArguments.removeLast(2)
        app.launch()
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        waitForFocus(card)
        XCTAssertFalse(app.staticTexts["Always open Only 0?"].exists, "the offer is asked once")
    }

    /// Down from the right column into a lone last card, with nothing
    /// directly beneath: the row's focus section takes it. Seven panels.
    func testRemoteCrossesFromTheRightColumnIntoALoneLastCard() throws {
        continueAfterFailure = false
        let (app, _, _) = try launchPlainFixture(prefix: "Lone", count: 7)
        func card(_ index: Int) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Lone \(index),")).firstMatch
        }
        XCTAssertTrue(card(0).waitForExistence(timeout: 15))
        waitForFocus(card(0))
        XCUIRemote.shared.press(.right)
        waitForFocus(card(1))
        for index in [3, 5] {
            XCUIRemote.shared.press(.down)
            waitForFocus(card(index))
        }
        XCUIRemote.shared.press(.down)
        waitForFocus(card(6), "Down from the right column should reach the lone last card")
    }

    /// A foreground refresh that moves the focused card into another row
    /// keeps focus on that card. The card is rebuilt in its new row, and the
    /// focus engine had moved focus to the neighbour that took its place.
    func testARefreshThatMovesTheFocusedCardKeepsItsFocus() throws {
        continueAfterFailure = false
        let (app, server, panels) = try launchPlainFixture(prefix: "Shift", count: 6)
        func card(_ index: Int) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Shift \(index),")).firstMatch
        }
        XCTAssertTrue(card(0).waitForExistence(timeout: 15))
        waitForFocus(card(0))
        XCUIRemote.shared.press(.down)
        waitForFocus(card(2))
        // Removing Shift 0 moves Shift 2 from row 1 (left) to row 0 (right).
        server.updatePanels("{\"panels\":[\(panels.dropFirst().joined(separator: ","))],\"total\":5}")
        XCUIDevice.shared.press(.home)
        app.activate()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == NO"), object: card(0))
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed, "The refresh should drop Shift 0")
        waitForFocus(card(2), "A refresh that moves the focused card must keep the user's place")
    }

    /// More panels than the thumbnail working set, mixing dense matrices and
    /// split-flap boards. Revisit evicted rows using the real remote focus engine.
    func testRemoteCanRevisitRowsBeyondThePreviewCacheCapacity() throws {
        continueAfterFailure = false
        let app = try launchStressFixture()
        func card(_ index: Int) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Stress \(index),")).firstMatch
        }
        func waitForPreviews(inRowStartingWith index: Int) {
            for item in index...(index + 1) {
                let ready = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "label CONTAINS %@", "Board reads:"), object: card(item))
                XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed,
                               "Navigation must exercise loaded previews, not placeholders")
                // "Board reads:" comes from the model; this is the picture
                // itself, which only rows near the viewport draw. A preview
                // window that stopped following the scroll leaves it unset.
                let drawn = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "value == %@", "Preview drawn"), object: card(item))
                XCTAssertEqual(XCTWaiter.wait(for: [drawn], timeout: 5), .completed,
                               "Stress \(item)'s board picture should be drawn once its row is on screen")
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

        // Restore a distant right-column card after leaving the browser.
        // Keep this after the full cache traversal.
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

    /// Controlled profiling experiment: identical cards and focus treatment,
    /// with the board image present or replaced by a plain field. Timings are
    /// diagnostic evidence; simulator frame budgets are not device assertions.
    func testWarmHorizontalFocusWithAndWithoutPreviewImages() throws {
        continueAfterFailure = false
        var panels: [String] = []
        var byID: [String: String] = [:]
        for index in 0..<2 {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(Fixtures.panelJSON.utf8)) as? [String: Any])
            let id = "warm-\(index)"
            object["id"] = id
            object["name"] = "Warm \(index)"
            object["render_style"] = "led_matrix"
            object["device_model_spec"] = ["geometry": ["kind": "pixels", "width": 636, "height": 352]]
            let json = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
            panels.append(json)
            byID[id] = json
        }
        let cells = Array(repeating: Array(repeating: 63, count: 30), count: 12)
        let frame = String(decoding: try JSONSerialization.data(withJSONObject:
            ["characters": cells, "rows": 12, "cols": 30, "message": "Warm preview"]), as: UTF8.self)
        let server = try FixtureHTTPServer(frameBody: frame,
            panelsBody: "{\"panels\":[\(panels.joined(separator: ","))],\"total\":2}", additionalPanels: byID)
        self.server = server
        let connection = "{\"host\":\"http://127.0.0.1:\(server.port)\",\"displayName\":\"Warm fixture\"}"
        let encoded = Data(connection.utf8).map { String(format: "%02x", $0) }.joined()
        for blank in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["-fiestaboard.connection", "<\(encoded)>", "-fiestaboard.signedOut", "NO",
                                   "-fiestaboard.panelProfile", "YES", "-fiestaboard.panelProfileBlank", blank ? "YES" : "NO"]
            app.launch()
            let cards = (0..<2).map { index in
                app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Warm \(index),")).firstMatch
            }
            XCTAssertTrue(cards[0].waitForExistence(timeout: 10))
            for card in cards {
                let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Board reads:"), object: card)
                XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
            }
            waitForFocus(cards[0])
            // Deliberately exclude startup/initial image work from this warm
            // interaction experiment. Readiness assertions above are separate.
            Thread.sleep(forTimeInterval: 3)
            for _ in 0..<6 {
                XCUIRemote.shared.press(.right)
                waitForFocus(cards[1])
                XCUIRemote.shared.press(.left)
                waitForFocus(cards[0])
            }
            // Leaving the grid flushes the app's opt-in timing recording.
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.buttons["Warm 0"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    /// Remote presses can return while tvOS is still transferring focus and
    /// scrolling the next row into view. Assert the eventual target, without
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
