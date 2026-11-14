import XCTest

/// Native window-server captures, with the matching accessibility frame and
/// focus inventory. This is deliberately separate from offscreen goldens.
@MainActor
extension XCTestCase {
    func attachMilestoneEvidence(_ name: String, app: XCUIApplication) {
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
}
