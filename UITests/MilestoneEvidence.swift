import XCTest

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

}
