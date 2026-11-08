import SwiftUI
import XCTest
@testable import FiestaBoardTV

/// The LED viewer board at 07b A6 `I166:195024;149:182603` (an instance of
/// `150:7480` "TV Board / Living room TV · LED pixel canvas 64×36", as
/// redrawn to the DD24 hub model): the fixture's hub panel and frame through
/// the app's painter, full-bleed at 1920 × 1080, lighting on.
@MainActor
final class LedViewerSnapshotTests: XCTestCase {

    /// `Tests/Fixtures/figma-content/led-all-layers.json`: the hub panel,
    /// the hub frame (cells and layers) and what the Figma frame draws.
    struct Fixture {
        let panel: Panel
        let frame: PanelFrame
        let figma: [String: Any]

        static func load() throws -> Fixture {
            let url = TVSnapshot.repoRoot.appendingPathComponent("Tests/Fixtures/figma-content/led-all-layers.json")
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            // The fixture's panel is the hub's LED fields; the rest of a
            // panel comes from the one-panel fixture.
            let fields = try XCTUnwrap(json["panel"] as? [String: Any])
            let panel = try MatrixDisplayTests.panel(fields)
            let frameData = try JSONSerialization.data(withJSONObject: XCTUnwrap(json["frame"]))
            let frame = try JSONDecoder().decode(PanelFrame.self, from: frameData)
            return Fixture(panel: panel, frame: frame, figma: try XCTUnwrap(json["figma"] as? [String: Any]))
        }

        var raster: MatrixRaster {
            MatrixRaster.make(panel: panel, cells: [], richCells: frame.richCells, layers: frame.layers)
        }

        /// The viewer's board: `fill_tv`, no drift, still (as a snapshot).
        var board: some View {
            MatrixCanvas(raster: raster, display: panel.matrixDisplay,
                         presentation: panel.matrixPresentation ?? .init(sizing: .fillTV))
                .frame(width: TVSnapshot.size.width, height: TVSnapshot.size.height)
                .background(Color.black)
        }
    }

    func testTheA6AllLayersBoard() throws {
        let fixture = try Fixture.load()
        XCTAssertEqual(fixture.panel.renderStyle, .ledMatrix)
        XCTAssertEqual(fixture.panel.matrixDisplay.appearance?.pixelShape, "square")
        XCTAssertEqual(fixture.raster.width, 64)
        XCTAssertEqual(fixture.raster.height, 36)
        let image = TVSnapshot.image(fixture.board, fullBleed: true)
        try ParityOutput.write(png: image, as: "viewer-led-all-layers")
        TVSnapshot.assertMatches(image, named: "viewer-led-all-layers")
    }
}
