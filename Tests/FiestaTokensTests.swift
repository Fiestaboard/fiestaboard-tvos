import SwiftUI
import XCTest
@testable import FiestaBoardTV

final class FiestaTokensTests: XCTestCase {

    /// Brand orange is the one value shared verbatim with FiestaUI's
    /// theme.css, where it is --primary in both light and dark.
    func testBrandIsFiestaOrange() {
        XCTAssertEqual(Fiesta.Colors.brandHex.lowercased(), "#f5a623")
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
