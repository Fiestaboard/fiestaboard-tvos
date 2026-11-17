import CoreGraphics
import XCTest

final class TextContrastProbeTests: XCTestCase {
    private func image(ink: CGFloat, ground: CGFloat) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 120, height: 40, bitsPerComponent: 8,
            bytesPerRow: 120 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: ground, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 120, height: 40))
        context.setFillColor(CGColor(gray: ink, alpha: 1)); context.fill(CGRect(x: 20, y: 10, width: 60, height: 20))
        return try XCTUnwrap(context.makeImage())
    }

    func testGrayInkOnTheNativeLightFocusGroundIsRejected() throws {
        let measured = try XCTUnwrap(TextContrastProbe.measure(try image(ink: 0.65, ground: 0.99), scale: 1,
            text: CGRect(x: 15, y: 5, width: 70, height: 30), background: CGPoint(x: 10, y: 20)))
        XCTAssertLessThan(measured.ratio, 3)
        XCTAssertGreaterThan(measured.corePixels, 100)
    }

    func testDarkInkOnTheLightFocusGroundAndMutedInkOnDarkAreReadable() throws {
        for (ink, ground) in [(0.1, 0.99), (0.65, 0.08)] {
            let measured = try XCTUnwrap(TextContrastProbe.measure(try image(ink: ink, ground: ground), scale: 1,
                text: CGRect(x: 15, y: 5, width: 70, height: 30), background: CGPoint(x: 10, y: 20)))
            XCTAssertGreaterThanOrEqual(measured.ratio, 4.5)
        }
    }

    func testEmptyTextBoundsDoNotInventInk() throws {
        XCTAssertNil(TextContrastProbe.measure(try image(ink: 0.65, ground: 0.99), scale: 1,
            text: CGRect(x: 90, y: 5, width: 20, height: 30), background: CGPoint(x: 10, y: 20)))
    }
}
