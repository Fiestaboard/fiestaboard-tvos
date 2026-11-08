import SwiftUI
import XCTest
@testable import FiestaBoardTV

/// A4b — the viewer's chrome material (PHASE-4-TV-PLAN §2.2 A4b; D15 (a);
/// DD4). One surface, three named 07b variants of `tvOS / Viewer overlay`
/// `250:110554`.
final class ViewerSurfaceTests: XCTestCase {

    func testGlassOnTvOS26AndTheRegularMaterialBelow() {
        XCTAssertEqual(ViewerMaterial.resolve(reduceTransparency: false, glassAvailable: true, forced: nil), .liquidGlass)
        XCTAssertEqual(ViewerMaterial.resolve(reduceTransparency: false, glassAvailable: false, forced: nil), .regularMaterial,
                       "D15 (a): below tvOS 26 the DD4 interim, not nothing")
    }

    /// tvOS already dims glass under Reduce Transparency; 07b still asks for
    /// an explicitly opaque surface, so the board never reads through text.
    func testReduceTransparencyIsAlwaysOpaque() {
        for glass in [true, false] {
            for forced in [nil, ViewerMaterial.liquidGlass, .regularMaterial, .opaque] {
                XCTAssertEqual(ViewerMaterial.resolve(reduceTransparency: true, glassAvailable: glass, forced: forced), .opaque,
                               "glass \(glass), forced \(String(describing: forced))")
            }
        }
    }

    /// The DEBUG force exists for the shots: neither CI (tvOS 26.2) nor a
    /// current Xcode can run the pre-26 branch natively.
    func testAForceSelectsANamedInterimButCannotConjureGlass() {
        XCTAssertEqual(ViewerMaterial.resolve(reduceTransparency: false, glassAvailable: true, forced: .regularMaterial), .regularMaterial)
        XCTAssertEqual(ViewerMaterial.resolve(reduceTransparency: false, glassAvailable: true, forced: .opaque), .opaque)
        XCTAssertEqual(ViewerMaterial.resolve(reduceTransparency: false, glassAvailable: false, forced: .liquidGlass), .regularMaterial,
                       "no .glassEffect before tvOS 26")
    }

    func testEachMaterialNamesItsFigmaVariant() {
        XCTAssertEqual(ViewerMaterial.liquidGlass.overlayVariantNode, "154:8170")
        XCTAssertEqual(ViewerMaterial.regularMaterial.overlayVariantNode, "250:110532")
        XCTAssertEqual(ViewerMaterial.opaque.overlayVariantNode, "250:110540")
    }

    func testTheLaunchArgumentNamesEachMaterial() {
        XCTAssertEqual(ViewerMaterial(launchArgument: "glass"), .liquidGlass)
        XCTAssertEqual(ViewerMaterial(launchArgument: "regular"), .regularMaterial)
        XCTAssertEqual(ViewerMaterial(launchArgument: "opaque"), .opaque)
        XCTAssertNil(ViewerMaterial(launchArgument: "frosted"))
        XCTAssertNil(ViewerMaterial(launchArgument: nil))
    }

    func testThisSimulatorHasGlass() {
        // CI is tvOS 26.2 and local 27.x: the glass golden is real glass.
        XCTAssertTrue(ViewerMaterial.glassAvailable)
    }
}

/// A4b — Back dismisses the overlay before it leaves the viewer.
final class ViewerBackTests: XCTestCase {
    func testBackOrder() {
        XCTAssertEqual(ViewerBack.action(oledConsumed: true, overlayVisible: false), .wake,
                       "a resting OLED screen wakes first")
        XCTAssertEqual(ViewerBack.action(oledConsumed: true, overlayVisible: true), .wake)
        XCTAssertEqual(ViewerBack.action(oledConsumed: false, overlayVisible: true), .dismissOverlay,
                       "the overlay goes before the viewer does")
        XCTAssertEqual(ViewerBack.action(oledConsumed: false, overlayVisible: false), .leave)
    }
}
