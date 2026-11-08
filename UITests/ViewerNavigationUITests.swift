import XCTest
import UIKit

@MainActor
final class ViewerNavigationUITests: XCTestCase {
    private var server: FixtureHTTPServer?

    override func tearDown() {
        server = nil
        super.tearDown()
    }

    private func launchLoadedViewer(extraArguments: [String] = []) -> XCUIApplication {
        let frameLoaded = expectation(description: "The viewer requested its frame")
        let server = try! FixtureHTTPServer(onFrame: { frameLoaded.fulfill() })
        self.server = server
        let app = XCUIApplication()
        let savedConnection = """
        {"host":"http://127.0.0.1:\(server.port)","displayName":"Test Board","defaultPanelRef":"1"}
        """
        let encodedConnection = Data(savedConnection.utf8)
            .map { String(format: "%02x", $0) }
            .joined()
        app.launchArguments = ["-fiestaboard.connection", "<\(encodedConnection)>",
                               "-fiestaboard.signedOut", "NO"] + extraArguments
        app.launch()

        XCTAssertFalse(app.staticTexts["Panels"].exists, "The saved default panel should start on the viewer")
        wait(for: [frameLoaded], timeout: 10)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "taco-loader").firstMatch.waitForNonExistence(timeout: 5),
                      "The board should finish loading before pressing Menu")
        return app
    }

    func testMenuReturnsFromViewerToPanels() {
        let app = launchLoadedViewer()
        XCUIRemote.shared.press(.menu)
        XCTAssertEqual(app.state, .runningForeground, "Menu should stay in FiestaBoard")
        XCTAssertTrue(app.staticTexts["Panels"].waitForExistence(timeout: 5))
    }

    func testResizeOfferLaterCanBeReachedAndDismissedWithRemote() throws {
        continueAfterFailure = false
        var panel = try JSONSerialization.jsonObject(with: Data(Fixtures.panelJSON.utf8)) as! [String: Any]
        panel["id"] = "portrait"; panel["name"] = "Portrait"; panel["rows"] = 21; panel["cols"] = 15
        let body = String(decoding: try JSONSerialization.data(withJSONObject: panel), as: UTF8.self)
        server = try FixtureHTTPServer(additionalPanels: ["portrait": body],
                                      additionalFrames: ["portrait": #"{"characters":null,"message":null,"rows":21,"cols":15,"updated_at":null}"#])
        let app = XCUIApplication()
        let connection = "{\"host\":\"http://127.0.0.1:\(server!.port)\",\"displayName\":\"Test Board\",\"defaultPanelRef\":\"portrait\"}"
        let encoded = Data(connection.utf8).map { String(format: "%02x", $0) }.joined()
        app.launchArguments = ["-fiestaboard.connection", "<\(encoded)>", "-fiestaboard.signedOut", "NO"]
        app.launch()
        defer { app.terminate() }
        let resize = app.buttons["Resize for this TV"]
        let later = app.buttons["Later"]
        XCTAssertTrue(resize.waitForExistence(timeout: 10))
        XCTAssertTrue(resize.hasFocus)
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(later.hasFocus, "Right should focus Later without revealing viewer controls")
        XCTAssertFalse(app.buttons["Panels"].exists)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(later.waitForNonExistence(timeout: 5))
        XCTAssertFalse(resize.exists)
        XCTAssertFalse(app.buttons["Panels"].exists)

        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Panels"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Panels"].hasFocus)
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(app.buttons["Settings"].hasFocus)
        XCTAssertFalse(later.exists, "The once-per-session resize offer must remain dismissed")
    }

    func testSelectRevealsControlsAndPanelsButtonReturnsToList() {
        let app = launchLoadedViewer()
        XCUIRemote.shared.press(.select)
        let panelsButton = app.buttons["Panels"]
        XCTAssertTrue(panelsButton.waitForExistence(timeout: 3))
        XCTAssertTrue(panelsButton.hasFocus, "Showing controls should focus Panels")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Panels"].waitForExistence(timeout: 5))
    }

    /// The board sits under a full-screen focusable target, which is how a
    /// press anywhere wakes the chrome. While the chrome is up that target
    /// must get out of the way, or the focus engine keeps handing focus back
    /// to it and the buttons cannot be reached.
    func testMovingRightFromPanelsReachesSettings() {
        let app = launchLoadedViewer()
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Panels"].waitForExistence(timeout: 3))

        XCUIRemote.shared.press(.right)
        XCTAssertTrue(app.buttons["Settings"].hasFocus,
                      "moving right from Panels should focus Settings")

        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5),
                      "activating Settings should open the settings screen")
    }

    func testFocusedViewerDoesNotWashOutTheBoard() throws {
        let app = launchLoadedViewer()
        let captured = app.screenshot().image
        let attachment = XCTAttachment(image: captured)
        attachment.name = "Focused viewer"
        attachment.lifetime = .keepAlways
        add(attachment)
        let screenshot = try XCTUnwrap(captured.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &pixel, width: 1, height: 1,
                                             bitsPerComponent: 8, bytesPerRow: 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: -CGFloat(screenshot.width / 2),
                            y: -CGFloat(screenshot.height / 2))
        context.draw(screenshot, in: CGRect(x: 0, y: 0,
                                            width: screenshot.width, height: screenshot.height))
        XCTAssertLessThan(Int(pixel[0]), 20, "the empty board should remain OLED black when focused")
        XCTAssertLessThan(Int(pixel[1]), 20)
        XCTAssertLessThan(Int(pixel[2]), 20)
    }

    // MARK: A4b — the glass overlay

    /// Back takes the overlay down first; only a second Back leaves.
    func testBackDismissesTheOverlayBeforeLeavingTheViewer() {
        let app = launchLoadedViewer()
        defer { app.terminate() }
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Panels"].waitForExistence(timeout: 3))

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["Panels"].waitForNonExistence(timeout: 3), "Back should dismiss the overlay")
        XCTAssertFalse(app.staticTexts["Panels"].exists, "…and stay on the viewer")
        XCTAssertEqual(app.state, .runningForeground)

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.staticTexts["Panels"].waitForExistence(timeout: 5), "a second Back leaves for Panels")
    }

    private struct ProbeExport: Decodable {
        struct Node: Decodable { let id: String; let frame: CGRect }
        let nodes: [Node]
    }

    /// XCUIScreen shots of the overlay up, per 07b material (DD4), with the
    /// bar's registry frame checked against A4 (80, 60, 1760).
    private func overlayShot(material: String, variant: String, name: String) throws {
        let probeURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("viewer-probes-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: probeURL) }
        let app = launchLoadedViewer(extraArguments: ["-fiestaboard.viewerMaterial", material,
                                                      "-fiestaboard.figmaProbeOut", probeURL.path])
        defer { app.terminate() }
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Panels"].waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 0.6) // the fade-in and the material settle

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        var nodes: [String: CGRect] = [:]
        for _ in 0..<50 {
            if let data = try? Data(contentsOf: probeURL),
               let export = try? JSONDecoder().decode(ProbeExport.self, from: data) {
                nodes = Dictionary(export.nodes.map { ($0.id, $0.frame) }, uniquingKeysWith: { $1 })
                if nodes[variant] != nil { break }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let bar = try XCTUnwrap(nodes["I166:191865;149:182603;166:193875"], "the overlay bar registered")
        XCTAssertEqual(bar.minX, 80, accuracy: 1)
        XCTAssertEqual(bar.minY, 60, accuracy: 1)
        XCTAssertEqual(bar.width, 1760, accuracy: 1)
        XCTAssertEqual(nodes[variant], bar, "drawn as 07b \(variant)")
    }

    func testOverlayShotLiquidGlass() throws {
        try overlayShot(material: "glass", variant: "154:8170", name: "Viewer overlay — Liquid Glass (154:8170)")
    }

    /// Reduce Transparency on (forced: the simulator setting can't be
    /// toggled from XCUITest). Off is the glass shot above.
    func testOverlayShotReduceTransparency() throws {
        try overlayShot(material: "opaque", variant: "250:110540", name: "Viewer overlay — Reduce Transparency (250:110540)")
    }

    func testOverlayShotRegularMaterialFallback() throws {
        try overlayShot(material: "regular", variant: "250:110532", name: "Viewer overlay — pre-tvOS 26 fallback (250:110532)")
    }
}
