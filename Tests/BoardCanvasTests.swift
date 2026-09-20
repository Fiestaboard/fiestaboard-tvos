import SwiftUI
import XCTest
@testable import FiestaBoardTV

@MainActor
final class BoardCanvasTests: XCTestCase {

    private func layout(cells: [[BoardCell]], tileHeight: Double = 100) -> BoardLayout {
        BoardLayout.make(rows: cells.count, cols: cells.first?.count ?? 0,
                         cells: cells, tileHeight: tileHeight)
    }

    func testRendersWithoutCrashing() {
        let grid = [[BoardCell.character("A"), .color(.red)], [.blank, .character("9")]]
        RenderHarness.render(BoardCanvas(layout: layout(cells: grid), background: .black))
    }

    /// The largest grid a panel can have — the case the Canvas approach
    /// exists for. 45x18 is an 85" auto-fit board.
    func testRendersTheLargestSupportedGrid() {
        let grid = Array(repeating: Array(repeating: BoardCell.character("W"), count: 45), count: 18)
        RenderHarness.render(BoardCanvas(layout: layout(cells: grid, tileHeight: 55), background: .black))
    }

    func testRendersAnEmptyBoard() {
        RenderHarness.render(BoardCanvas(layout: layout(cells: []), background: .black))
    }

    func testRendersWithAnimationEnabled() {
        let grid = [[BoardCell.character("A")]]
        RenderHarness.render(BoardCanvas(layout: layout(cells: grid), background: .black, animated: true))
    }

    func testFlipTransitionWalksTheFiestaUIDrumAtEightyMillisecondsPerStep() {
        let started = Date(timeIntervalSince1970: 0)
        let flip = BoardFlipTransition(from: [.character("A")], to: [.character("D")],
                                       code62: .degree, startedAt: started)
        XCTAssertEqual(flip.duration, 0.24, accuracy: 0.0001)

        let falling = flip.sample(index: 0, at: started.addingTimeInterval(0.02))
        XCTAssertEqual(falling.previous, .character("A"))
        XCTAssertEqual(falling.next, .character("B"))
        XCTAssertEqual(falling.progress, 0.25, accuracy: 0.0001)
        XCTAssertTrue(falling.isAnimating)

        let rising = flip.sample(index: 0, at: started.addingTimeInterval(0.06))
        XCTAssertEqual(rising.cell, .character("B"))
        XCTAssertEqual(rising.progress, 0.75, accuracy: 0.0001)

        let secondStep = flip.sample(index: 0, at: started.addingTimeInterval(0.10))
        XCTAssertEqual(secondStep.previous, .character("B"))
        XCTAssertEqual(secondStep.next, .character("C"))

        let settled = flip.sample(index: 0, at: started.addingTimeInterval(0.24))
        XCTAssertEqual(settled.cell, .character("D"))
        XCTAssertFalse(settled.isAnimating)
    }

    func testDrumStepsStayInSyncAndWrapThroughBlack() {
        let started = Date(timeIntervalSince1970: 0)
        let flip = BoardFlipTransition(from: [.color(.black), .color(.black)],
                                       to: [.character("A"), .character("A")],
                                       code62: .degree, startedAt: started)
        XCTAssertEqual(flip.duration, 0.24, accuracy: 0.0001)
        for index in 0..<2 {
            let first = flip.sample(index: index, at: started.addingTimeInterval(0.02))
            XCTAssertEqual(first.previous, .color(.black))
            XCTAssertEqual(first.next, .color(.black), "code 71 is the second black flap")
            let second = flip.sample(index: index, at: started.addingTimeInterval(0.10))
            XCTAssertEqual(second.previous, .color(.black))
            XCTAssertEqual(second.next, .blank)
            let third = flip.sample(index: index, at: started.addingTimeInterval(0.18))
            XCTAssertEqual(third.previous, .blank)
            XCTAssertEqual(third.next, .character("A"))
        }
    }

    func testNoteDrumShowsHeartAtCodeSixtyTwo() {
        let started = Date(timeIntervalSince1970: 0)
        let flip = BoardFlipTransition(from: [.character("?")], to: [.character("♥")],
                                       code62: .heart, startedAt: started)
        let sample = flip.sample(index: 0, at: started.addingTimeInterval(0.10))
        XCTAssertEqual(sample.previous, .blank, "code 61 is undefined")
        XCTAssertEqual(sample.next, .character("♥"))
    }

    func testAChangedTargetContinuesFromTheVisibleFlap() {
        let started = Date(timeIntervalSince1970: 0)
        let first = BoardFlipTransition(from: [.character("A")], to: [.character("D")],
                                        code62: .degree, startedAt: started)
        let changedAt = started.addingTimeInterval(0.10)
        let next = first.retargeted(to: [.character("E")], at: changedAt)
        let sample = next.sample(index: 0, at: changedAt.addingTimeInterval(0.01))
        XCTAssertEqual(sample.previous, .character("B"))
        XCTAssertEqual(sample.next, .character("C"))
        XCTAssertEqual(next.duration, 0.24, accuracy: 0.0001)
    }

    func testFlipKeepsTheOldBottomWhileRevealingTheNewTop() throws {
        let board = layout(cells: [[.color(.orange)]], tileHeight: 200)
        let started = Date(timeIntervalSince1970: 0)
        let flip = BoardFlipTransition(from: [.color(.red)], to: [.color(.orange)],
                                       code62: .degree, startedAt: started)
        let view = Canvas { context, _ in
            BoardCanvas.paint(board, background: .black, transition: flip,
                              at: started.addingTimeInterval(0.038), in: &context)
        }
        .frame(width: board.width, height: board.height)
        .background(Color.black)
        let image = RenderHarness.image(view, size: CGSize(width: board.width, height: board.height))
        let top = try XCTUnwrap(image.pixel(x: Int(board.width / 2), y: 30))
        let bottom = try XCTUnwrap(image.pixel(x: Int(board.width / 2), y: 170))
        XCTAssertGreaterThan(Int(top.g), 140, "new orange top should be revealed")
        XCTAssertLessThan(Int(bottom.g), 110, "old red bottom should remain until it flips")
        XCTAssertGreaterThan(Int(bottom.r), 160, "the cast shadow should not erase the old red")
    }

