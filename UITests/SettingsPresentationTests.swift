import XCTest

/// These exercise the app's Menu handling: a detail must return to its parent,
/// while leaving the settings root returns to the viewer that opened it.
@MainActor
final class SettingsPresentationTests: XCTestCase {
    private var server: FixtureHTTPServer?

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        server = nil
        super.tearDown()
    }

    private func launchSettings(includeSecondPanel: Bool = false, matrixPanel: Bool = false, localSettings: Bool = true, holdPanelUpdates: Bool = false) -> XCUIApplication {
        let frameLoaded = expectation(description: "Viewer loaded")
        let secondPanel = Fixtures.panelJSON
            .replacingOccurrences(of: "abc123def456", with: "kitchen-panel")
            .replacingOccurrences(of: "\"short_code\":1", with: "\"short_code\":2")
            .replacingOccurrences(of: "Living Room", with: "Kitchen")
        var panels = includeSecondPanel
            ? "{\"panels\":[\(Fixtures.panelJSON),\(secondPanel)],\"total\":2}"
            : Fixtures.panelsList
        if matrixPanel {
            var panel = try! JSONSerialization.jsonObject(with: Data(Fixtures.panelJSON.utf8)) as! [String: Any]
            panel["render_style"] = "led_matrix"
            panel["matrix_sizing"] = NSNull()
            panel["matrix_pitch_mm"] = 6
            panel["device_model_spec"] = ["geometry": ["kind": "pixels", "width": 192, "height": 96]]
            panels = String(decoding: try! JSONSerialization.data(withJSONObject: ["panels": [panel], "total": 1]), as: UTF8.self)
        }
        var characters = Array(repeating: Array(repeating: 0, count: 30), count: 12)
        let letters = [6, 9, 5, 19, 20, 1, 2, 15, 1, 18, 4]
        characters[5].replaceSubrange(9..<20, with: letters)
        let frameData = try! JSONSerialization.data(withJSONObject: [
            "characters": characters, "rows": 12, "cols": 30, "message": "FIESTABOARD"
        ])
        server = try! FixtureHTTPServer(frameBody: String(decoding: frameData, as: UTF8.self),
                                       panelsBody: panels,
                                       additionalPanels: includeSecondPanel ? ["kitchen-panel": secondPanel, "2": secondPanel] : [:],
                                       holdPanelUpdates: holdPanelUpdates,
                                       onFrame: { frameLoaded.fulfill() })
        let app = XCUIApplication()
        let connection = """
        {"host":"http://127.0.0.1:\(server!.port)","displayName":"Test Board","defaultPanelRef":"1"}
        """
        let encoded = Data(connection.utf8).map { String(format: "%02x", $0) }.joined()
        app.launchArguments = ["-fiestaboard.connection", "<\(encoded)>",
                               "-fiestaboard.signedOut", "NO"]
        app.launch()
        wait(for: [frameLoaded], timeout: 10)
        XCTAssertTrue(app.progressIndicators.firstMatch.waitForNonExistence(timeout: 5))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Panels"].waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(app.buttons["Settings"].hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        if localSettings {
            // Viewer opens shared appearance; explicitly choose local controls
            // for tests of this TV's preferences. Focus starts on the first category.
            waitForRowFocus("This Apple TV", in: app)
            XCUIRemote.shared.press(.select)
        }
        return app
    }

    /// Native focus movement also verifies that the new category is reachable
    /// with a remote, rather than only by an accessibility activation.
    private func rowHasFocus(_ label: String, in app: XCUIApplication) -> Bool {
        let row = app.buttons[label]
        let cell = app.cells.containing(.button, identifier: label).firstMatch
        return row.exists && (row.hasFocus || (cell.exists && cell.hasFocus))
    }

    private func openRow(_ label: String, in app: XCUIApplication,
                         file: StaticString = #filePath, line: UInt = #line) {
        // SwiftUI List gives focus to the native cell on newer tvOS versions;
        // its nested accessibility Button can keep hasFocus=false throughout.
        for _ in 0..<24 {
            if rowHasFocus(label, in: app) {
                XCUIRemote.shared.press(.select)
                return
            }
            XCUIRemote.shared.press(.down)
        }
        XCTFail("Could not focus \(label)", file: file, line: line)
    }

    private func openCategory(_ label: String, in app: XCUIApplication) {
        // Lower controls can sit below the category column. Move back to
        // its vertical range before asking the focus engine to move left.
        for _ in 0..<12 { XCUIRemote.shared.press(.up) }
        XCUIRemote.shared.press(.left)
        for _ in 0..<6 { XCUIRemote.shared.press(.up) }
        openRow(label, in: app)
        XCUIRemote.shared.press(.right)
    }

    private func waitForRowFocus(_ label: String, in app: XCUIApplication,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            rowHasFocus(label, in: app)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed,
                       "Closing a choice list must restore focus to \(label)", file: file, line: line)
    }

    private func attachScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCategoriesSeparateLocalAndSharedSettings() {
        let app = launchSettings()
        for category in ["This Apple TV", "Panel appearance", "Connection", "About & help"] {
            XCTAssertTrue(app.buttons[category].exists)
        }
        XCTAssertTrue(app.staticTexts["Applies only to this Apple TV."].exists)
        attachScreenshot("Settings — This Apple TV", app: app)
        // Merely focusing a category must not swap the controls beneath the user.
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(rowHasFocus("Panel appearance", in: app))
        XCTAssertTrue(app.staticTexts["Applies only to this Apple TV."].exists)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Applies to every viewer of this panel."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["settings.panelPreview"].exists)
        let message = NSPredicate(format: "value == %@", "FIESTABOARD")
        expectation(for: message, evaluatedWith: app.otherElements["settings.panelPreview"])
        waitForExpectations(timeout: 5)
        attachScreenshot("Settings — Panel appearance", app: app)
    }

    func testCurrentPanelHasCompleteSharedDisplayControls() {
        let app = launchSettings(matrixPanel: true, localSettings: false)
        XCTAssertTrue(app.staticTexts["Applies to every viewer of this panel."].waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.right)
        openRow("All display settings", in: app)
        XCTAssertTrue(app.textFields["panelSettings.name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["panelSettings.name"].value as? String, "Living Room")
        XCTAssertTrue(app.staticTexts["Screen diagonal (3–200 inches)"].exists,
                      "An entered number must keep a visible label; placeholder-only fields lose their meaning")
        attachScreenshot("Shared panel display settings", app: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.otherElements["settings.panelPreview"].waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.menu)
        XCTAssertFalse(app.staticTexts["Settings"].exists)
    }

    func testSharedDisplaySaveKeepsFocusDuringFailureAndAllowsRetry() {
        let app = launchSettings(matrixPanel: true, localSettings: false, holdPanelUpdates: true)
        defer { server?.failHeldPanelUpdates() }
        XCUIRemote.shared.press(.right)
        openRow("All display settings", in: app)
        XCTAssertTrue(app.textFields["panelSettings.name"].waitForExistence(timeout: 5))
        // Change the draft through the remote, leaving the real board untouched.
        for _ in 0..<8 {
            let toggle = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Animations")).firstMatch
            let cell = app.cells.containing(.switch, identifier: toggle.label).firstMatch
            if toggle.hasFocus || (cell.exists && cell.hasFocus) { break }
            XCUIRemote.shared.press(.down)
        }
        XCUIRemote.shared.press(.select)
        openRow("panelSettings.save", in: app)
        let save = app.buttons["panelSettings.save"]
        let saving = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Saving…"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [saving], timeout: 5), .completed)
        XCTAssertTrue(save.isEnabled, "Saving must retain its focus owner while duplicate presses are guarded")
        XCTAssertTrue(rowHasFocus("panelSettings.save", in: app))
        let requestArrived = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            self?.server?.heldPanelUpdateCount == 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [requestArrived], timeout: 5), .completed)
        XCUIRemote.shared.press(.select)
        let duplicate = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            (self?.server?.heldPanelUpdateCount ?? 0) > 1
        }, object: nil)
        duplicate.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [duplicate], timeout: 1), .completed,
                       "Repeated Select must not send a duplicate save")
        server?.failHeldPanelUpdates()
        let retry = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Save changes"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [retry], timeout: 5), .completed)
        waitForRowFocus("panelSettings.save", in: app)
        XCTAssertFalse(app.staticTexts["panelSettings.saved"].exists)
        attachScreenshot("Shared settings — failed save retains focus", app: app)
        XCUIRemote.shared.press(.select)
        let retried = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            self?.server?.heldPanelUpdateCount == 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [retried], timeout: 5), .completed)
        XCTAssertTrue(rowHasFocus("panelSettings.save", in: app))
    }

    func testMatrixAppearanceExposesItsTransitionSwitch() {
        let app = launchSettings(matrixPanel: true)
        openCategory("Panel appearance", in: app)
        let transitions = app.switches["settings.animationToggle"]
        XCTAssertTrue(transitions.waitForExistence(timeout: 3))
        XCTAssertTrue(transitions.label.hasPrefix("Matrix transitions"))
        XCTAssertTrue(transitions.isEnabled)
    }

    func testMatrixSizeChoicesAreReachableWithTheRemote() {
        let app = launchSettings(matrixPanel: true)
        openCategory("This Apple TV", in: app)
        openRow("settings.matrixSizing", in: app)
        for label in ["Fill TV", "Fit panel", "True LED size"] {
            XCTAssertTrue(app.buttons[label].waitForExistence(timeout: 3)
                          || app.staticTexts[label].exists, "Missing matrix sizing choice: \(label)")
        }
        attachScreenshot("Matrix size choices", app: app)
        for _ in 0..<3 { XCUIRemote.shared.press(.up) }
        openRow("True LED size", in: app)
        XCTAssertTrue(app.buttons["TV size"].waitForExistence(timeout: 3))
        openRow("TV size", in: app)
        openRow("55 inches", in: app)
        XCTAssertEqual(app.buttons["TV size"].value as? String, "55 inches")
        openRow("LED spacing", in: app)
        openRow("8 mm", in: app)
        XCTAssertEqual(app.buttons["LED spacing"].value as? String, "8 mm")
        openCategory("This Apple TV", in: app)
        openRow("LED spacing", in: app)
        // A choice list remembers its selected row. Move above it before
        // choosing a smaller value with the down-only row helper.
        for _ in 0..<10 { XCUIRemote.shared.press(.up) }
        openRow("6 mm", in: app)
        openCategory("This Apple TV", in: app)
        openRow("settings.matrixSizing", in: app)
        for _ in 0..<3 { XCUIRemote.shared.press(.up) }
        openRow("Fill TV", in: app)
        XCTAssertEqual(app.buttons["settings.matrixSizing"].value as? String, "Fill TV")
    }

    func testPlaybackChoiceListsAreReachableWithTheRemote() {
        let app = launchSettings()
        openCategory("This Apple TV", in: app)
        openRow("Open at launch", in: app)
        XCTAssertTrue(app.buttons["Panel list"].waitForExistence(timeout: 3))
        openRow("Living Room", in: app)
        waitForRowFocus("Open at launch", in: app)
        openRow("Split-flap size", in: app)
        openRow("True flap size", in: app)
        waitForRowFocus("Split-flap size", in: app)
        XCTAssertEqual(app.buttons["Split-flap size"].value as? String, "True flap size")
        openCategory("This Apple TV", in: app)
        openRow("Split-flap size", in: app)
        for _ in 0..<3 { XCUIRemote.shared.press(.up) }
        openRow("Fit the screen", in: app)
        waitForRowFocus("Split-flap size", in: app)
        XCTAssertEqual(app.buttons["Split-flap size"].value as? String, "Fit the screen")
    }

    func testMatrixEffectChoicesAreReachableWithTheRemote() {
        let app = launchSettings(matrixPanel: true)
        openCategory("This Apple TV", in: app)
        openRow("settings.matrixTransitionStyle", in: app)
        for label in ["Character wipe", "Row scan", "Pixel dissolve", "Stepped marquee"] {
            XCTAssertTrue(app.buttons[label].waitForExistence(timeout: 3)
                          || app.staticTexts[label].exists, "Missing matrix effect: \(label)")
        }
        attachScreenshot("Matrix transition choices", app: app)
        for _ in 0..<4 { XCUIRemote.shared.press(.up) }
        openRow("Row scan", in: app)
        let setting = app.buttons["settings.matrixTransitionStyle"]
        XCTAssertTrue(setting.waitForExistence(timeout: 3))
        XCTAssertEqual(setting.value as? String, "Row scan")
        XCUIRemote.shared.press(.select)
        for _ in 0..<4 { XCUIRemote.shared.press(.up) }
        openRow("Character wipe", in: app)
        XCTAssertTrue(setting.waitForExistence(timeout: 3))
        XCTAssertEqual(setting.value as? String, "Character wipe")
    }

    func testMenuPopsPanelDetailBeforeLeavingSettings() {
        let app = launchSettings()
        openCategory("Panel appearance", in: app)
        openRow("Resize for this TV", in: app)
        XCTAssertTrue(app.buttons["Resize Living Room"].waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["True-size calibration"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.state, .runningForeground)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.staticTexts["Settings"].waitForNonExistence(timeout: 3))
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.buttons["Living Room"].waitForExistence(timeout: 5),
                      "Menu at the settings root should return to the loaded viewer")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Panels"].waitForExistence(timeout: 3),
                      "The returned viewer should reveal its controls")
        XCTAssertTrue(app.buttons["Panels"].hasFocus)
        XCTAssertTrue(app.buttons["Settings"].exists)
    }

    func testCalibrationHasSeparateNamedControlsAndNestedBackNavigation() {
        let app = launchSettings()
        openCategory("Panel appearance", in: app)
        openRow("True-size calibration", in: app)
        XCTAssertTrue(app.buttons["Decrease Living Room flap size"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Increase Living Room flap size"].exists)
        XCTAssertTrue(app.buttons["Save Living Room flap size"].exists)
        XCTAssertTrue(app.otherElements["settings.calibrationPreview"].exists)
        let previewFrame = app.otherElements["settings.calibrationPreview"].frame
        XCTAssertGreaterThanOrEqual(previewFrame.width, app.frame.width * 0.95)
        XCTAssertGreaterThanOrEqual(previewFrame.height, app.frame.height * 0.95,
                                    "True-size calibration must measure the full TV viewport")
        let increase = app.buttons["Increase Living Room flap size"]
        let previous = increase.value as? String
        openRow("Increase Living Room flap size", in: app)
        XCTAssertNotEqual(increase.value as? String, previous,
                          "The selected panel's scale must change while its board is visible")
        XCTAssertTrue(app.otherElements["settings.calibrationPreview"].exists)
        attachScreenshot("Settings — True-size calibration", app: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["True-size calibration"].waitForExistence(timeout: 3))
    }

    func testPanelChoiceControlsTheCalibrationTarget() {
        let app = launchSettings(includeSecondPanel: true)
        openCategory("Panel appearance", in: app)
        for _ in 0..<12 {
            if rowHasFocus("settings.panelPicker", in: app) { break }
            XCUIRemote.shared.press(.up)
        }
        XCTAssertTrue(rowHasFocus("settings.panelPicker", in: app))
        XCUIRemote.shared.press(.select)
        openRow("Kitchen", in: app)
        XCTAssertTrue(app.otherElements["settings.panelPreview"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.otherElements["settings.panelPreview"].label, "Kitchen preview")
        openRow("True-size calibration", in: app)
        XCTAssertTrue(app.buttons["Increase Kitchen flap size"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Increase Living Room flap size"].exists)
        XCUIRemote.shared.press(.menu)
        XCTAssertEqual(app.otherElements["settings.panelPreview"].label, "Kitchen preview")
    }

    func testHelpKeepsPrivacyReachableAndMenuReturnsToSettings() {
        let app = launchSettings()
        openCategory("About & help", in: app)
        openRow("Privacy", in: app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "FiestaBoard's servers")).firstMatch.waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["Privacy"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["About & help"].waitForExistence(timeout: 3))
    }
}
