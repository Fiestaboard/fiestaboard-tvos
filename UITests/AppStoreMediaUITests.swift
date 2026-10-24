import XCTest

/// Shipping UI + real HTTP polling. Only the local board's example content and
/// sign-in approval are fixtures; the app performs every render and transition.
@MainActor
final class AppStoreMediaUITests: XCTestCase {
    private var server: FixtureHTTPServer?
    private var shots: [[String: String]] = []
    private var events: [[String: Any]] = []
    private let storeShots = ["01-weather", "02-departures", "03-home-note", "04-dinner-note",
                              "05-pixel-clock", "06-sunset", "07-starlight", "08-panels-first-row",
                              "09-panels-second-row", "10-tv-settings"]
    private let reviewShots = ["review-connect", "review-sign-in", "review-device-code", "review-end"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FIESTA_APP_STORE_MEDIA"] == "1",
                          "App Store media runs only in its dedicated capture workflow.")
    }

    override func tearDown() { server = nil; super.tearDown() }

    func testReviewerWalkthroughAndScreenshots() throws {
        let catalog = try MediaBoards.catalog()
        let frames = MediaFrameStore(catalog.frames)
        let fixture = try FixtureHTTPServer(panelsBody: json(["panels": catalog.panels, "total": catalog.panels.count]),
                                            additionalPanels: catalog.panelsByID,
                                            additionalFrameProvider: { frames.body(for: $0) },
                                            tvSignInEnabled: true, approveDeviceSignIn: true)
        server = fixture
        let app = XCUIApplication()
        app.launchArguments = ["-fiestaboard.connection", "<>", "-fiestaboard.signedOut", "NO",
                               "-fiestaboard.discoveryFixture", "http://127.0.0.1:\(fixture.port)/__fixtures/discovery",
                               "-fiestaboard.sizing", "fit", "-fiestaboard.matrix.transitionStyle", "pixelDissolve"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.textFields["FiestaBoard address"].waitForExistence(timeout: 15))
        fixture.releaseDiscoveredBoard(name: "Home FiestaBoard")
        let discovered = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Home FiestaBoard,")).firstMatch
        XCTAssertTrue(discovered.waitForExistence(timeout: 10))
        capture("review-connect", app: app, hold: 2)
        focus(discovered, direction: .up, app: app)
        XCUIRemote.shared.press(.select)
        let phone = app.buttons["device-sign-in"]
        XCTAssertTrue(phone.waitForExistence(timeout: 10))
        capture("review-sign-in", app: app, hold: 2)
        focus(phone, direction: .up, app: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["device-new-code"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "W D J B")).firstMatch.waitForExistence(timeout: 3))
        capture("review-device-code", app: app)

        XCTAssertTrue(card("Weather", app: app).waitForExistence(timeout: 20))
        waitForValue("Board reads:", element: card("Departures", app: app), key: "label")
        capture("08-panels-first-row", app: app, hold: 2)
        focus(card("Weather", app: app), direction: .left, app: app)
        openFocusedPanel("Weather", message: "San Francisco", app: app)
        capture("01-weather", app: app, hold: 3)

        returnToPanels(app)
        XCUIRemote.shared.press(.right)
        focus(card("Departures", app: app), direction: .right, app: app)
        openFocusedPanel("Departures", message: "Coast Line", app: app)
        capture("02-departures", app: app, hold: 3)

        returnToPanels(app)
        XCUIRemote.shared.press(.down)
        XCUIRemote.shared.press(.left)
        focus(card("Home Notes", app: app), direction: .left, app: app)
        capture("09-panels-second-row", app: app, hold: 2)
        openFocusedPanel("Home Notes", message: "You make this place feel like home", app: app)
        capture("03-home-note", app: app, hold: 2)
        event("split-flap-update-request", details: "Home note → dinner note; same panel and geometry; HTTP frame update")
        frames.set(try MediaBoards.personal(dinner: true), for: "media-notes")
        waitForValue("Dinner together at 7:00", element: app.buttons["Home Notes"])
        event("split-flap-frame-received", details: "Accessibility received new HTTP frame; native drum animation is running")
        Thread.sleep(forTimeInterval: 6)
        event("split-flap-settled", details: "Six seconds after frame receipt; native split-flap animation has settled")
        capture("04-dinner-note", app: app, hold: 2)

        returnToPanels(app)
        XCUIRemote.shared.press(.right)
        focus(card("Pixel Clock", app: app), direction: .right, app: app)
        openFocusedPanel("Pixel Clock", message: "8:42", app: app)
        capture("05-pixel-clock", app: app, hold: 3)

        returnToPanels(app)
        XCUIRemote.shared.press(.down)
        focus(card("Pixel Landscape", app: app), direction: .down, app: app)
        openFocusedPanel("Pixel Landscape", message: "Golden hour", app: app)
        capture("06-sunset", app: app, hold: 2)
        event("led-update-request", details: "Golden-hour landscape → starlight; same round LED panel; HTTP canvas-layer update")
        frames.set(try MediaBoards.landscape(night: true), for: "media-landscape")
        waitForValue("Starlight", element: app.buttons["Pixel Landscape"])
        event("led-frame-received", details: "Accessibility received new HTTP frame; native pixel-dissolve effect is running")
        Thread.sleep(forTimeInterval: 4)
        event("led-settled", details: "Four seconds after frame receipt; native pixel dissolve has settled")
        capture("07-starlight", app: app, hold: 3)

        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Panels"].waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(app.buttons["Settings"].hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Applies to every viewer of this panel."].waitForExistence(timeout: 5))
        focus(app.buttons["This Apple TV"], direction: .up, app: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Applies only to this Apple TV."].waitForExistence(timeout: 3))
        capture("10-tv-settings", app: app, hold: 3)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["Pixel Landscape"].waitForExistence(timeout: 5))
        capture("review-end", app: app, hold: 2)
        let index: [String: Any] = ["version": 2, "expectedStoreScreenshots": storeShots,
                                   "expectedReviewScreenshots": reviewShots, "shots": shots, "events": events,
                                   "start": "review-connect", "end": "review-end",
                                   "content": "Original illustrative data and pixel art; no live weather, clock, or transit feed is connected."]
        let attachment = XCTAttachment(data: Data(try json(index).utf8), uniformTypeIdentifier: "public.json")
        attachment.name = "AppStore-media-index.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(app.state, .runningForeground)
    }

    private func card(_ name: String, app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + ",")).firstMatch
    }

    private func focus(_ element: XCUIElement, direction: XCUIRemote.Button, app: XCUIApplication) {
        for _ in 0..<8 {
            if element.hasFocus { return }
            let identifier = element.identifier.isEmpty ? element.label : element.identifier
            // Full board speech can exceed XCTest's 128-character limit for
            // identifier queries. A predicate also supports native List cells.
            let cell = app.cells.containing(NSPredicate(format: "identifier == %@ OR label == %@", identifier, element.label)).firstMatch
            if cell.exists && cell.hasFocus { return }
            XCUIRemote.shared.press(direction)
        }
        XCTFail("Could not focus \(element.label)")
    }

    private func waitForValue(_ value: String, element: XCUIElement, key: String = "value") {
        let received = XCTNSPredicateExpectation(predicate: NSPredicate(format: "%K CONTAINS %@", key, value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [received], timeout: 15), .completed)
    }

    private func openFocusedPanel(_ name: String, message: String, app: XCUIApplication) {
        event("panel-switch", details: name)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 10))
        waitForValue(message, element: app.buttons[name])
        // A newly opened panel has no old raster to transition from. Give the
        // actual renderer two seconds before capturing the first settled view.
        Thread.sleep(forTimeInterval: 2)
        // These deliberately varied grids can trigger the app's normal size
        // offer. Keep their authored dimensions through the real Later action.
        let later = app.buttons["Later"]
        if later.exists {
            focus(later, direction: .right, app: app)
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(later.waitForNonExistence(timeout: 5))
            event("resize-offer-dismissed", details: name + ": chose Later to preserve its authored grid")
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertFalse(app.buttons["Resize for this TV"].exists)
        XCTAssertTrue(app.buttons["Settings"].waitForNonExistence(timeout: 6), "Viewer controls must hide before capture")
    }

    private func returnToPanels(_ app: XCUIApplication) {
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.staticTexts["Panels"].waitForExistence(timeout: 5))
    }

    private func capture(_ name: String, app: XCUIApplication, hold: TimeInterval = 0) {
        if storeShots.contains(name) {
            XCTAssertFalse(app.buttons["Later"].exists, "Listing screenshots must not contain a resize offer")
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "AppStore-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        shots.append(["name": name, "role": storeShots.contains(name) ? "store" : "review"])
        if hold > 0 { Thread.sleep(forTimeInterval: hold) }
    }

    private func event(_ name: String, details: String) {
        events.append(["event": name, "timestamp": Date().timeIntervalSince1970, "details": details])
    }

    private func json(_ object: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
}

/// UI-test writes and Network's serial queue reads use the same lock.
private final class MediaFrameStore {
    private let lock = NSLock()
    private var frames: [String: String]
    init(_ frames: [String: String]) { self.frames = frames }
    func body(for ref: String) -> String? { lock.lock(); defer { lock.unlock() }; return frames[ref] }
    func set(_ body: String, for ref: String) { lock.lock(); frames[ref] = body; lock.unlock() }
}

/// Five intentionally different compositions; all artwork/data is original and
/// illustrative. These are normal characters, rich cells and RGBA canvas layers.
private enum MediaBoards {
    struct Catalog { let panels: [[String: Any]]; let panelsByID: [String: String]; let frames: [String: String] }

    static func catalog() throws -> Catalog {
        let definitions: [(String, String, Int, Int, String, String?, Int, Int)] = [
            ("media-weather", "Weather", 8, 24, "black", nil, 0, 0),
            ("media-transit", "Departures", 8, 28, "black", nil, 0, 0),
            ("media-notes", "Home Notes", 6, 18, "white", nil, 0, 0),
            ("media-clock", "Pixel Clock", 9, 21, "black", "square", 128, 72),
            ("media-landscape", "Pixel Landscape", 7, 16, "black", "round", 96, 54)
        ]
        var panels: [[String: Any]] = [], byID: [String: String] = [:]
        for (index, item) in definitions.enumerated() {
            let (id, name, rows, cols, color, shape, width, height) = item
            var panel = try JSONSerialization.jsonObject(with: Data(Fixtures.panelJSON.utf8)) as! [String: Any]
            panel["id"] = id; panel["short_code"] = index + 1; panel["name"] = name
            panel["rows"] = rows; panel["cols"] = cols; panel["board_color"] = color
            panel["animations_enabled"] = true
            panel["device_type"] = id == "media-weather" ? "vestaboard" : "note_array"
            panel["code62_glyph"] = id == "media-weather" ? "degree" : "heart"
            panel["auto_dim"] = ["enabled": false, "start": "22:00", "end": "07:00"]
            if let shape {
                panel["render_style"] = "led_matrix"; panel["matrix_sizing"] = "fill_tv"
                panel["device_model_spec"] = ["geometry": ["kind": "pixels", "width": width, "height": height],
                    "font": "5x7", "appearance": ["pixelShape": shape, "dotRatio": 0.82]]
            }
            panels.append(panel); byID[id] = try json(panel)
        }
        return Catalog(panels: panels, panelsByID: byID, frames: [
            "media-weather": try weather(), "media-transit": try departures(), "media-notes": try personal(dinner: false),
            "media-clock": try clock(), "media-landscape": try landscape(night: false)])
    }

    private static func code(_ character: Character) -> Int {
        if let i = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".firstIndex(of: character) { return "ABCDEFGHIJKLMNOPQRSTUVWXYZ".distance(from: "ABCDEFGHIJKLMNOPQRSTUVWXYZ".startIndex, to: i) + 1 }
        if let i = "1234567890".firstIndex(of: character) { return "1234567890".distance(from: "1234567890".startIndex, to: i) + 27 }
        return ["!": 37, "-": 44, "+": 46, "&": 47, ":": 50, "'": 52, "%": 54, ".": 56, "/": 59, "°": 62, "♥": 62][String(character)] ?? 0
    }
    private static func text(_ value: String, row: Int, col: Int? = nil, grid: inout [[Int]]) {
        let letters = Array(value.uppercased()); let start = col ?? max(0, (grid[row].count - letters.count) / 2)
        for (offset, letter) in letters.enumerated() where start + offset < grid[row].count { grid[row][start + offset] = code(letter) }
    }
    private static func payload(_ cells: [[Int]], message: String) throws -> String {
        try json(["characters": cells, "rows": cells.count, "cols": cells[0].count, "message": message])
    }
    static func weather() throws -> String {
        var grid = Array(repeating: Array(repeating: 0, count: 24), count: 8)
        text("SAN FRANCISCO", row: 0, grid: &grid)
        for (r, line) in ["..#..", ".###.", "#####", ".###.", "..#.."].enumerated() {
            for (c, p) in line.enumerated() where p == "#" { grid[r + 2][c + 2] = r == 2 ? 64 : 65 }
        }
        text("68°F", row: 2, col: 11, grid: &grid); text("SUNNY", row: 4, col: 10, grid: &grid)
        text("H 70°  L 55°", row: 6, col: 10, grid: &grid)
        text("WIND W 8 MPH", row: 7, grid: &grid)
        return try payload(grid, message: "San Francisco. Sunny, 68 degrees. High 70, low 55. Example weather.")
    }
    static func departures() throws -> String {
        var grid = Array(repeating: Array(repeating: 0, count: 28), count: 8)
        text("NEXT DEPARTURES", row: 0, grid: &grid)
        for col in 2..<26 { grid[1][col] = 64 }
        text("COAST LINE       2 MIN", row: 3, col: 4, grid: &grid)
        text("HARBOR LOCAL     8 MIN", row: 5, col: 4, grid: &grid)
        text("AIRPORT         25 MIN", row: 7, col: 4, grid: &grid)
        grid[3][1] = 66; grid[5][1] = 67; grid[7][1] = 65
        return try payload(grid, message: "Coast Line 2 minutes. Harbor Local 8 minutes. Airport 25 minutes. Example departures.")
    }
    static func personal(dinner: Bool) throws -> String {
        var grid = Array(repeating: Array(repeating: 0, count: 18), count: 6)
        let lines = dinner ? ["", "DINNER", "TOGETHER", "AT 7:00", "♥ ♥ ♥", ""]
                           : ["", "YOU MAKE", "THIS PLACE", "FEEL LIKE", "HOME ♥", ""]
        for (row, line) in lines.enumerated() { text(line, row: row, grid: &grid) }
        for row in 1..<5 { grid[row][1] = dinner ? 64 : 68; grid[row][16] = dinner ? 64 : 68 }
        return try payload(grid, message: dinner ? "Dinner together at 7:00. Hearts." : "You make this place feel like home. Heart.")
    }
    static func clock() throws -> String {
        let width = 104, height = 34
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 3, to: rgba.count, by: 4) { rgba[i] = 255 }
        func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int) {
            for py in y..<(y + h) { for px in x..<(x + w) {
                let i = (py * width + px) * 4; rgba[i] = 255; rgba[i + 1] = 176; rgba[i + 2] = 32
            } }
        }
        let segments = [[0,1,2,3,4,5], [1,2], [0,1,6,4,3], [0,1,6,2,3], [5,6,1,2], [0,5,6,2,3], [0,5,6,4,2,3], [0,1,2], [0,1,2,3,4,5,6], [0,1,2,3,5,6]]
        let positions = [(0,0,14,3),(11,2,3,12),(11,15,3,12),(0,26,14,3),(0,15,3,12),(0,2,3,12),(0,13,14,3)]
        for (offset, digit) in [0,8,4,2].enumerated() {
            let origin = 6 + offset * 22 + (offset >= 2 ? 4 : 0)
            for segment in segments[digit] { let (x,y,w,h) = positions[segment]; rect(origin+x, y+2, w, h) }
        }
        rect(47, 11, 3, 3); rect(47, 22, 3, 3)
        var cells = Array(repeating: Array(repeating: ["type": "char", "value": " ", "color": "#70DDB0"], count: 21), count: 9)
        for (row, string) in [(0,"GOOD MORNING"), (7,"SAT 24 OCT")] {
            let start = (21 - string.count) / 2
            for (offset, c) in string.enumerated() { cells[row][start + offset]["value"] = String(c) }
        }
        return try json(["characters": NSNull(), "cells": cells, "rows": 9, "cols": 21,
                         "message": "8:42. Good morning. Saturday 24 October. Example clock.",
                         "layers": [["x": 12, "y": 16, "width": width, "height": height, "rgba": Data(rgba).base64EncodedString()]]])
    }
    static func landscape(night: Bool) throws -> String {
        let width = 96, height = 54
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        func pixel(_ x: Int, _ y: Int, _ color: (UInt8, UInt8, UInt8)) {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            let i = (y * width + x) * 4; bytes[i] = color.0; bytes[i+1] = color.1; bytes[i+2] = color.2; bytes[i+3] = 255
        }
        for y in 0..<height { for x in 0..<width {
            let color: (UInt8,UInt8,UInt8) = night
                ? (UInt8(5 + y/5), UInt8(9 + y/3), UInt8(30 + y))
                : (UInt8(70 + y*3), UInt8(55 + y), UInt8(125 - y))
            pixel(x,y,color)
        } }
        for y in 5..<30 { for x in 5..<40 {
            let disc = (x-23)*(x-23)+(y-18)*(y-18) < 100
            let cutout = night && (x-27)*(x-27)+(y-14)*(y-14) < 100
            if disc && !cutout { pixel(x,y,night ? (215,235,255) : (255,214,105)) }
        } }
        if night { for (x,y) in [(8,5),(38,9),(51,5),(64,15),(77,7),(87,21),(43,21)] {
            pixel(x,y,(210,232,255)); pixel(x-1,y,(95,143,210)); pixel(x+1,y,(95,143,210))
        } }
        for x in 0..<width {
            let ridge = 23 + abs(x-27)/3 + ((x/9)%3)
            for y in min(53,ridge)..<height { pixel(x,y,night ? (24,35,75) : (89,66,129)) }
            let near = 35 + abs(x-70)/5
            for y in min(53,near)..<height { pixel(x,y,night ? (11,24,45) : (28,70,88)) }
        }
        for y in 36..<height {
            let half = 1 + (y-36)/3; let center = 45 + (y-36)/4
            for x in (center-half)...(center+half) { pixel(x,y,night ? (49,91,134) : (83,179,188)) }
        }
        for (tx,ty) in [(8,32),(17,38),(80,34),(89,42)] {
            let ink: (UInt8,UInt8,UInt8) = night ? (4,13,24) : (9,42,48)
            for dy in 0..<10 { for dx in -(dy/3)...(dy/3) { pixel(tx+dx,ty+dy,ink) } }
            for dy in 10..<14 { pixel(tx,ty+dy,ink) }
        }
        return try json(["characters": NSNull(), "rows": 7, "cols": 16,
                         "message": night ? "Starlight. Original moonlit mountain pixel landscape." : "Golden hour. Original sunset mountain pixel landscape.",
                         "layers": [["x": 0, "y": 0, "width": width, "height": height, "rgba": Data(bytes).base64EncodedString()]]])
    }
    private static func json(_ object: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
}
