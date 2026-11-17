import XCTest
import CoreGraphics

/// Native window-server captures, with the matching accessibility frame and
/// focus inventory. This is deliberately separate from offscreen goldens.
@MainActor
extension XCTestCase {
    func attachMilestoneEvidence(_ name: String, app: XCUIApplication) {
        // Remote focus is asserted by the caller; allow the native platter's
        // animation to finish before retaining window-server pixels.
        Thread.sleep(forTimeInterval: 0.5)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        // debugDescription preserves the complete semantics/frame tree with
        // one snapshot request; repeated per-element queries can race focus
        // transitions and turn a capture walk into a multi-minute operation.
        let inventory = XCTAttachment(string: "Screen: \(app.frame)\n\n\(app.debugDescription)")
        inventory.name = "\(name) — accessibility and focus probes"
        inventory.lifetime = .keepAlways
        add(inventory)
    }
    /// A bounded, non-activating semantics walk. Keep each distinct focused
    /// control's native screen and tree; repeated presses at the end don't
    /// create duplicate artifacts. The focus predicate is already exercised
    /// by the Panels presentation suite on native tvOS.
    func attachVerticalFocusWalk(_ name: String, app: XCUIApplication, steps: Int = 16) {
        var seen = Set<String>()
        for _ in 0..<steps {
            let focused = app.descendants(matching: .any)
                .matching(NSPredicate(format: "hasFocus == YES")).firstMatch
            XCTAssertTrue(focused.exists, "\(name) must keep a native focus owner")
            guard focused.exists else { return }
            let identity = "\(focused.identifier) \(focused.label)"
            XCTAssertTrue(focused.hasFocus)
            if seen.insert(identity).inserted {
                attachMilestoneEvidence("\(name) — focused \(identity)", app: app)
            }
            XCUIRemote.shared.press(.down)
        }
    }

    func assertNativeTextContrast(_ label: String, app: XCUIApplication,
                                  context: String, file: StaticString = #filePath, line: UInt = #line) {
        let text = app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
        assertNativeGlyphContrast(text, app: app, minimum: 4.5, context: context, file: file, line: line)
    }

    func assertNativeGlyphContrast(_ element: XCUIElement, app: XCUIApplication, minimum: Double,
                                   context: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 3), context, file: file, line: line)
        Thread.sleep(forTimeInterval: 0.5)
        let screenshot = XCUIScreen.main.screenshot()
        guard let cg = screenshot.image.cgImage else { XCTFail("No native image", file: file, line: line); return }
        let frame = element.frame
        let scale = CGFloat(cg.width) / app.frame.width
        guard let measurement = TextContrastProbe.measure(cg, scale: scale, text: frame,
            background: CGPoint(x: frame.minX - 8, y: frame.midY)) else {
            XCTFail("No core glyph pixels for \(context): \(frame)", file: file, line: line); return
        }
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = "Contrast — \(context)"; shot.lifetime = .keepAlways; add(shot)
        let probe = XCTAttachment(string: "Element: \(element.label)\nFrame: \(frame)\n\(measurement.dictionary)\nMinimum: \(minimum)\n\n\(app.debugDescription)")
        probe.name = "Contrast — \(context) — pixel and focus probes"
        probe.lifetime = .keepAlways; add(probe)
        XCTAssertGreaterThanOrEqual(measurement.ratio, minimum,
            "Native glyph contrast \(context): \(measurement.dictionary)", file: file, line: line)
    }

}
