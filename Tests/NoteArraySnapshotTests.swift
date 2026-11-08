import SwiftUI
import UIKit
import XCTest
@testable import FiestaBoardTV

/// A10 — note-array panels drawn as separate Notes, through the real viewer
/// (`ViewerScreen` + `ViewerModel`, panel decoded from `panel-notes-v1.json`).
///
/// Golden ↔ 07b:
/// - `viewer-note-array` → A5 `166:193912`, slot `I166:193912;149:182603`,
///   board `…;166:194992` = `TV Board / Lobby wall · Note array 2×2`
///   `149:184613` (Rosa's café), redrawn full-bleed at 1920 (DD24).
/// - `viewer-note-array-partial` → DD5's rule card (A5 `251:122469`): a 34 × 7
///   panel, the trailing Notes cut open. No 07b frame draws one.
///
/// Structural probe: the Notes' frames against the A5 board's
/// (`…;149:184615`, `…;149:184859`, `…;149:185134`, `…;149:185408`) within
/// ±5 % (N18-4), then pixel samples for the bezel, the gap and the tiles.
@MainActor
final class NoteArraySnapshotTests: XCTestCase {

    // MARK: 07b's café menu, Note by Note

    private static let heart = Code62Glyph.heart.character

    private static func text(_ s: String) -> [BoardCell] {
        precondition(s.count == 15, "a Note row is 15 cells: \"\(s)\"")
        return s.map { $0 == " " ? .blank : .character($0) }
    }

    private static let rainbow: [BoardCell] = (0..<15).map {
        .color([BoardColor.red, .orange, .yellow, .green, .blue, .violet][$0 % 6])
    }

    /// Notes 1–4 of `149:184613`, three rows each.
    static let cafe: [[BoardCell]] = {
        let one = [text("  ROSA'S CAFE  "), text("  OPEN 7 TO 3  "), rainbow]
        let two = [text("  SOUP OF DAY  "), text("   TORTILLA    "), text("    $6 CUP     ")]
        let three = [text("   HORCHATA    "), text("   COLD BREW   "), text("    $4 EACH    ")]
        let four = [text("   FREE WIFI   "), text(" NET ROSAGUEST "), text("  \(heart) GRACIAS \(heart)  ")]
        return (0..<3).map { one[$0] + two[$0] } + (0..<3).map { three[$0] + four[$0] }
    }()

    /// A5's Notes in screen points (board instance at y 205).
    static let figmaNotes: [(id: String, frame: CGRect)] = [
        ("I166:193912;149:182603;166:194992;149:184615", CGRect(x: 0, y: 205, width: 930.64, height: 305.32)),
        ("I166:193912;149:182603;166:194992;149:184859", CGRect(x: 989.36, y: 205, width: 930.64, height: 305.32)),
        ("I166:193912;149:182603;166:194992;149:185134", CGRect(x: 0, y: 569.04, width: 930.64, height: 305.32)),
        ("I166:193912;149:182603;166:194992;149:185408", CGRect(x: 989.36, y: 569.04, width: 930.64, height: 305.32)),
    ]

    // MARK: Harness

    private struct Shot {
        let image: UIImage
        let layout: BoardLayout
        /// The board's top-left on screen, in points.
        let origin: CGPoint

        func screen(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: origin.x, dy: origin.y) }

