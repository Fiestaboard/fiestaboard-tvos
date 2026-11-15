import XCTest
import UIKit

/// A8b (`248:110205`): OLED care is one page of summary rows, each opening its
/// own choice page (DD23: no OLED question, preview or disclaimer).
@MainActor
final class OLEDCareUITests: XCTestCase {
    private var server: FixtureHTTPServer?

    private func focused(_ label: String, app: XCUIApplication) -> Bool {
        let row = app.buttons[label]
        let cell = app.cells.containing(.button, identifier: label).firstMatch
        return row.exists && (row.hasFocus || (cell.exists && cell.hasFocus))
    }
    private func select(_ label: String, app: XCUIApplication) {
        for _ in 0..<30 {
            if focused(label, app: app) {
                attachMilestoneEvidence("OLED care — focused \(label)", app: app)
                XCUIRemote.shared.press(.select)
                return
            }
            XCUIRemote.shared.press(.down)
        }
        XCTFail("Remote could not reach \(label)")
    }
    private func openCare(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        for _ in 0..<6 { XCUIRemote.shared.press(.up) }
        for _ in 0..<6 {
            if focused("Settings", app: app) { break }
            XCUIRemote.shared.press(.right)
        }
        XCTAssertTrue(focused("Settings", app: app))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        select("This Apple TV", app: app)
        XCUIRemote.shared.press(.right)
        select("settings.oledCare", app: app)
        XCTAssertTrue(app.buttons["oled.brightness"].waitForExistence(timeout: 5))
    }
    private func brightness(_ app: XCUIApplication) -> String { app.buttons["oled.brightness"].value as? String ?? "" }

