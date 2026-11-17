import CoreGraphics
import XCTest

/// Locks the `GlassMeasurement.isTranslucentGlass` band with synthetic
/// images, so the mutation checks run by hand in A0 (an opaque panel and a
/// panel with no effect both fail) are regression-protected (review #15, 6.3).
/// Pure CoreGraphics: no simulator rendering involved.
final class GlassProbeTests: XCTestCase {
    private let scale: CGFloat = 1
    private let size = CGSize(width: 1920, height: 1080)
    private let panel = CGRect(x: 480, y: 300, width: 960, height: 320)

    private enum Panel { case none, opaque, tint, blur }

    /// 40 pt red/blue stripes, then the panel drawn over them.
    private func image(_ panelKind: Panel) throws -> CGImage {
        let width = Int(size.width * scale), height = Int(size.height * scale)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // Flip to top-left origin, matching UIKit and GlassProbe's sampling.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)
        for index in 0..<48 {
            ctx.setFillColor(index.isMultiple(of: 2) ? CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
                                                     : CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: CGFloat(index) * 40, y: 0, width: 40, height: size.height))
        }
        switch panelKind {
        case .none:
            break
        case .opaque:
            ctx.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
            ctx.fill(panel)
        case .tint:
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.5))
            ctx.fill(panel)
        case .blur:
            // A crude stand-in for a material: each stripe inside the panel
            // is pulled most of the way toward purple, plus a light wash.
            for index in 0..<48 {
                let red = index.isMultiple(of: 2)
                ctx.setFillColor(CGColor(srgbRed: red ? 0.75 : 0.45, green: 0.25, blue: red ? 0.45 : 0.75, alpha: 1))
                ctx.fill(CGRect(x: CGFloat(index) * 40, y: panel.minY, width: 40, height: panel.height)
                    .intersection(panel))
            }
        }
        return try XCTUnwrap(ctx.makeImage())
    }

    private func measure(_ kind: Panel) throws -> GlassMeasurement {
        try XCTUnwrap(GlassProbe.measure(image(kind), scale: scale, panel: panel))
    }

    func testNoPanelIsNotGlass() throws {
        let m = try measure(.none)
        XCTAssertEqual(m.followsBackdrop, 510, accuracy: 1)
        XCTAssertEqual(m.alteredFromBackdrop, 0, accuracy: 1)
        XCTAssertFalse(m.isTranslucentGlass)
    }

    func testAnOpaquePanelIsNotGlass() throws {
        let m = try measure(.opaque)
        XCTAssertEqual(m.followsBackdrop, 0, accuracy: 1)
        XCTAssertFalse(m.isTranslucentGlass)
    }

    func testAMaterialLikePanelIsTranslucentGlass() throws {
        let m = try measure(.blur)
        XCTAssertTrue(m.isTranslucentGlass, "\(m.dictionary)")
    }

    /// Known limit, kept visible: a flat 50 % tint also reads as translucent.
    /// The probe proves "backdrop shows through and something is composited",
    /// not blur; Fable judges blur by eye (MASTER-PLAN §3.3 check 4).
    func testAFlatTintAlsoPassesByDesign() throws {
        let m = try measure(.tint)
        XCTAssertTrue(m.isTranslucentGlass, "\(m.dictionary)")
    }

    func testCleanColumnsAreSampledOnBothStripeColours() throws {
        let m = try measure(.blur)
        XCTAssertGreaterThan(m.redColumns, 50)
        XCTAssertGreaterThan(m.blueColumns, 50)
        XCTAssertEqual(m.samples, m.redColumns + m.blueColumns)
    }
}
