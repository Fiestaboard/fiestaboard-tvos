import XCTest
import CoreImage
@testable import FiestaBoardTV

final class QRCodeTests: XCTestCase {
    func testLocalQRCodeDecodesPublicURLAndHasFourModuleWhiteBorder() throws {
        let value = "https://board.test:4420/fiesta/activate?user_code=WDJB-MJHT"
        let qr = try XCTUnwrap(QRCode.image(for: value, scale: 8))
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(), options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let features = detector.features(in: CIImage(cgImage: qr))
        XCTAssertEqual((features.first as? CIQRCodeFeature)?.messageString, value)
        XCTAssertEqual(qr.width % 8, 0)
        let data = try XCTUnwrap(qr.dataProvider?.data)
        let bytes = CFDataGetBytePtr(data)!
        XCTAssertEqual(bytes[0], 255)
        XCTAssertEqual(bytes[31 * qr.bytesPerRow], 255)
    }
}
