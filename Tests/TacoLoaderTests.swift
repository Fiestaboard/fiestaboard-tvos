import XCTest
@testable import FiestaBoardTV

@MainActor
final class TacoLoaderTests: XCTestCase {
    func testBundledAnimationPreservesOriginalFramesAndFinalHold() throws {
        let animation = try XCTUnwrap(TacoAnimation.shared)
        XCTAssertEqual(animation.images.count, 45)
        XCTAssertEqual(animation.duration, 1.92, accuracy: 0.001)
        XCTAssertEqual(animation.timedImages.count, 48)
        let finalImage = try XCTUnwrap(animation.images.last)
        XCTAssertTrue(animation.timedImages.suffix(4).allSatisfy { $0 === finalImage },
                      "The original final frame holds for 160 ms, four normal frame intervals")
        XCTAssertTrue(animation.images.allSatisfy { $0.size == finalImage.size },
                      "Every frame must share one canvas so playback cannot jump in size")
    }
}
