import XCTest
import UIKit

@MainActor
final class HomeTopShelfUITests: XCTestCase {
    private var server: FixtureHTTPServer?

    /// How much of Home's upper half must be brand amber before we accept
    /// that the Top Shelf is ours. A poster is a full-bleed amber field, so
    /// the real thing scores far above this; another app's art scores near
    /// zero. One sampled pixel could not tell those apart reliably.
    private let brandCoverageThreshold = 0.25

    override func tearDown() {
        server = nil
        super.tearDown()
    }

    func testHomeTopShelfShowsTheBrandedPanelCarousel() throws {
        let panelsLoaded = expectation(description: "Top Shelf published from the panel list")
        let server = try FixtureHTTPServer(onPanels: { panelsLoaded.fulfill() })
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
        wait(for: [panelsLoaded], timeout: 10)

        XCUIRemote.shared.press(.menu)
        // Home restores whichever icon it last focused, which may belong to
        // another app when this test follows other simulator tests. Walk the
        // row in both directions until FiestaBoard's own Top Shelf is up.
        var best = 0.0
        var capture = XCUIScreen.main.screenshot()
        for direction in [XCUIRemote.Button.right, .left] {
            for _ in 0..<10 {
                best = max(best, brandCoverage(in: capture.image))
                if best >= brandCoverageThreshold { break }
                XCUIRemote.shared.press(direction)
                Thread.sleep(forTimeInterval: 1.0)
                capture = XCUIScreen.main.screenshot()
            }
            if best >= brandCoverageThreshold { break }
        }

        let attachment = XCTAttachment(screenshot: capture)
        attachment.name = "Apple TV Home Top Shelf"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThanOrEqual(
            best, brandCoverageThreshold,
            "Home Top Shelf should show the brand field, not a board screenshot "
            + "(best coverage \(best))")
    }

    /// The fraction of Home's upper 60% that is brand amber (#f5a623):
    /// bright, warm, and with far less blue than green.
    private func brandCoverage(in image: UIImage) -> Double {
        guard let source = image.cgImage else { return 0 }
        let width = 80, height = 45
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 0 }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Row 0 of the bitmap is the top of the image. Stop before the icon
        // row, which carries every other app's colours.
        let rows = height * 6 / 10
        var amber = 0
        for y in 0..<rows {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let (r, g, b) = (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
                if r > 170, g > 90, g < r, b < g / 2 { amber += 1 }
            }
        }
        return Double(amber) / Double(rows * width)
    }
}
