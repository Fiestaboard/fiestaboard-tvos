import XCTest
import UIKit

@MainActor
final class HomeTopShelfUITests: XCTestCase {
    private var server: FixtureHTTPServer?

    override func tearDown() {
        server = nil
        super.tearDown()
    }

    func testHomeTopShelfShowsThePanelCarousel() throws {
        let frameLoaded = expectation(description: "Top Shelf preview fetched the frame")
        let server = try FixtureHTTPServer(frameBody: Fixtures.frameJSON,
                                           onFrame: { frameLoaded.fulfill() })
        self.server = server
        let connection = """
        {"host":"http://127.0.0.1:\(server.port)","displayName":"Test Board"}
        """
        let encoded = Data(connection.utf8).map { String(format: "%02x", $0) }.joined()
        let app = XCUIApplication()
        app.launchArguments = ["-fiestaboard.connection", "<\(encoded)>",
                               "-fiestaboard.signedOut", "NO"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Panels"].waitForExistence(timeout: 5))
        wait(for: [frameLoaded], timeout: 10)

        XCUIRemote.shared.press(.menu)
        // Home keeps the previously focused icon, which can belong to a
        // different app when this test follows other simulator tests.
        var capture = XCUIScreen.main.screenshot()
        for _ in 0..<8 where !hasRedFlap(in: capture.image) {
            XCUIRemote.shared.press(.right)
            Thread.sleep(forTimeInterval: 0.5)
            capture = XCUIScreen.main.screenshot()
        }
        for _ in 0..<8 where !hasRedFlap(in: capture.image) {
            XCUIRemote.shared.press(.left)
            Thread.sleep(forTimeInterval: 0.5)
            capture = XCUIScreen.main.screenshot()
        }
        let attachment = XCTAttachment(screenshot: capture)
        attachment.name = "Apple TV Home Top Shelf"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(hasRedFlap(in: capture.image),
                      "Home Top Shelf should show the fixture board's red flap")
    }

    private func hasRedFlap(in image: UIImage) -> Bool {
        guard let source = image.cgImage else { return false }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &pixel, width: 1, height: 1,
                                      bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        // Core Graphics draws CGImage from a bottom-left origin; the Home
        // screenshot coordinate we inspect is measured from the top.
        context.translateBy(x: -CGFloat(source.width) * 0.27,
                            y: -CGFloat(source.height) * (1 - 0.63))
        context.draw(source, in: CGRect(x: 0, y: 0,
                                        width: source.width, height: source.height))
        return Int(pixel[0]) > 150 && Int(pixel[0]) > Int(pixel[1]) * 2
            && Int(pixel[0]) > Int(pixel[2]) * 2
    }
}
