import SwiftUI
import XCTest
@testable import FiestaBoardTV

@MainActor
final class FlapAtlasTests: XCTestCase {
    func testRetinaAtlasFitsTextureDimensionsAndKeepsLastDrumFaces() throws {
        for height in [80.0, 120.0] {
            let atlas = try XCTUnwrap(FlapAtlas(tileHeight: height, background: .black, code62: .degree, scale: 2))
            let face = try XCTUnwrap(atlas.image(code: 68, phase: nil))
            XCTAssertLessThanOrEqual(atlas.maximumTextureDimension, 4096,
                                     "Each backing sheet must fit within the conservative texture budget")
            let pixel = try XCTUnwrap(UIImage(cgImage: face).pixel(x: face.width / 2, y: face.height / 4))
            XCTAssertGreaterThan(pixel.r, 120)
            XCTAssertGreaterThan(pixel.b, 120)
            XCTAssertLessThanOrEqual(atlas.byteCount, 64 * 1024 * 1024)
        }
    }

    func testPreparedFramesKeepPigmentAndMechanicalHalfFaces() throws {
        let atlas = try XCTUnwrap(FlapAtlas(tileHeight: 80, background: .black, code62: .degree, scale: 1))
        let still = UIImage(cgImage: try XCTUnwrap(atlas.image(code: 63, phase: nil)))
        let face = try XCTUnwrap(still.pixel(x: Int(still.size.width / 2), y: 20))
        XCTAssertEqual(Int(face.r), 235, accuracy: 2)
        XCTAssertEqual(Int(face.g), 64, accuracy: 2)
        // Half-way through red -> orange: orange revealed above, red remains below.
        let falling = UIImage(cgImage: try XCTUnwrap(atlas.image(code: 63, phase: 6)))
        let top = try XCTUnwrap(falling.pixel(x: Int(falling.size.width / 2), y: 10))
        let bottom = try XCTUnwrap(falling.pixel(x: Int(falling.size.width / 2), y: 70))
        XCTAssertGreaterThan(top.g, 140)
        XCTAssertLessThan(bottom.g, 110)
        XCTAssertGreaterThan(bottom.r, 160)
        XCTAssertLessThanOrEqual(atlas.byteCount, 64 * 1024 * 1024)
    }

    func testDrumRetainsSecondBlackPositionBeforeWrappingToBlank() {
        let start = Date(timeIntervalSince1970: 0)
        let transition = BoardFlipTransition(from: [.color(.black)], to: [.character("A")], code62: .degree, startedAt: start)
        XCTAssertEqual(transition.sample(index: 0, at: start.addingTimeInterval(0.10)).drumCode, 71)
    }
}
