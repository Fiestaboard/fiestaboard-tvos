import XCTest

/// Run with AnimationReview.xctestplan to retain Xcode's native screen videos.
/// Ordinary UI-test runs skip these deliberate holds. Frames arrive through the
/// same HTTP polling path as a real board; the app needs no recording-only UI.
@MainActor
final class AnimationReviewUITests: XCTestCase {
    private var server: FixtureHTTPServer?

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FIESTA_RECORD_REVIEW"] == "1",
                          "Use the AnimationReview test plan to record native review videos.")
    }

    override func tearDown() {
        server = nil
        super.tearDown()
    }

    func testSplitFlapMessageTransitions() throws {
        try record(style: .flap, rows: 12, cols: 29)
    }

    func testSplitFlapStress810TileTransitions() throws {
        try record(style: .flap, rows: 18, cols: 45, dense: true)
    }

    func testSquareLEDMessageTransitions() throws {
        try record(style: .square, rows: 12, cols: 29)
    }

    func testTransitionsOnRoundLEDs() throws {
        try record(style: .round, rows: 12, cols: 29)
    }

    func testSquareLEDRowScan() throws {
        try record(style: .square, rows: 12, cols: 29, effect: "rowScan")
    }

    func testRoundLEDRowScan() throws {
        try record(style: .round, rows: 12, cols: 29, effect: "rowScan")
    }

    func testSquareLEDPixelDissolve() throws {
        try record(style: .square, rows: 12, cols: 29, effect: "pixelDissolve")
    }

    func testRoundLEDPixelDissolve() throws {
        try record(style: .round, rows: 12, cols: 29, effect: "pixelDissolve")
    }

    func testSquareLEDSteppedMarquee() throws {
        try record(style: .square, rows: 12, cols: 29, effect: "marquee")
    }

    func testRoundLEDSteppedMarquee() throws {
        try record(style: .round, rows: 12, cols: 29, effect: "marquee")
    }

    private enum Style: String {
        case flap, square, round
    }

    private func record(style: Style, rows: Int, cols: Int, dense: Bool = false,
                        effect: String = "characterWipe") throws {
        let name = style == .flap ? "Split Flap Review" : "\(style.rawValue.capitalized) LED Review"
        let ref = "animation-review-\(style.rawValue)-\(rows)x\(cols)"
        let messages = ["WELCOME TO FIESTABOARD", "MAKE EVERY DAY A FIESTA",
                        "GOOD FOOD GREAT COMPANY", "SEE YOU AT THE NEXT FIESTA"]
        let bodies = try messages.enumerated().map { index, message in
            try frame(message: message, rows: rows, cols: cols, phase: index, dense: dense)
        }
        let frames = ReviewFrameStore(bodies[0])
        var panel = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(Fixtures.panelJSON.utf8)) as? [String: Any])
        panel["id"] = ref
        panel["name"] = name
        panel["rows"] = rows
        panel["cols"] = cols
        panel["animations_enabled"] = true
        panel["auto_dim"] = ["enabled": false, "start": "22:00", "end": "07:00"]
        panel["render_style"] = style == .flap ? "split_flap" : "led_matrix"
        panel["matrix_sizing"] = "fill_tv"
        if style != .flap {
            panel["device_model_spec"] = [
                "geometry": ["kind": "pixels", "width": 192, "height": 96],
                "font": "5x7",
                "appearance": ["pixelShape": style.rawValue, "dotRatio": 0.82]
            ]
        }
        let panelBody = try json(panel)
        let fixture = try FixtureHTTPServer(frameProvider: { frames.body },
                                            panelsBody: try json(["panels": [panel], "total": 1]),
                                            additionalPanels: [ref: panelBody])
        server = fixture
        let connection = try json(["host": "http://127.0.0.1:\(fixture.port)",
                                   "displayName": "Animation Review", "defaultPanelRef": ref])
        let encoded = Data(connection.utf8).map { String(format: "%02x", $0) }.joined()
        let app = XCUIApplication()
        app.launchArguments = ["-fiestaboard.connection", "<\(encoded)>",
                               "-fiestaboard.signedOut", "NO", "-fiestaboard.sizing", "fit",
                               "-fiestaboard.renderProfile", "YES",
                               "-fiestaboard.matrix.transitionStyle", effect]
        app.launch()
        let board = app.buttons[name]
        XCTAssertTrue(board.waitForExistence(timeout: 15), "The recording must show the app's viewer")
        waitForMessage(messages[0], board: board)
        Thread.sleep(forTimeInterval: 2)

        for index in 1..<messages.count {
            frames.body = bodies[index]
            waitForMessage(messages[index], board: board)
            // Accessibility changes on receipt. Leave the real renderer time
            // to finish the drum turn or LED effect and show a stable frame.
            Thread.sleep(forTimeInterval: style == .flap ? 6 : 5)
        }
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertFalse(app.buttons["Settings"].exists, "Review clips should keep controls hidden")
        Thread.sleep(forTimeInterval: 2)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "\(name) — \(rows * cols) source cells — final frame"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForMessage(_ message: String, board: XCUIElement) {
        let received = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", message), object: board)
        XCTAssertEqual(XCTWaiter.wait(for: [received], timeout: 10), .completed,
                       "The visible viewer must receive \(message)")
    }

    private func frame(message: String, rows: Int, cols: Int, phase: Int, dense: Bool) throws -> String {
        var cells = (0..<rows).map { row in
            (0..<cols).map { col in dense ? 1 + (row * cols + col + phase * 7) % 26 : 0 }
        }
        // Color stripes exercise the painted flaps and LED color transitions.
        for col in 0..<cols {
            cells[1][col] = 63 + (col / 4 + phase) % 6
            cells[rows - 2][col] = 63 + (5 + col / 4 - phase) % 6
        }
        let codes = message.utf8.map { byte -> Int in
            (65...90).contains(byte) ? Int(byte - 64) : 0
        }
        let start = max(0, (cols - codes.count) / 2)
        cells[rows / 2] = Array(repeating: 0, count: cols)
        for (offset, code) in codes.prefix(cols).enumerated() { cells[rows / 2][start + offset] = code }
        return try json(["characters": cells, "message": message, "rows": rows, "cols": cols])
    }

    private func json(_ object: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
}

/// The UI-test thread writes while Network's serial queue serves a poll.
private final class ReviewFrameStore {
    private let lock = NSLock()
    private var storedBody: String

    init(_ body: String) { storedBody = body }

    var body: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedBody
        }
        set {
            lock.lock()
            storedBody = newValue
            lock.unlock()
        }
    }
}
