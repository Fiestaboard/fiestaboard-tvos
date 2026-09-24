import XCTest
import UIKit

@MainActor
final class ViewerNavigationUITests: XCTestCase {
    private var server: FixtureHTTPServer?

    override func tearDown() {
        server = nil
        super.tearDown()
    }

    private func launchLoadedViewer() -> XCUIApplication {
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
                               "-fiestaboard.signedOut", "NO"]
        app.launch()

        XCTAssertFalse(app.staticTexts["Panels"].exists, "The saved default panel should start on the viewer")
        wait(for: [frameLoaded], timeout: 10)
        XCTAssertTrue(app.progressIndicators.firstMatch.waitForNonExistence(timeout: 5),
                      "The board should finish loading before pressing Menu")
        return app
    }

    func testMenuReturnsFromViewerToPanels() {
        let app = launchLoadedViewer()
        XCUIRemote.shared.press(.menu)
        XCTAssertEqual(app.state, .runningForeground, "Menu should stay in FiestaBoard")
        XCTAssertTrue(app.staticTexts["Panels"].waitForExistence(timeout: 5))
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
}