    func testSummaryRowsBrightnessPersistenceAndBack() throws {
        continueAfterFailure = false
        server = try FixtureHTTPServer()
        defer { server = nil }
        let app = XCUIApplication()
        let connection = "{\"host\":\"http://127.0.0.1:\(server!.port)\",\"displayName\":\"Test Board\"}"
        let encoded = Data(connection.utf8).map { String(format: "%02x", $0) }.joined()
        app.launchArguments = ["-fiestaboard.connection", "<\(encoded)>", "-fiestaboard.signedOut", "NO"]
        app.launch()
        openCare(app)
        for row in ["oled.brightness", "oled.movement", "oled.night", "oled.rest", "oled.breaks", "oled.rotation",
                    "oled.disconnected", "oled.screensaver"] {
            XCTAssertTrue(app.buttons[row].exists, row)
        }
        XCTAssertFalse(app.staticTexts["oled.question"].exists, "DD23: no OLED question")
        XCTAssertFalse(app.staticTexts["Preview — app output only"].exists, "DD23: no preview")
        attachMilestoneEvidence("OLED care — summary focused", app: app)
        // Each summary row opens a native choice page. Capture before editing,
        // and return with Menu so this walk does not change local preferences.
        for (id, title, rightColumn) in [
            ("oled.movement", "Movement", false),
            ("oled.night", "Night dimming", false),
            ("oled.rest", "Scheduled rest", false),
            ("oled.breaks", "Periodic breaks", true),
            ("oled.rotation", "Layout rotation", true),
            ("oled.disconnected", "When disconnected", true),
            ("oled.screensaver", "Screen saver", true)
        ] {
            for _ in 0..<5 { XCUIRemote.shared.press(.up) }
            XCUIRemote.shared.press(.left)
            for _ in 0..<5 { XCUIRemote.shared.press(.up) }
            if rightColumn { XCUIRemote.shared.press(.right) }
            select(id, app: app)
            XCTAssertTrue(app.buttons["oled.brightness"].waitForNonExistence(timeout: 5))
            if id == "oled.movement" {
                XCTAssertTrue(app.staticTexts["Shifts the board a few pixels over 20 min"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.staticTexts["Larger shifts for long, static days"].exists)
            }
            attachMilestoneEvidence("OLED care — \(title) choices focused", app: app)
            attachVerticalFocusWalk("OLED care — \(title) controls", app: app, steps: 10)
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(app.buttons["oled.brightness"].waitForExistence(timeout: 5))
        }
        for _ in 0..<5 { XCUIRemote.shared.press(.up) }
        XCUIRemote.shared.press(.left)
        for _ in 0..<5 { XCUIRemote.shared.press(.up) }
        select("oled.brightness", app: app)
        XCTAssertTrue(app.buttons["50 %"].waitForExistence(timeout: 5))
        attachMilestoneEvidence("OLED care — brightness choices focused", app: app)
        select("50 %", app: app)
        XCTAssertTrue(app.buttons["oled.brightness"].waitForExistence(timeout: 5))
        XCTAssertEqual(brightness(app), "50 %")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["settings.oledCare"].value as? String, "On · only this Apple TV")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Your FiestaPanel displays. OLED TV? Optional setup in Settings → OLED care."].exists,
                       "opening OLED care dismisses the optional invitation")
        app.terminate(); app.launch()
        openCare(app)
        XCTAssertEqual(brightness(app), "50 %", "persists on this TV")
        // Leave device defaults clean for other native presentation tests.
        select("oled.brightness", app: app)
        for _ in 0..<6 { XCUIRemote.shared.press(.down) }
        select("100 %", app: app)
        XCTAssertTrue(app.buttons["oled.brightness"].waitForExistence(timeout: 5))
        XCTAssertEqual(brightness(app), "100 %")
    }
    func testMenuFromNestedDimLevelAndTimeReturnsOneLevel() throws {
        continueAfterFailure = false
        server = try FixtureHTTPServer()
        defer { server = nil }
        let app = XCUIApplication()
        let connection = "{\"host\":\"http://127.0.0.1:\(server!.port)\",\"displayName\":\"Test Board\"}"
        let encoded = Data(connection.utf8).map { String(format: "%02x", $0) }.joined()
        app.launchArguments = ["-fiestaboard.connection", "<\(encoded)>", "-fiestaboard.signedOut", "NO"]
        app.launch()
        defer { app.terminate() }
        openCare(app)
        select("oled.night", app: app)
        let dimLevel = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Night dim level")).firstMatch
        XCTAssertTrue(dimLevel.waitForExistence(timeout: 5))
        select(dimLevel.label, app: app)
        XCTAssertTrue(app.navigationBars["Night dim level"].waitForExistence(timeout: 5))
        attachVerticalFocusWalk("OLED care — Night dim level controls", app: app, steps: 6)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(dimLevel.waitForExistence(timeout: 5), "Menu must return to Night dimming, not OLED summary")
        attachMilestoneEvidence("OLED care — Night dimming after dim-level Back", app: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["oled.brightness"].waitForExistence(timeout: 5))
        select("oled.rest", app: app)
        let starts = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Rest starts")).firstMatch
        XCTAssertTrue(starts.waitForExistence(timeout: 5))
        select(starts.label, app: app)
        XCTAssertTrue(app.navigationBars["Rest starts"].waitForExistence(timeout: 5))
        attachVerticalFocusWalk("OLED care — Rest starts time controls", app: app, steps: 4)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(starts.waitForExistence(timeout: 5), "Menu must return to Scheduled rest, not OLED summary")
        attachMilestoneEvidence("OLED care — Scheduled rest after time Back", app: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["oled.brightness"].waitForExistence(timeout: 5))
    }

    private func focusOnly(_ label: String, app: XCUIApplication) {
        for _ in 0..<8 { XCUIRemote.shared.press(.up) }
        for _ in 0..<30 {
            if focused(label, app: app) { return }
            XCUIRemote.shared.press(.down)
        }
        XCTFail("Could not focus \(label) without activation")
    }

    func testFocusedOLEDSecondaryTextKeepsReadableNativeContrast() throws {
        continueAfterFailure = false
        server = try FixtureHTTPServer()
        defer { server = nil }
        let app = XCUIApplication()
        let connection = "{\"host\":\"http://127.0.0.1:\(server!.port)\",\"displayName\":\"Contrast Test Hub\"}"
        let encoded = Data(connection.utf8).map { String(format: "%02x", $0) }.joined()
        app.launchArguments = ["-fiestaboard.connection", "<\(encoded)>", "-fiestaboard.signedOut", "NO"]
        app.launch()
        defer { app.terminate() }
        openCare(app)
        focusOnly("oled.movement", app: app)
        let brightness = app.buttons["oled.brightness"].value as? String ?? "100 %"
        assertNativeTextContrast(brightness, app: app, context: "OLED summary unfocused value")
        focusOnly("oled.brightness", app: app)
        assertNativeTextContrast(brightness, app: app, context: "OLED summary focused value")
        select("oled.movement", app: app)
        XCTAssertTrue(app.buttons["Gentle"].waitForExistence(timeout: 5))
        let gentle = "Shifts the board a few pixels over 20 min"
        let wider = "Larger shifts for long, static days"
        assertNativeTextContrast(gentle, app: app, context: "Movement Gentle unfocused")
        assertNativeTextContrast(wider, app: app, context: "Movement Wider unfocused")
        focusOnly("Gentle", app: app)
        assertNativeTextContrast(gentle, app: app, context: "Movement Gentle focused")
        focusOnly("Wider", app: app)
        assertNativeTextContrast(wider, app: app, context: "Movement Wider focused")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["oled.night"].waitForExistence(timeout: 5))
        select("oled.night", app: app)
        XCTAssertTrue(app.buttons["Never"].waitForExistence(timeout: 5))
        focusOnly("Never", app: app)
        let follow = "Uses the shared schedule set on your phone"
        let custom = "Only this TV"
        assertNativeTextContrast(follow, app: app, context: "Night Follow panel unfocused")
        assertNativeTextContrast(custom, app: app, context: "Night Custom unfocused")
        focusOnly("Follow panel", app: app)
        assertNativeTextContrast(follow, app: app, context: "Night Follow panel focused")
        focusOnly("Custom", app: app)
        assertNativeTextContrast(custom, app: app, context: "Night Custom focused")
    }

    func testNativeTimeEditorKeepsHourPeriodAndMinuteReadableAndPersists() throws {
        continueAfterFailure = false
        server = try FixtureHTTPServer()
        defer { server = nil }
        let app = XCUIApplication()
        let connection = "{\"host\":\"http://127.0.0.1:\(server!.port)\",\"displayName\":\"Time Test Hub\"}"
        let encoded = Data(connection.utf8).map { String(format: "%02x", $0) }.joined()
        app.launchArguments = ["-fiestaboard.connection", "<\(encoded)>", "-fiestaboard.signedOut", "NO"]
        app.launch()
        defer { app.terminate() }
        openCare(app)
        select("oled.rest", app: app)
        let starts = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Rest starts")).firstMatch
        XCTAssertTrue(starts.waitForExistence(timeout: 5))
        select(starts.label, app: app)
        XCTAssertTrue(app.navigationBars["Rest starts"].waitForExistence(timeout: 5))
        if app.buttons["oled.time.hour"].exists { select("oled.time.hour", app: app) }
        let selected = app.buttons["10:00 PM"]
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        let minimum = ("10:00 PM" as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 23)]).width
        focusOnly("10:00 PM", app: app)
        let visibleText = selected.staticTexts["10:00 PM"].firstMatch
        let cell = app.cells.containing(.button, identifier: "10:00 PM").firstMatch
        let laidOut = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let glyphs = visibleText.exists ? visibleText.frame : selected.frame
            return cell.exists && glyphs.width >= minimum
                && cell.frame.contains(glyphs) && app.frame.contains(glyphs)
        }, object: nil)
        let layoutResult = XCTWaiter.wait(for: [laidOut], timeout: 5)
        attachMilestoneEvidence("OLED care — selected hour native cell layout", app: app)
        let visibleFrame = visibleText.exists ? visibleText.frame : selected.frame
        XCTAssertEqual(layoutResult, .completed,
            "Full hour glyphs must fit the actual native cell and viewport: glyphs \(visibleFrame), cell \(cell.frame)")
        XCTAssertGreaterThanOrEqual(visibleFrame.width, minimum,
            "The actual native hour label must fit its full hour and AM/PM at the TV type floor")
        // The accessibility Button reports its label's frame, not the whole
        // native focused surface; use the owning cell for containment.
        XCTAssertTrue(cell.frame.contains(visibleFrame))
        XCTAssertTrue(app.frame.contains(visibleFrame))
        XCTAssertTrue(selected.isSelected || (selected.value as? String) == "Selected")
        attachMilestoneEvidence("OLED care — selected hour fully readable", app: app)
        for _ in 0..<24 { XCUIRemote.shared.press(.up) }
        select("11:00 AM", app: app)
        XCTAssertTrue(app.buttons["oled.time.minute"].waitForExistence(timeout: 5))
        select("oled.time.minute", app: app)
        for _ in 0..<12 { XCUIRemote.shared.press(.up) }
        select(":35", app: app)
        assertTimeHubAfterMinuteSelection(app, hour: "11:00 AM", minute: ":35",
                                          context: "changed time before Menu")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(starts.waitForExistence(timeout: 5))
        XCTAssertTrue(starts.label.contains("11:35 AM") || (starts.value as? String) == "11:35 AM")
        attachMilestoneEvidence("OLED care — changed time across AM PM", app: app)
        app.terminate(); app.launch()
        openCare(app)
        select("oled.rest", app: app)
        XCTAssertTrue(starts.waitForExistence(timeout: 5))
        XCTAssertTrue(starts.label.contains("11:35 AM") || (starts.value as? String) == "11:35 AM",
                      "Hour and minute persist across app relaunch")
        focusOnly(starts.label, app: app)
        attachMilestoneEvidence("OLED care — persisted Scheduled rest start after relaunch", app: app)
        select(starts.label, app: app)
        select("oled.time.hour", app: app)
        for _ in 0..<24 { XCUIRemote.shared.press(.up) }
        select("10:00 PM", app: app)
        select("oled.time.minute", app: app)
        for _ in 0..<12 { XCUIRemote.shared.press(.up) }
        select(":00", app: app)
        assertTimeHubAfterMinuteSelection(app, hour: "10:00 PM", minute: ":00",
                                          context: "restored time before Menu")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(starts.waitForExistence(timeout: 5))
        XCTAssertTrue(starts.label.contains("10:00 PM") || (starts.value as? String) == "10:00 PM")
    }

    func testRapidMinuteSelectionThenMenuKeepsTheImmediateParent() throws {
        continueAfterFailure = false
        server = try FixtureHTTPServer()
        defer { server = nil }
        let app = XCUIApplication()
        let connection = "{\"host\":\"http://127.0.0.1:\(server!.port)\",\"displayName\":\"Rapid Back Test Hub\"}"
        let encoded = Data(connection.utf8).map { String(format: "%02x", $0) }.joined()
        app.launchArguments = ["-fiestaboard.connection", "<\(encoded)>", "-fiestaboard.signedOut", "NO"]
        app.launch()
        defer { app.terminate() }
        openCare(app)
        select("oled.rest", app: app)
        let starts = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Rest starts")).firstMatch
        XCTAssertTrue(starts.waitForExistence(timeout: 5))
        select(starts.label, app: app)
        select("oled.time.minute", app: app)
        for _ in 0..<12 { XCUIRemote.shared.press(.up) }
        select(":35", app: app)
        // Reproduce the valid rapid remote sequence: no destination query,
        // attachment, readiness guard or delay between Select and Menu.
        XCUIRemote.shared.press(.menu)
        attachMilestoneEvidence("OLED care — rapid minute Select then Menu", app: app)
        XCTAssertTrue(app.navigationBars["Scheduled rest"].waitForExistence(timeout: 5))
        XCTAssertTrue(starts.waitForExistence(timeout: 5))
        XCTAssertTrue(starts.label.contains(":35") || (starts.value as? String)?.contains(":35") == true)
        XCTAssertFalse(app.buttons["oled.brightness"].exists, "Menu must not skip to the OLED summary")
        // Restore the fixture's minute through the same native editor.
        select(starts.label, app: app)
        select("oled.time.minute", app: app)
        for _ in 0..<12 { XCUIRemote.shared.press(.up) }
        select(":00", app: app)
        XCTAssertTrue(app.navigationBars["Minute"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["oled.time.minute"].waitForExistence(timeout: 5))
        focusOnly("oled.time.minute", app: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(starts.waitForExistence(timeout: 5))
    }

    private func assertTimeHubAfterMinuteSelection(_ app: XCUIApplication, hour: String,
                                                   minute: String, context: String) {
        // Selection dismisses the native choice page asynchronously. Send Menu
        // only after the destination and its actual focused surface are ready.
        XCTAssertTrue(app.navigationBars["Minute"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Rest starts"].waitForExistence(timeout: 5))
        let hourRow = app.buttons["oled.time.hour"]
        let minuteRow = app.buttons["oled.time.minute"]
        XCTAssertTrue(hourRow.waitForExistence(timeout: 5))
        XCTAssertTrue(minuteRow.waitForExistence(timeout: 5))
        XCTAssertEqual(hourRow.value as? String, hour)
        XCTAssertEqual(minuteRow.value as? String, minute)
        focusOnly("oled.time.minute", app: app)
        attachMilestoneEvidence("OLED care — Scheduled rest — Rest starts — " + context, app: app)
    }

}
