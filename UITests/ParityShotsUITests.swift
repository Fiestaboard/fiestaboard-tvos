import XCTest

/// A0 — XCUITest half of the D7 parity method (PHASE-4-TV-PLAN §2.1).
///
/// Glass and the focus platter are drawn by the system compositor, which a
/// `drawHierarchy` snapshot never runs. These shots go through `XCUIScreen`
/// against the DEBUG parity fixture (`-fiestaboard.parityFixture glass`):
/// red/blue stripes under a `.glassEffect` panel, plus two focusable
/// buttons. The app writes its `FigmaGeometryRegistry` to a path we pass in,
/// so registry frames can be cross-checked against `XCUIElement.frame`.
@MainActor
final class ParityShotsUITests: XCTestCase {
    private var probeURL: URL!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        probeURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("figma-probes-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: probeURL)
        super.tearDown()
    }

    private struct Export: Decodable {
        struct Node: Decodable { let id: String; let label: String?; let frame: CGRect }
        let nodes: [Node]
    }

    private func launchFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-fiestaboard.parityFixture", "glass",
                               "-fiestaboard.figmaProbeOut", probeURL.path]
        app.launch()
        return app
    }

    /// Polls for the app's export until it holds every id in `ids`.
    private func registry(containing ids: [String]) throws -> [String: Export.Node] {
        for _ in 0..<50 {
            if let data = try? Data(contentsOf: probeURL),
               let export = try? JSONDecoder().decode(Export.self, from: data) {
                let byID = Dictionary(export.nodes.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
                if ids.allSatisfy({ byID[$0] != nil }) { return byID }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTFail("the app never exported \(ids) to \(probeURL.path)")
        return [:]
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "figma:\(id)").firstMatch
    }

    private func shot(_ name: String) -> XCUIScreenshot {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return screenshot
    }

    private func pixelScale(_ shot: XCUIScreenshot) throws -> CGFloat {
        let cg = try XCTUnwrap(shot.image.cgImage)
        return CGFloat(cg.width) / 1920
    }

    // MARK: M8 cross-check

    /// Registry frames (onGeometryChange, global space) agree with what
    /// XCUITest reports for the same Figma ids, within ±1 pt. The focused
    /// button is excluded: the focus lift scales the platter, and how each
    /// side reports that is recorded by the focus test instead.
    func testRegistryFramesAgreeWithXCUIElementFrames() throws {
        let app = launchFixture()
        defer { app.terminate() }
        continueAfterFailure = true // report every id, not just the first miss
        let ids = ["parity:title", "parity:glass", "parity:second"]
        XCTAssertTrue(element(app, "parity:glass").waitForExistence(timeout: 10))
        let registry = try registry(containing: ids + ["parity:first"])

        for id in ids {
            let registered = try XCTUnwrap(registry[id]?.frame)
            let reported = element(app, id).frame
            XCTContext.runActivity(named: "\(id): registry \(registered) vs XCUI \(reported)") { _ in
                XCTAssertEqual(reported.minX, registered.minX, accuracy: 1, id)
                XCTAssertEqual(reported.minY, registered.minY, accuracy: 1, id)
                XCTAssertEqual(reported.width, registered.width, accuracy: 1, id)
                XCTAssertEqual(reported.height, registered.height, accuracy: 1, id)
            }
        }
        XCTAssertEqual(registry["parity:title"]?.label, element(app, "parity:title").label,
                       "registry text is cross-checked against XCUIElement.label")
    }

    // MARK: Glass proof

    /// `.glassEffect` over a known pattern, captured by `XCUIScreen`: the
    /// stripes must show through (translucency) and the panel must visibly
    /// alter them (a material is composited, not an empty frame).
    func testGlassIsCapturedAsTranslucentByXCUIScreen() throws {
        let app = launchFixture()
        defer { app.terminate() }
        let glass = element(app, "parity:glass")
        XCTAssertTrue(glass.waitForExistence(timeout: 10))
        let panel = try XCTUnwrap(registry(containing: ["parity:glass"])["parity:glass"])
        Thread.sleep(forTimeInterval: 0.5) // let the material settle

        let screenshot = shot("Parity fixture — glass over stripes")
        let cg = try XCTUnwrap(screenshot.image.cgImage)
        let scale = try pixelScale(screenshot)
        XCTAssertEqual(scale, 2, "XCUIScreen shots are 3840×2160 on the Apple TV 4K simulator")

        let m = try XCTUnwrap(GlassProbe.measure(cg, scale: scale, panel: panel.frame),
                              "no clean red/blue backdrop columns around the panel")
        XCTContext.runActivity(named: "glass (\(panel.label ?? "?")): \(m.dictionary)") { _ in }
        XCTAssertTrue(m.isTranslucentGlass,
                      "expected translucent glass over the stripes; measured \(m.dictionary)")
    }

    // MARK: Focus

    /// The focus lift is visible to `XCUIScreen`: the first button's pixels
    /// change when focus moves away from it.
    func testFocusLiftIsCapturedByXCUIScreen() throws {
        let app = launchFixture()
        defer { app.terminate() }
        let first = element(app, "parity:first")
        let second = element(app, "parity:second")
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        for _ in 0..<3 where !first.hasFocus { XCUIRemote.shared.press(.left) }
        XCTAssertTrue(first.hasFocus, "the fixture starts with focus on the first button")
        let registeredFirst = try XCTUnwrap(registry(containing: ["parity:first"])["parity:first"]?.frame)
        let focusedFrame = first.frame
        Thread.sleep(forTimeInterval: 0.5)
        let focused = shot("Parity fixture — first button focused")

        XCUIRemote.shared.press(.right)
        XCTAssertTrue(second.hasFocus)
        Thread.sleep(forTimeInterval: 0.5)
        let unfocusedFrame = first.frame
        let unfocused = shot("Parity fixture — first button unfocused")

        let scale = try pixelScale(focused)
        let difference = try XCTUnwrap(GlassProbe.meanDifference(
            try XCTUnwrap(focused.image.cgImage), try XCTUnwrap(unfocused.image.cgImage),
            scale: scale, in: registeredFirst))
        XCTContext.runActivity(named: """
            focus: mean Δ \(difference); XCUI focused \(focusedFrame) unfocused \(unfocusedFrame); \
            registry \(registeredFirst)
            """) { _ in }
        XCTAssertGreaterThan(difference, 20, "the focused platter must differ from the unfocused button")
        XCTAssertEqual(unfocusedFrame.width, registeredFirst.width, accuracy: 1,
                       "unfocused, XCUI and the registry agree")
    }
}
