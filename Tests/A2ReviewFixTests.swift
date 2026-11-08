import SwiftUI
import XCTest
@testable import FiestaBoardTV

/// Fixes from the #18 review (program/reviews/pr-tvos-18-review.md).
@MainActor
final class A2ReviewFixTests: XCTestCase {

    override func setUp() {
        super.setUp()
        FigmaGeometryRegistry.shared.reset()
    }

    /// Pixels in `image` (scale 2) brighter than near-black, outside `box`
    /// (points). Used to catch artwork drawing past its layout frame.
    private func litPixelsOutside(_ box: CGRect, in image: UIImage, margin: CGFloat = 2) throws -> Int {
        let rgba = try XCTUnwrap(RGBA(try XCTUnwrap(image.cgImage)))
        let keep = box.insetBy(dx: -margin, dy: -margin)
        var count = 0
        var y = 0
        while y < rgba.height {
            var x = 0
            while x < rgba.width {
                let point = CGPoint(x: CGFloat(x) / 2, y: CGFloat(y) / 2)
                if !keep.contains(point), let p = rgba.at(x, y), p.0 + p.1 + p.2 > 60 { count += 1 }
                x += 4
            }
            y += 4
        }
        return count
    }

    // MARK: 4.1 (blocker) — the A2 waiting row

    /// A2 `166:147643` "Waiting": a static 44 pt Taco mark and one line. The
    /// animated loader used here drew at ~95 pt over the lines below it.
    func testTheWaitingRowMarkIsTheA2Size() throws {
        let row = DeviceSignInWaitingRow(message: TVCopy.DeviceSignIn.waiting)
        let image = TVSnapshot.image(ZStack(alignment: .topLeading) {
            Color.black
            row.figmaNode("row").offset(x: 200, y: 200)
        })
        let entries = FigmaGeometryRegistry.shared.snapshot()
        let mark = try XCTUnwrap(entries[DeviceSignInWaitingRow.markNode]?.frame, "the mark is probed as A2 166:147644")
        XCTAssertEqual(mark.width, 44, accuracy: 0.5)
        XCTAssertEqual(mark.height, 44, accuracy: 0.5)
        let frame = try XCTUnwrap(entries["row"]?.frame)
        XCTAssertLessThanOrEqual(frame.height, 46, "one line beside a 44 pt mark, as A2 draws it")
        XCTAssertEqual(try litPixelsOutside(frame, in: image), 0, "nothing draws outside the row")
    }

    /// The same overflow, at its root: the loader's GIF image view drew at
    /// its intrinsic size, ignoring the SwiftUI frame. `.small` must stay
    /// inside 36 pt wherever it is used (Connect, Sign in, Panels,
    /// FiestaBot, the hub card).
    func testTheSmallLoaderDrawsInsideItsFrame() throws {
        let image = TVSnapshot.image(ZStack(alignment: .topLeading) {
            Color.black
            TacoLoader(size: .small, isAnimating: false).figmaNode("loader").offset(x: 300, y: 300)
        })
        let frame = try XCTUnwrap(FigmaGeometryRegistry.shared.snapshot()["loader"]?.frame)
        XCTAssertEqual(frame.width, 36, accuracy: 0.5)
        XCTAssertEqual(try litPixelsOutside(frame, in: image), 0, "the small taco must not overflow its 36 pt frame")
    }

    // MARK: 4.2 / DD12 — the host line hides the default port

    func testTheHostLineHidesTheDefaultPort() {
        let hub = DiscoveredBoard(id: "a", name: "FiestaBoard", host: URL(string: "http://192.168.1.20:4420")!)
        XCTAssertEqual(BoardAddressLabel.text(for: hub), "192.168.1.20")
    }

    func testTheHostLineKeepsAPortThatIsNotTheDefault() {
        let hub = DiscoveredBoard(id: "b", name: "FiestaBoard", host: URL(string: "http://192.168.1.21:8080")!)
        XCTAssertEqual(BoardAddressLabel.text(for: hub), "192.168.1.21:8080")
        let portless = DiscoveredBoard(id: "c", name: "FiestaBoard", host: URL(string: "https://hub.example.com")!)
        XCTAssertEqual(BoardAddressLabel.text(for: portless), "hub.example.com")
    }

    // MARK: 4.7 — US spelling

    func testCopyUsesUSCanceled() {
        XCTAssertEqual(DevicePollError(code: "invalid_grant").userMessage,
                       "This code was canceled or already used. Choose New code.")
    }
}
