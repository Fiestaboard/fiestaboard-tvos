import XCTest

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
}