    func testUnlitFlapHasAVisibleHingeWithoutLightingItsFace() throws {
        let board = layout(cells: [[.blank]], tileHeight: 200)
        let image = RenderHarness.image(BoardCanvas(layout: board, background: .black),
                                        size: CGSize(width: board.width, height: board.height))
        let face = try XCTUnwrap(image.pixel(x: Int(board.width / 2), y: 80))
        let seam = try XCTUnwrap(image.pixel(x: Int(board.width / 2), y: 101))
        XCTAssertLessThanOrEqual(Int(face.r), 2)
        XCTAssertGreaterThan(Int(seam.r), 12, "the split should read on an OLED black tile")
    }

    /// A color tile must paint its pigment across the leaf face. Sample above
    /// the hinge, whose shadow intentionally darkens the exact centre.
    func testAColorTilePaintsItsPigment() throws {
        let grid = [[BoardCell.color(.red)]]
        let board = layout(cells: grid, tileHeight: 200)
        let view = BoardCanvas(layout: board, background: .black)
            .frame(width: board.width, height: board.height)

        let image = RenderHarness.image(view, size: CGSize(width: board.width, height: board.height))
        let centre = try XCTUnwrap(image.pixel(x: Int(board.width / 2), y: Int(board.height * 0.4)))

        // #eb4034
        XCTAssertEqual(Int(centre.r), 0xeb, accuracy: 12, "red channel")
        XCTAssertEqual(Int(centre.g), 0x40, accuracy: 12, "green channel")
        XCTAssertEqual(Int(centre.b), 0x34, accuracy: 12, "blue channel")
    }

    func testWhiteHardwareUsesLightFlapsAndInvertsWhiteAndBlackCodes() throws {
        for (cell, shouldBeLight) in [(BoardCell.blank, true),
                                      (.color(.white), false),
                                      (.color(.black), true)] {
            let board = layout(cells: [[cell]], tileHeight: 200)
            let image = RenderHarness.image(BoardCanvas(layout: board, background: .white),
                                            size: CGSize(width: board.width, height: board.height))
            let pixel = try XCTUnwrap(image.pixel(x: Int(board.width / 2), y: Int(board.height / 2)))
            if shouldBeLight {
                XCTAssertGreaterThan(Int(pixel.r), 0xc0)
            } else {
                XCTAssertLessThan(Int(pixel.r), 0x60)
            }
        }
    }

    /// The gutter between two tiles must show the board behind them, which
    /// is what proves the pitch is being honoured rather than the tiles
    /// being drawn edge to edge.
    func testTheGutterShowsTheBoardBehind() throws {
        let grid = [[BoardCell.color(.white), BoardCell.color(.white)]]
        let board = layout(cells: grid, tileHeight: 200)
        let view = BoardCanvas(layout: board, background: .black)
            .frame(width: board.width, height: board.height)

        let image = RenderHarness.image(view, size: CGSize(width: board.width, height: board.height))

        // Tile 0 spans 0..140; the gutter runs 140..169; tile 1 starts at 169.
        let gutterX = Int(board.tiles[0].width + board.tileHeight * BoardGeometry.tileGutterRatio / 2)
        let gutter = try XCTUnwrap(image.pixel(x: gutterX, y: Int(board.height / 2)))
        XCTAssertLessThan(Int(gutter.r), 0x60, "the gutter must not be a lit flap")

        let tile = try XCTUnwrap(image.pixel(x: Int(board.tiles[0].width / 2), y: Int(board.height * 0.4)))
        XCTAssertGreaterThan(Int(tile.r), 0xc0, "a white flap must be lit")
    }

    func testBlackFlapsAndGutterAreTrueBlackForOLED() throws {
        let board = layout(cells: [[.blank, .color(.black)]], tileHeight: 200)
        let image = RenderHarness.image(BoardCanvas(layout: board, background: .black),
                                        size: CGSize(width: board.width, height: board.height))
        let first = try XCTUnwrap(image.pixel(x: Int(board.tiles[0].width / 2), y: 80))
        let gutter = try XCTUnwrap(image.pixel(x: Int(board.tiles[0].width + 10), y: 80))
        let second = try XCTUnwrap(image.pixel(x: Int(board.tiles[1].x + board.tiles[1].width / 2), y: 80))
        for pixel in [first, gutter, second] {
            XCTAssertLessThanOrEqual(Int(pixel.r), 2)
            XCTAssertLessThanOrEqual(Int(pixel.g), 2)
            XCTAssertLessThanOrEqual(Int(pixel.b), 2)
        }
    }

    func testBoardColorsBridgeToSwiftUI() {
        // Guards against a typo silently turning into black.
        XCTAssertNotEqual(BoardColor.red.swiftUI.description, BoardColor.blue.swiftUI.description)
        for color in BoardColor.allCases {
            XCTAssertFalse(color.hex.isEmpty)
        }
    }

    func testTheBoardFontRegistersFromTheBundle() {
        BoardFont.registerIfNeeded()
        XCTAssertNotNil(UIFont(name: BoardFont.familyName, size: 24),
                        "Spline Sans Mono must load from the bundle — the system fallback is a degradation, not the target")
    }
}
