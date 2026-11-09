import XCTest

/// A12 (PHASE-4-TV-PLAN §2.2): Apple's accessibility audit on every screen
/// the remote reaches without a physical Apple TV — the viewer and its
/// controls, Panels, Settings (each category and detail page) and OLED care.
///
/// The audit checks element descriptions (VoiceOver labels), hit regions,
/// contrast, clipped text, traits and element detection. Every finding fails
/// the test unless `waivers` names it with a reason. The hardware half
/// (a VoiceOver walk on a real Apple TV) is docs/HARDWARE-CHECKLIST.md §1.
@MainActor
final class AccessibilityAuditUITests: XCTestCase {
    private var server: FixtureHTTPServer?

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    override func tearDown() {
        server = nil
        super.tearDown()
    }

    static let auditTypes: XCUIAccessibilityAuditType = [
        .sufficientElementDescription, .hitRegion, .contrast, .textClipped, .elementDetection, .trait,
    ]

    /// A finding the audit reports that is not a real failure, matched on the
    /// audit type and the element's label or identifier. Each needs a reason.
    struct Waiver {
        let type: XCUIAccessibilityAuditType
        let element: String
        let reason: String
    }

    static let waivers: [Waiver] = [
        // Connect's address field is the system TVTextField. The audit warns
        // it "may be clipped at larger Dynamic Type sizes", but tvOS has no
        // Dynamic Type setting (HIG Typography: tvOS doesn't support Dynamic
        // Type), so no viewer can reach a larger size. Its label is the
        // field's own placeholder layer, also reported.
        Waiver(type: .textClipped, element: "this SwiftUI.TVTextField", reason: "tvOS has no Dynamic Type"),
        Waiver(type: .textClipped, element: "this UITextFieldLabel", reason: "the same field's placeholder label (UITextFieldLabel)"),
    ]

    private func launch(signedIn: Bool = true) -> XCUIApplication {
        let frameLoaded = XCTestExpectation(description: "The viewer requested its frame")
        frameLoaded.assertForOverFulfill = false
        var characters = Array(repeating: Array(repeating: 0, count: 30), count: 12)
        characters[5].replaceSubrange(9..<20, with: [6, 9, 5, 19, 20, 1, 2, 15, 1, 18, 4])
        let frame = try! JSONSerialization.data(withJSONObject: [
            "characters": characters, "rows": 12, "cols": 30, "message": "FIESTABOARD",
        ])
        let server = try! FixtureHTTPServer(frameBody: String(decoding: frame, as: UTF8.self),
                                            onFrame: { frameLoaded.fulfill() })
        self.server = server
        let app = XCUIApplication()
        if signedIn {
            let connection = """
            {"host":"http://127.0.0.1:\(server.port)","displayName":"Test Board","defaultPanelRef":"1"}
            """
            let encoded = Data(connection.utf8).map { String(format: "%02x", $0) }.joined()
            app.launchArguments = ["-fiestaboard.connection", "<\(encoded)>", "-fiestaboard.signedOut", "NO"]
        } else {
            app.launchArguments = ["-fiestaboard.signedOut", "YES"]
        }
        app.launch()
        if signedIn {
            wait(for: [frameLoaded], timeout: 10)
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "taco-loader").firstMatch
                .waitForNonExistence(timeout: 5))
        }
        return app
    }

    /// Run the audit and fail on every finding that isn't waived.
    private func audit(_ screen: String, _ app: XCUIApplication,
                       file: StaticString = #filePath, line: UInt = #line) {
        var findings: [String] = []
        do {
            try app.performAccessibilityAudit(for: Self.auditTypes) { issue in
                let element = issue.element.map { "\($0.label)|\($0.identifier)|\($0.elementType.rawValue)" } ?? "(none)"
                let subject = element + " " + issue.detailedDescription
                let waived = Self.waivers.contains { $0.type == issue.auditType && subject.contains($0.element) }
                if !waived {
                    findings.append("\(issue.auditType.rawValue) \(issue.compactDescription) — \(element): \(issue.detailedDescription)")
                }
                return true
            }
        } catch {
            XCTFail("\(screen): the audit could not run: \(error)", file: file, line: line)
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "a12-audit-\(screen)"
        shot.lifetime = .keepAlways
        add(shot)
        for finding in findings {
            XCTFail("\(screen): \(finding)", file: file, line: line)
        }
    }

    private func rowHasFocus(_ label: String, in app: XCUIApplication) -> Bool {
        let row = app.buttons[label]
        let cell = app.cells.containing(.button, identifier: label).firstMatch
        return row.exists && (row.hasFocus || (cell.exists && cell.hasFocus))
    }

    private func focus(_ label: String, in app: XCUIApplication, moving direction: XCUIRemote.Button = .down,
                       file: StaticString = #filePath, line: UInt = #line) -> Bool {
        for step in [direction, direction == .down ? .up : .down] as [XCUIRemote.Button] {
            for _ in 0..<16 {
                if rowHasFocus(label, in: app) { return true }
                XCUIRemote.shared.press(step)
            }
        }
        XCTFail("Could not focus \(label)", file: file, line: line)
        return false
    }

    private func openSettings(_ app: XCUIApplication) {
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Panels"].waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.right)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
    }

    // MARK: Screens

    func testTheViewerAndItsControls() {
        let app = launch()
        audit("viewer", app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Panels"].waitForExistence(timeout: 3))
        audit("viewer-overlay", app)
    }

    func testPanels() {
        let app = launch()
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.staticTexts["Living Room"].waitForExistence(timeout: 5)
                      || app.buttons["Living Room"].waitForExistence(timeout: 5))
        audit("panels", app)
    }

    func testConnect() {
        let app = launch(signedIn: false)
        XCTAssertTrue(app.buttons.firstMatch.waitForExistence(timeout: 10))
        audit("connect", app)
    }

    func testEverySettingsCategory() {
        let app = launch()
        openSettings(app)
        audit("settings-this-tv", app)
        for category in ["Panel appearance", "Connection", "About & help"] {
            for _ in 0..<12 { XCUIRemote.shared.press(.up) }
            XCUIRemote.shared.press(.left)
            for _ in 0..<6 { XCUIRemote.shared.press(.up) }
            if focus(category, in: app) {
                XCUIRemote.shared.press(.select)
                sleep(1)
                audit("settings-\(category.lowercased().replacingOccurrences(of: " ", with: "-"))", app)
            }
        }
    }

    private func openCategory(_ label: String, in app: XCUIApplication) -> Bool {
        for _ in 0..<12 { XCUIRemote.shared.press(.up) }
        XCUIRemote.shared.press(.left)
        for _ in 0..<6 { XCUIRemote.shared.press(.up) }
        guard focus(label, in: app) else { return false }
        XCUIRemote.shared.press(.select)
        XCUIRemote.shared.press(.right)
        return true
    }

    func testOLEDCare() {
        let app = launch()
        openSettings(app)
        guard openCategory("This Apple TV", in: app), focus("settings.oledCare", in: app) else { return }
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["oled.brightness"].waitForExistence(timeout: 5))
        audit("oled-care", app)
    }

    func testSettingsDetailPages() {
        for page in ["Home screen shortcut", "Screen protection", "Privacy", "Licenses"] {
            let app = launch()
            openSettings(app)
            guard openCategory("About & help", in: app), focus(page, in: app) else { continue }
            XCUIRemote.shared.press(.select)
            sleep(1)
            audit("settings-\(page.lowercased().replacingOccurrences(of: " ", with: "-"))", app)
            app.terminate()
        }
    }
}
