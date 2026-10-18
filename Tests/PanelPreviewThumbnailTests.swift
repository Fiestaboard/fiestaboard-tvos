import SwiftUI
import UIKit
import XCTest
@testable import FiestaBoardTV

@MainActor
final class PanelPreviewThumbnailTests: XCTestCase {
    func testThumbnailPaintsBothDisplayKindsAtTheRequestedResolution() throws {
        for matrix in [false, true] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(Fixtures.panelJSON.utf8)) as? [String: Any])
            if matrix {
                object["render_style"] = "led_matrix"
                object["device_model_spec"] = ["geometry": ["kind": "pixels", "width": 192, "height": 96]]
            }
            let panel = try JSONDecoder().decode(Panel.self, from: JSONSerialization.data(withJSONObject: object))
            let preview = PanelPreview(rows: 3, cols: 6,
                cells: Array(repeating: Array(repeating: .color(.red), count: 6), count: 3), message: nil)
            let request = PanelPreviewImageCache.Request(panel: panel, preview: preview,
                size: CGSize(width: 400, height: 220), scale: 2)
            let cgImage = try XCTUnwrap(PanelPreviewThumbnail.render(request, environment: EnvironmentValues()))
            XCTAssertEqual(cgImage.width, 800)
            XCTAssertEqual(cgImage.height, 440)
            let image = UIImage(cgImage: cgImage)
            var redPixels = 0
            for y in stride(from: 0, to: cgImage.height, by: 5) {
                for x in stride(from: 0, to: cgImage.width, by: 5) {
                    if let pixel = image.pixel(x: x, y: y), pixel.r > 150, pixel.g < 120, pixel.b < 120 {
                        redPixels += 1
                    }
                }
            }
            XCTAssertGreaterThan(redPixels, 100, "The cached \(matrix ? "matrix" : "flap") must contain the board")
        }
    }
}
