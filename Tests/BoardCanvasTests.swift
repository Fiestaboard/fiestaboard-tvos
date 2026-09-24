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
        // The lit edge sits under the gap; both scale with the tile, so on
        // a 200pt tile the highlight's centre is at 100 + 2.5 + 1.25.
        let metrics = BoardCanvas.seam(forTileHeight: board.tileHeight)
        let highlightY = Int(100 + metrics.thickness * 1.5)
        XCTAssertEqual(highlightY, 103)
        let seam = try XCTUnwrap(image.pixel(x: Int(board.width / 2), y: highlightY))
        XCTAssertLessThanOrEqual(Int(face.r), 2)
        XCTAssertGreaterThan(Int(seam.r), 12, "the split should read on an OLED black tile")
    }

    /// The split is a physical gap and scales with the flap. Below a pixel
    /// it fades rather than staying a fixed two pixels, which on a 19pt
    /// preview tile is as heavy as the glyph and reads as striping.
    func testTheSeamScalesWithTheTileAndNeverVanishes() throws {
        XCTAssertEqual(BoardCanvas.seam(forTileHeight: 200), .init(thickness: 2.5, ink: 1))
        let viewer = BoardCanvas.seam(forTileHeight: 75)
        XCTAssertEqual(viewer.thickness, 1)
        XCTAssertEqual(viewer.ink, 0.9375, accuracy: 1e-9, "a hairline at viewer size, as before")
        XCTAssertEqual(BoardCanvas.seam(forTileHeight: 19), .init(thickness: 1, ink: 0.3))
        XCTAssertEqual(BoardCanvas.seam(forTileHeight: 4), .init(thickness: 1, ink: 0.3), "a trace survives any size")

        func brightestSeamPixel(tileHeight: Double) throws -> Int {
            let board = layout(cells: [[.blank]], tileHeight: tileHeight)
            let image = smallBoardImage(BoardCanvas(layout: board, background: .black),
                                        size: CGSize(width: board.width, height: board.height))
            let x = Int(board.width / 2)
            return try (0..<Int(board.height)).map { y in Int(try XCTUnwrap(image.pixel(x: x, y: y)).r) }.max() ?? 0
        }
        let preview = try brightestSeamPixel(tileHeight: 19)
        XCTAssertGreaterThan(preview, 4, "the split still reads on a preview tile")
        XCTAssertLessThan(preview, 18, "but no longer as a stripe")
        let viewerSize = try brightestSeamPixel(tileHeight: 75)
        XCTAssertGreaterThan(viewerSize, 24, "unchanged at viewer size: a 0.13 white hairline")
        XCTAssertLessThan(viewerSize, 40)
    }

    /// The board at preview size (19pt and 32pt tiles, as the panel cards and
    /// Top Shelf draw it) and at viewer size (75pt), before and after the
    /// seam became proportional. `seam-before-NNpt` is the fixed 2px seam
    /// kept in `LegacySquashPainter`; `seam-after-NNpt` is the renderer now;
    /// `seam-sheet` is all six, before on the top row, at 3× for viewing.
    func testAttachesTheSeamAtPreviewAndViewerSizes() throws {
        let cells: [[BoardCell]] = [
            [.character("H"), .character("E"), .character("L"), .character("L"), .character("O")],
            [.blank, .character("1"), .character("2"), .blank, .color(.red)],
            [.character("T"), .character("V"), .blank, .character("O"), .character("K")],
        ]
        let started = Date(timeIntervalSince1970: 0)
        var images: [[UIImage]] = [[], []]
        for height in [19.0, 32.0, 75.0] {
            let board = layout(cells: cells, tileHeight: height)
            let still = BoardFlipTransition(from: board.tiles.map(\.cell), to: board.tiles.map(\.cell),
                                            code62: .degree, startedAt: started)
            let size = CGSize(width: board.width, height: board.height)
            for (row, legacy) in [true, false].enumerated() {
                let view = Canvas { context, _ in
                    if legacy {
                        LegacySquashPainter.paint(board, transition: still, at: started, in: &context)
                    } else {
                        BoardCanvas.paint(board, background: .black, transition: nil, at: started, in: &context)
                    }
                }
                .frame(width: size.width, height: size.height)
                let image = smallBoardImage(view, size: size)
                images[row].append(image)
                let attachment = XCTAttachment(image: image)
                attachment.name = "seam-\(legacy ? "before" : "after")-\(Int(height))pt"
                attachment.lifetime = .keepAlways
                add(attachment)
                // Glyph ink is #f0f0e8; a frame with none of it drew nothing.
                let brightest = (0..<Int(size.height)).flatMap { y in
                    (0..<Int(size.width)).compactMap { x in image.pixel(x: x, y: y).map { Int($0.r) } }
                }.max() ?? 0
                XCTAssertGreaterThan(brightest, 180, "a \(height)pt board rendered nothing")
            }
        }

        let zoom = 3.0
        let cell = CGSize(width: images[0].map(\.size.width).max()! + 20, height: images[0].map(\.size.height).max()! + 20)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let sheet = UIGraphicsImageRenderer(size: CGSize(width: cell.width * 3 * zoom, height: cell.height * 2 * zoom),
                                            format: format).image { context in
            context.cgContext.interpolationQuality = .none
            for (row, series) in images.enumerated() {
                for (column, image) in series.enumerated() {
                    image.draw(in: CGRect(x: (cell.width * Double(column) + 10) * zoom,
                                          y: (cell.height * Double(row) + 10) * zoom,
                                          width: image.size.width * zoom, height: image.size.height * zoom))
                }
            }
        }
        let sheetAttachment = XCTAttachment(image: sheet)
        sheetAttachment.name = "seam-sheet"
        sheetAttachment.lifetime = .keepAlways
        add(sheetAttachment)
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

    /// `RenderHarness.image` paints nothing into a window smaller than a
    /// few hundred points on the tvOS simulator, so small boards are drawn
    /// into the full TV-size window, pinned top-leading, and cropped out.
    private func smallBoardImage<V: View>(_ view: V, size: CGSize) -> UIImage {
        let full = RenderHarness.image(
            view.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color.black))
        let crop = CGRect(x: 0, y: 0, width: ceil(size.width), height: ceil(size.height))
        guard let cg = full.cgImage?.cropping(to: crop) else { return full }
        return UIImage(cgImage: cg)
    }

    // MARK: - Flap physics

    func testTheLeafFallsUnderGravityAndBouncesOffTheStop() {
        XCTAssertEqual(FlapPhysics.angle(at: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(FlapPhysics.angle(at: FlapPhysics.impact), .pi, accuracy: 1e-9)
        XCTAssertEqual(FlapPhysics.angle(at: 1), .pi, accuracy: 1e-9)

        // Gravity, not an ease: the last tenth of the fall covers far more
        // arc than the first tenth.
        let tenth = FlapPhysics.impact / 10
        let early = FlapPhysics.angle(at: tenth) - FlapPhysics.angle(at: 0)
        let late = FlapPhysics.angle(at: FlapPhysics.impact) - FlapPhysics.angle(at: FlapPhysics.impact - tenth)
        XCTAssertGreaterThan(late, early * 6)

        var last = 0.0
        for step in 0...64 {
            let angle = FlapPhysics.angle(at: Double(step) / 100)
            XCTAssertGreaterThanOrEqual(angle, last, "the fall never reverses")
            last = angle
        }

        // Impact is not a settle: the leaf kicks back off the stop, then rests.
        let rebound = FlapPhysics.angle(at: 0.78)
        XCTAssertLessThan(rebound, .pi - 0.1)
        XCTAssertGreaterThan(rebound, .pi / 2)
        XCTAssertFalse(FlapPhysics.showsNext(at: 0.2))
        XCTAssertTrue(FlapPhysics.showsNext(at: 0.5))
    }

    func testPerspectiveWidensTheFreeEdgeAndForeshortensNonlinearly() {
        XCTAssertEqual(FlapPhysics.projection(angle: 0), .init(height: 1, widthFactor: 1))
        XCTAssertEqual(FlapPhysics.projection(angle: .pi).height, 1, accuracy: 1e-9)
        XCTAssertEqual(FlapPhysics.projection(angle: .pi / 2).height, 0, accuracy: 1e-9)

        let mid = FlapPhysics.projection(angle: .pi / 4)
        XCTAssertGreaterThan(mid.widthFactor, 1.08, "the near edge is fractionally wider")
        XCTAssertLessThan(mid.widthFactor, 1.2, "but only fractionally")
        XCTAssertGreaterThan(mid.height, cos(.pi / 4),
                             "the near edge is magnified, so the leaf reads taller than a flat cosine squash")
    }

    func testTheFaceDarkensThroughTheFallAndCatchesTheLightBackAtVertical() {
        XCTAssertEqual(FlapPhysics.brightness(angle: 0), 1, accuracy: 1e-9, "no pop against the static tile")
        XCTAssertEqual(FlapPhysics.brightness(angle: .pi), 1, accuracy: 1e-9)
        for step in 0...100 {
            XCTAssertLessThanOrEqual(FlapPhysics.brightness(angle: .pi * Double(step) / 100), 1,
                                     "nothing is brighter than the face at rest")
        }
        XCTAssertLessThan(FlapPhysics.brightness(angle: 0.15), 0.95, "the sheen goes as soon as it tips")
        XCTAssertLessThan(FlapPhysics.brightness(angle: 1.2), 0.75, "turned away from the light")
        XCTAssertLessThan(FlapPhysics.brightness(angle: .pi / 2 + 0.2), 0.4, "the back face arrives facing the floor")
        XCTAssertLessThan(FlapPhysics.brightness(angle: .pi - 0.2), 0.85, "the bounce drops out of the highlight")
        XCTAssertGreaterThan(FlapPhysics.brightness(angle: .pi - 0.2), FlapPhysics.brightness(angle: .pi - 0.6),
                             "and brightens on the way back up to the stop")
    }

    func testTheCastShadowGrowsWithTheFallAndIsCoveredAtRest() {
        XCTAssertEqual(FlapPhysics.castShadow(angle: 0).opacity, 0)
        XCTAssertEqual(FlapPhysics.castShadow(angle: .pi / 2).depth, 1)
        let partial = FlapPhysics.castShadow(angle: 1.2)
        XCTAssertGreaterThan(partial.depth, 0)
        XCTAssertLessThan(partial.depth, 1)
        XCTAssertEqual(FlapPhysics.projection(angle: .pi).height, 1, accuracy: 1e-9,
                       "the landed leaf covers the whole lower half, so the shadow under it is hidden")
    }

    // MARK: - Flap rendering

    /// Mid-fall the leaf has swung toward the eye, so its free edge projects
    /// wider than the tile: pixels in the gutter beside the tile light up.
    func testTheFallingLeafComesOffTheBoardIntoTheGutter() throws {
        let board = layout(cells: [[.color(.white), .color(.black)]], tileHeight: 200)
        let tile = board.tiles[1]
        let started = Date(timeIntervalSince1970: 0)
        // White is code 69 and black 70: one drum step, the white leaf falling.
        let flip = BoardFlipTransition(from: [.color(.white), .color(.white)],
                                       to: [.color(.white), .color(.black)],
                                       code62: .degree, startedAt: started)
        let progress = 0.35
        let angle = FlapPhysics.angle(at: progress)
        XCTAssertGreaterThan(angle, 0.9, "sanity: this sample is mid-fall")
        XCTAssertLessThan(angle, .pi / 2)
        let leafHeight = tile.height / 2 * FlapPhysics.projection(angle: angle).height
        let sampleX = Int(tile.x) - 3
        let sampleY = Int(tile.y + tile.height / 2 - leafHeight * 0.8)

        func pixel(at date: Date) throws -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            let view = Canvas { context, _ in
                BoardCanvas.paint(board, background: .black, transition: flip, at: date, in: &context)
            }
            .frame(width: board.width, height: board.height)
            .background(Color.black)
            let image = RenderHarness.image(view, size: CGSize(width: board.width, height: board.height))
            return try XCTUnwrap(image.pixel(x: sampleX, y: sampleY))
        }

        let atRest = try pixel(at: started)
        XCTAssertLessThanOrEqual(Int(atRest.r), 2, "the gutter is empty while the leaf stands upright")
        let midFall = try pixel(at: started.addingTimeInterval(progress * BoardFlipTransition.stepDuration))
        XCTAssertGreaterThan(Int(midFall.r), 48, "the leaf's near edge overhangs the gutter")
        XCTAssertLessThan(Int(midFall.r), 200, "and has turned away from the light")
    }

    /// The landing is an impact: for a moment after it hits the stop the leaf
    /// has kicked back off it and is out of the light, visibly darker than
    /// it will be at rest.
    func testTheLeafDipsOutOfTheLightAsItBouncesOffTheStop() throws {
        let board = layout(cells: [[.character("A")]], tileHeight: 240)
        let tile = board.tiles[0]
        let started = Date(timeIntervalSince1970: 0)
        let flip = BoardFlipTransition(from: [.blank], to: [.character("A")],
                                       code62: .degree, startedAt: started)
        // Well clear of the glyph, on the lower half the landed leaf covers.
        let sampleX = Int(tile.width * 0.15)
        let sampleY = Int(tile.height * 0.75)

        func pixel(at date: Date) throws -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            let view = Canvas { context, _ in
                BoardCanvas.paint(board, background: .white, transition: flip, at: date, in: &context)
            }
            .frame(width: board.width, height: board.height)
            .background(Color.white)
            let image = RenderHarness.image(view, size: CGSize(width: board.width, height: board.height))
            return try XCTUnwrap(image.pixel(x: sampleX, y: sampleY))
        }

        let bounce = try pixel(at: started.addingTimeInterval(0.78 * BoardFlipTransition.stepDuration))
        let rest = try pixel(at: started.addingTimeInterval(BoardFlipTransition.stepDuration))
        XCTAssertGreaterThan(Int(rest.r), 0xd8, "at rest the face is the plain light flap")
        XCTAssertLessThan(Int(bounce.r), Int(rest.r) - 20, "in the bounce it has dropped out of the highlight")
        XCTAssertGreaterThan(Int(bounce.r), 0x80, "but it is the lit next face, not the shadowed old one")
    }

    /// Twelve frames through one drum step of a single tile, attached so the
    /// motion can be inspected without a TV. `flip-NN-of-12` is the physical
    /// leaf on OLED-black hardware, `flip-light-NN-of-12` the same on white
    /// hardware where the face is lit; `squash-NN-of-12` is the previous
    /// behaviour — the CSS port, kept verbatim in `LegacySquashPainter`
    /// below — for comparison. `flip-sheet` stacks the three sequences in
    /// one image, physical black on top, physical light, then the squash.
    func testAttachesOneFlipFrameByFrame() throws {
        let board = layout(cells: [[.character("B")]], tileHeight: 240)
        let started = Date(timeIntervalSince1970: 0)
        let flip = BoardFlipTransition(from: [.character("A")], to: [.character("B")],
                                       code62: .degree, startedAt: started)
        let frames = 12
        let pad = board.tileHeight * BoardGeometry.tileGutterRatio
        let size = CGSize(width: board.width + pad * 2, height: board.height + pad * 2)

        func frame(at date: Date, legacy: Bool, hardware: BoardColor = .black) -> UIImage {
            let view = Canvas { context, _ in
                context.translateBy(x: pad, y: pad)
                if legacy {
                    LegacySquashPainter.paint(board, transition: flip, at: date, in: &context)
                } else {
                    BoardCanvas.paint(board, background: hardware, transition: flip, at: date, in: &context)
                }
            }
            .frame(width: size.width, height: size.height)
            .background(hardware == .black ? Color.black : hardware.swiftUI)
            return RenderHarness.image(view, size: size)
        }

        var physical: [UIImage] = []
        var light: [UIImage] = []
        var squash: [UIImage] = []
        for index in 0..<frames {
            let progress = Double(index) / Double(frames - 1)
            let date = started.addingTimeInterval(progress * BoardFlipTransition.stepDuration)
            let label = String(format: "%02d-of-%02d", index + 1, frames)

            let new = frame(at: date, legacy: false)
            physical.append(new)
            let newAttachment = XCTAttachment(image: new)
            newAttachment.name = "flip-\(label)"
            newAttachment.lifetime = .keepAlways
            add(newAttachment)

            // White hardware has a lit face, which is where the perspective,
            // the shading and the cast shadow are actually visible.
            let onLight = frame(at: date, legacy: false, hardware: .white)
            light.append(onLight)
            let litAttachment = XCTAttachment(image: onLight)
            litAttachment.name = "flip-light-\(label)"
            litAttachment.lifetime = .keepAlways
            add(litAttachment)

            let old = frame(at: date, legacy: true)
            squash.append(old)
            let oldAttachment = XCTAttachment(image: old)
            oldAttachment.name = "squash-\(label)"
            oldAttachment.lifetime = .keepAlways
            add(oldAttachment)

            // Every frame must actually contain a tile: an all-black frame
            // is the renderer silently drawing nothing.
            let centreX = Int(size.width / 2)
            let lit = (0..<Int(size.height)).contains { y in
                guard let p = new.pixel(x: centreX, y: y) else { return false }
                return Int(p.r) > 40
            }
            XCTAssertTrue(lit, "frame \(label) rendered nothing")
        }

        let sheetFormat = UIGraphicsImageRendererFormat()
        sheetFormat.scale = 1
        let sheet = UIGraphicsImageRenderer(
            size: CGSize(width: size.width * Double(frames), height: size.height * 3),
            format: sheetFormat
        ).image { _ in
            for (row, images) in [physical, light, squash].enumerated() {
                for (index, image) in images.enumerated() {
                    image.draw(at: CGPoint(x: size.width * Double(index), y: size.height * Double(row)))
                }
            }
        }
        let sheetAttachment = XCTAttachment(image: sheet)
        sheetAttachment.name = "flip-sheet"
        sheetAttachment.lifetime = .keepAlways
        add(sheetAttachment)
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

/// The flip as it was before the physical leaf: FiestaUI's CSS effect ported
/// as a 2D vertical squash. Frozen here so `testAttachesOneFlipFrameByFrame`
/// can attach the old and new behaviour side by side; not used by the app.
@MainActor
private enum LegacySquashPainter {

    static func paint(_ layout: BoardLayout, transition: BoardFlipTransition,
                      at date: Date, in context: inout GraphicsContext) {
        let font = BoardFont.glyph(size: layout.fontSize)
        let ink = Color(hex: "#f0f0e8")
        for (index, tile) in layout.tiles.enumerated() {
            let sample = transition.sample(index: index, at: date)
            if sample.isAnimating {
                paintSplit(tile: tile, sample: sample, in: &context, font: font, ink: ink)
            } else {
                draw(tile: tile, cell: tile.cell, in: &context, font: font, ink: ink)
            }
            let midY = tile.y + tile.height / 2
            context.fill(Path(CGRect(x: tile.x, y: midY, width: tile.width, height: 1)),
                         with: .color(Color.black.opacity(0.35)))
            context.fill(Path(CGRect(x: tile.x, y: midY + 1, width: tile.width, height: 1)),
                         with: .color(Color.white.opacity(0.13)))
        }
    }

    private static func paintSplit(tile: TileRect, sample: BoardFlipTransition.Sample,
                                   in context: inout GraphicsContext, font: Font, ink: Color) {
        let midY = tile.y + tile.height / 2
        let top = CGRect(x: tile.x, y: tile.y, width: tile.width, height: tile.height / 2)
        let bottom = CGRect(x: tile.x, y: midY, width: tile.width, height: tile.height / 2)

        var newTop = context
        newTop.clip(to: Path(top))
        draw(tile: tile, cell: sample.next, in: &newTop, font: font, ink: ink)

        var oldBottom = context
        oldBottom.clip(to: Path(bottom))
        draw(tile: tile, cell: sample.previous, in: &oldBottom, font: font, ink: ink)

        if sample.progress < 0.5 {
            let t = sample.progress * 2
            let fall = t * t
            let scale = max(0.001, cos(.pi / 2 * fall))
            var flap = context
            flap.clip(to: Path(top))
            flap.translateBy(x: 0, y: midY)
            flap.scaleBy(x: 1, y: scale)
            flap.translateBy(x: 0, y: -midY)
            draw(tile: tile, cell: sample.previous, in: &flap, font: font, ink: ink)
        } else {
            let t = (sample.progress - 0.5) * 2
            let settle = 1 - pow(1 - t, 3)
            let scale = max(0.001, sin(.pi / 2 * settle))
            var flap = context
            flap.clip(to: Path(bottom))
            flap.translateBy(x: 0, y: midY)
            flap.scaleBy(x: 1, y: scale)
            flap.translateBy(x: 0, y: -midY)
            draw(tile: tile, cell: sample.next, in: &flap, font: font, ink: ink)
        }

        let shadow = 0.25 * sin(.pi * sample.progress)
        context.fill(Path(bottom), with: .color(Color.black.opacity(shadow)))
    }

    private static func draw(tile: TileRect, cell: BoardCell, in context: inout GraphicsContext,
                             font: Font, ink: Color) {
        let rect = CGRect(x: tile.x, y: tile.y, width: tile.width, height: tile.height)
        let shape = Path(roundedRect: rect, cornerRadius: tile.radius)
        switch cell {
        case .blank:
            context.fill(shape, with: .color(.black))
        case .color(let color):
            context.fill(shape, with: .color(color == .black ? .black : color.swiftUI))
        case .character(let character):
            context.fill(shape, with: .color(.black))
            let text = context.resolve(Text(String(character)).font(font).foregroundColor(ink))
            context.draw(text, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
        }
    }
}
