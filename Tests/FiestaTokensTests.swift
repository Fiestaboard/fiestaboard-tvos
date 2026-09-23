import SwiftUI
import XCTest
@testable import FiestaBoardTV

final class FiestaTokensTests: XCTestCase {

    /// Brand orange is the one value shared verbatim with FiestaUI's
    /// theme.css, where it is --primary in both light and dark.
    func testBrandIsFiestaOrange() {
        XCTAssertEqual(Fiesta.Colors.brandHex.lowercased(), "#f5a623")
    }

    /// The icon generator compiles TacoMark on its own, without the UI
    /// layer, so brand amber is spelled out in two places. They must agree.
    func testTacoMarkBrandFieldMatchesTheToken() throws {
        let components = try XCTUnwrap(TacoMark.Ink.brand.components)
        let hex = components.prefix(3)
            .map { String(format: "%02x", Int(($0 * 255).rounded())) }
            .joined()
        XCTAssertEqual("#" + hex, Fiesta.Colors.brandHex.lowercased())
    }

    /// The board background is #1a1a1a, never pure black: a real flap
    /// reflects light, and pure black reads as a dead panel.
    func testBoardBackgroundIsNotPureBlack() {
        XCTAssertNotEqual(BoardColor.black.hex.lowercased(), "#000000")
    }

    func testEveryTokenResolves() {
        // Cheap guard against a token being added without a value.
        _ = Fiesta.Colors.background
        _ = Fiesta.Colors.surface
        _ = Fiesta.Colors.surfaceRaised
        _ = Fiesta.Colors.foreground
        _ = Fiesta.Colors.mutedForeground
        _ = Fiesta.Colors.brand
        _ = Fiesta.Colors.border
        _ = Fiesta.Colors.destructive
    }
}