        func pixel(_ x: Double, _ y: Double, file: StaticString = #filePath,
                   line: UInt = #line) throws -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            try XCTUnwrap(image.pixel(x: Int((x * TVSnapshot.scale).rounded(.down)),
                                      y: Int((y * TVSnapshot.scale).rounded(.down))),
                          "(\(x), \(y)) is on screen", file: file, line: line)
        }
    }

    private func viewer(case name: String, cells: [[BoardCell]], boardColor: String? = nil) throws -> Shot {
        var body = try XCTUnwrap(NoteArrayTests.cases()[name]?["body"] as? [String: Any])
        if let boardColor { body["board_color"] = boardColor }
        let panel = try NoteArrayTests.panel(body)
        let rows = try XCTUnwrap(panel.rows), cols = try XCTUnwrap(panel.cols)
        let app = AppModel(connection: ConnectionStore(defaults: UserDefaults(suiteName: "a10.\(UUID().uuidString)")!,
                                                       credentials: InMemoryCredentialStore()))
        let model = ViewerModel(app: app, ref: panel.id,
                                signage: SignageSettings(defaults: UserDefaults(suiteName: "a10.\(UUID().uuidString)")!))
        model.apply(PanelSnapshot(panel: panel, cells: cells, rows: rows, cols: cols,
                                  connection: .live, dimmed: false, deleted: false))
        let layout = try model.layout(for: TVSnapshot.size)
        let image = TVSnapshot.image(ViewerScreen(ref: panel.id, model: model).environment(app),
                                     settle: 0.3, fullBleed: true)
        let origin = CGPoint(x: (TVSnapshot.size.width - layout.width) / 2,
                             y: (TVSnapshot.size.height - layout.height) / 2)
        return Shot(image: image, layout: layout, origin: origin)
    }

    private func assertColor(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8), _ hex: UInt32, tolerance: Int = 3,
                             _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let want = [Int(hex >> 16 & 255), Int(hex >> 8 & 255), Int(hex & 255)]
        let got = [Int(p.r), Int(p.g), Int(p.b)]
        XCTAssertTrue(zip(want, got).allSatisfy { abs($0 - $1) <= tolerance },
                      "\(message): \(got) vs #\(String(hex, radix: 16))", file: file, line: line)
    }

    /// Stops a test (rather than the runner) when the bezels are missing.
    private func require(_ layout: BoardLayout, notes count: Int,
                         file: StaticString = #filePath, line: UInt = #line) throws {
        guard layout.notes.count == count else {
            XCTFail("\(layout.notes.count) bezels, expected \(count)", file: file, line: line)
            throw XCTSkip("no bezels to probe")
        }
    }

    private static let bezelFill: UInt32 = 0x050505
    private static let bezelBorder: UInt32 = 0x1A1A1A

    // MARK: The 2×2 (A5 166:193912)

    func testTheTwoByTwoIsFourNotesAsA5DrawsThem() throws {
        let shot = try viewer(case: "note-array-2x2", cells: Self.cafe)
        let layout = shot.layout
        try require(layout, notes: 4)
        XCTAssertEqual(layout.tiles.count, 180)

        // Structural probe: each Note's frame against A5's, ±5 % (N18-4).
        for (note, figma) in zip(layout.notes, Self.figmaNotes) {
            let frame = shot.screen(note.rect)
            XCTAssertEqual(frame.minX, figma.frame.minX, accuracy: figma.frame.width * 0.05, "\(figma.id) x")
            XCTAssertEqual(frame.minY, figma.frame.minY, accuracy: figma.frame.height * 0.05, "\(figma.id) y")
            XCTAssertEqual(frame.width, figma.frame.width, accuracy: figma.frame.width * 0.05, "\(figma.id) width")
            XCTAssertEqual(frame.height, figma.frame.height, accuracy: figma.frame.height * 0.05, "\(figma.id) height")
        }
        XCTAssertEqual(layout.width, 1920, accuracy: 0.5, "full-bleed at 1920 (DD24)")

        // The bezel: border, then fill, then the first tile (07b 4 / 24 / tile).
        let first = shot.screen(layout.notes[0].rect)
        let midY = first.midY
        assertColor(try shot.pixel(first.minX + layout.bezelBorder / 2, midY), Self.bezelBorder, "Note 1's border")
        assertColor(try shot.pixel(first.minX + layout.bezelBorder + 4, midY), Self.bezelFill, "Note 1's bezel fill")
        let second = shot.screen(layout.notes[1].rect)
        assertColor(try shot.pixel(second.minX + layout.bezelBorder / 2, midY), Self.bezelBorder, "Note 2's border")
        assertColor(try shot.pixel(second.maxX - layout.bezelBorder / 2, midY), Self.bezelBorder, "Note 2's right border")
        // OLED black between Notes: no surround across the gap.
        assertColor(try shot.pixel((first.maxX + second.minX) / 2, midY), 0x000000, tolerance: 0, "the gap between Notes")
        let third = shot.screen(layout.notes[2].rect)
        assertColor(try shot.pixel(first.midX, (first.maxY + third.minY) / 2), 0x000000, tolerance: 0, "the gap between rows")
        // Above and below the array is the viewer's black.
        assertColor(try shot.pixel(960, first.minY - 4), 0x000000, tolerance: 0, "above the array")

        // Tiles sample their colours at their centres (below the split).
        for (col, hex) in [(0, 0xEB4034), (3, 0x7ED321)] as [(Int, UInt32)] {
            let tile = layout.tiles[2 * 30 + col]
            let rect = shot.screen(CGRect(x: tile.x, y: tile.y, width: tile.width, height: tile.height))
            assertColor(try shot.pixel(rect.midX, rect.minY + rect.height * 0.75), hex, tolerance: 12,
                        "Note 1 row 3 col \(col)")
        }
        // The hearts are white glyphs (Note hardware), on Note 4's last row.
        XCTAssertEqual(Self.cafe[5][17], .character(Self.heart))

        TVSnapshot.assertMatches(shot.image, named: "viewer-note-array")
    }

    // MARK: Partial Notes (DD5)

    /// 34 × 7 = 238 cells in 9 Notes: the right column and bottom row of
    /// Notes are cut open, and every cell is drawn.
    func testAPartialArrayIsCutOpenAndEveryCellIsDrawn() throws {
        let rows = 7, cols = 34
        let cells: [[BoardCell]] = (0..<rows).map { row in
            (0..<cols).map { col in
                row == rows - 1 || col == cols - 1 ? .color(.green)
                    : (row + col).isMultiple(of: 2) ? .color(.blue) : .color(.violet)
            }
        }
        let shot = try viewer(case: "partial-note", cells: cells)
        let layout = shot.layout
        XCTAssertEqual(layout.tiles.count, 238)
        try require(layout, notes: 9)

        // Every one of the 238 cells is painted, at its centre (below the split).
        for tile in layout.tiles {
            let rect = shot.screen(CGRect(x: tile.x, y: tile.y, width: tile.width, height: tile.height))
            let p = try shot.pixel(rect.midX, rect.minY + rect.height * 0.75)
            let hex: UInt32 = tile.row == rows - 1 || tile.col == cols - 1 ? 0x7ED321
                : (tile.row + tile.col).isMultiple(of: 2) ? 0x4A90D9 : 0x9B59B6
            assertColor(p, hex, tolerance: 16, "cell \(tile.row),\(tile.col)")
        }

        // The bottom-left Note is open at the bottom: fill, not border, at its
        // cut, and black below it. Its left side keeps its border.
        let bottom = shot.screen(layout.notes[6].rect)
        assertColor(try shot.pixel(bottom.midX, bottom.maxY - 1), Self.bezelFill, "no border on the open bottom")
        assertColor(try shot.pixel(bottom.midX, bottom.maxY + 2), 0x000000, tolerance: 0, "black past the cut")
        assertColor(try shot.pixel(bottom.minX + layout.bezelBorder / 2, bottom.minY + 30), Self.bezelBorder,
                    "the closed side keeps its border")
        // No corner on the open side: the bezel fills right to the cut's corner.
        assertColor(try shot.pixel(bottom.minX + layout.bezelBorder + 1, bottom.maxY - 1), Self.bezelFill,
                    "the open edge has no rounded corner")

        TVSnapshot.assertMatches(shot.image, named: "viewer-note-array-partial")
    }

    /// androidtv #28 N28-2: an open right edge that is on screen. 9 × 20 is
    /// height-bound, so the cut lands inside the TV.
    func testAnOpenRightEdgeOnScreen() throws {
        var body = try XCTUnwrap(NoteArrayTests.cases()["partial-note"]?["body"] as? [String: Any])
        body["rows"] = 9
        body["cols"] = 20
        body["notes_wide"] = 1
        body["notes_tall"] = 3
        let panel = try NoteArrayTests.panel(body)
        let layout = try BoardLayout.fitting(rows: 9, cols: 20, cells: [], in: TVSnapshot.size, mode: .fit,
                                             diagonalInches: 55, calibration: 1,
                                             colPitchIn: BoardGeometry.colPitchIn, noteArray: panel.isNoteArray)
        XCTAssertEqual(layout.height, 1080, accuracy: 0.5, "height-bound")
        XCTAssertLessThan(layout.width, 1900)
        let image = TVSnapshot.image(ZStack {
            Color.black
            BoardCanvas(layout: layout, background: .black, code62: panel.effectiveCode62)
                .frame(width: layout.width, height: layout.height)
        }, fullBleed: true)
        try require(layout, notes: 2)
        let shot = Shot(image: image, layout: layout,
                        origin: CGPoint(x: (1920 - layout.width) / 2, y: (1080 - layout.height) / 2))
        let partial = shot.screen(layout.notes[1].rect)
        XCTAssertTrue(layout.notes[1].openRight)
        assertColor(try shot.pixel(partial.maxX - 1, partial.midY), Self.bezelFill, "no border on the open right")
        assertColor(try shot.pixel(partial.maxX + 2, partial.midY), 0x000000, tolerance: 0, "black past the cut")
        let whole = shot.screen(layout.notes[0].rect)
        assertColor(try shot.pixel(whole.maxX - layout.bezelBorder / 2, whole.midY), Self.bezelBorder,
                    "a whole Note's right side keeps its border")
    }

    /// A white board takes FiestaUI's light bezel pair.
    func testAWhiteBoardTakesTheLightBezel() throws {
        let shot = try viewer(case: "note-array-2x2", cells: Self.cafe, boardColor: "white")
        try require(shot.layout, notes: 4)
        let first = shot.screen(shot.layout.notes[0].rect)
        assertColor(try shot.pixel(first.minX + shot.layout.bezelBorder / 2, first.midY), 0xD8D8D8, "light border")
        assertColor(try shot.pixel(first.minX + shot.layout.bezelBorder + 4, first.midY), 0xF8F8F8, "light fill")
        let second = shot.screen(shot.layout.notes[1].rect)
        assertColor(try shot.pixel((first.maxX + second.minX) / 2, first.midY), 0x000000, tolerance: 0,
                    "the gap stays OLED black")
    }

    /// The old-hub fallback (no counts) and a flagship stay one merged grid
    /// through the viewer.
    func testOldHubsAndOtherBoardsStayMerged() throws {
        let cells = (0..<6).map { _ in (0..<30).map { _ in BoardCell.color(.red) } }
        let shot = try viewer(case: "old-server", cells: cells)
        XCTAssertTrue(shot.layout.notes.isEmpty)
        let merged = try BoardLayout.fitting(rows: 6, cols: 30, cells: cells, in: TVSnapshot.size, mode: .fit,
                                             diagonalInches: 55, calibration: 1, colPitchIn: BoardGeometry.colPitchIn)
        XCTAssertEqual(shot.layout.tiles, merged.tiles)
        XCTAssertTrue(try viewer(case: "non-array", cells: []).layout.notes.isEmpty)
    }
}
