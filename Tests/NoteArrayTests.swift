import CryptoKit
import XCTest
@testable import FiestaBoardTV

/// A10 (PHASE-4-TV-PLAN §2.2; DESIGN-DELTAS DD5): a note-array panel draws
/// as separate Notes. The shared fixture is androidtv G9's
/// `panel-notes-v1.json`, vendored byte for byte; the metrics are 07b
/// `TV Board / Lobby wall · Note array 2×2` `149:184613`'s, as fractions of
/// the tile height (h = 46 there): tiles 28 in from the bezel edge (24 padding
/// plus a 4 border), corner radius 18, Notes 40 apart.
final class NoteArrayTests: XCTestCase {

    static let fixtures = TVSnapshot.repoRoot.appendingPathComponent("Tests/Fixtures")

    static func cases() throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: fixtures.appendingPathComponent("panel-notes-v1.json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(root["cases"] as? [String: [String: Any]])
    }

    static func panel(_ body: [String: Any]) throws -> Panel {
        try JSONDecoder().decode(Panel.self, from: JSONSerialization.data(withJSONObject: body))
    }

    static func panel(case name: String) throws -> Panel {
        try panel(XCTUnwrap(cases()[name]?["body"] as? [String: Any], name))
    }

    private static func body(notesWide: Any?, notesTall: Any?) -> [String: Any] {
        var body: [String: Any] = ["id": "w", "name": "Wall", "board_id": "b", "device_type": "note_array",
                                   "rows": 6, "cols": 30]
        body["notes_wide"] = notesWide ?? NSNull()
        body["notes_tall"] = notesTall ?? NSNull()
        return body
    }

    // MARK: The fixture

    func testTheFixtureIsAndroidsByteForByte() throws {
        let data = try Data(contentsOf: Self.fixtures.appendingPathComponent("SOURCE.json"))
        let source = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entry = try XCTUnwrap(source["panel-notes-v1.json"] as? [String: Any])
        XCTAssertEqual(entry["repo"] as? String, "Fiestaboard/fiestaboard-androidtv")
        XCTAssertEqual(entry["path"] as? String, "core/src/test/resources/panel-notes-v1.json")
        XCTAssertEqual((entry["commit"] as? String)?.count, 40)
        let fixture = try Data(contentsOf: Self.fixtures.appendingPathComponent("panel-notes-v1.json"))
        let hash = SHA256.hash(data: fixture).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hash, entry["sha256"] as? String)
        XCTAssertEqual(Set(try Self.cases().keys), ["note-array-2x2", "non-array", "old-server", "partial-note"])
    }

    // MARK: Decoding

    /// Every case reads as the fixture's `expect` says: whether it splits,
    /// its counts, its Note spans, and that every cell is drawn.
    func testEveryFixtureCaseDecodesAndLaysOutAsExpected() throws {
        for (name, value) in try Self.cases() {
            let body = try XCTUnwrap(value["body"] as? [String: Any])
            let expect = try XCTUnwrap(value["expect"] as? [String: Any])
            let panel = try Self.panel(body)
            XCTAssertEqual(panel.isNoteArray, expect["note_array"] as? Bool, name)
            XCTAssertEqual(panel.notesWide, expect["notes_wide"] as? Int, name)
            XCTAssertEqual(panel.notesTall, expect["notes_tall"] as? Int, name)
            let rows = try XCTUnwrap(panel.rows), cols = try XCTUnwrap(panel.cols)
            let layout = BoardLayout.make(rows: rows, cols: cols, cells: [], tileHeight: 46,
                                          noteArray: panel.isNoteArray)
            XCTAssertEqual(layout.tiles.count, expect["cells"] as? Int, "\(name): every cell is drawn")
            if let noteCols = expect["note_cols"] as? [Int], let noteRows = expect["note_rows"] as? [Int] {
                XCTAssertEqual(NoteArray.spans(cols, per: NoteArray.cols), noteCols, name)
                XCTAssertEqual(NoteArray.spans(rows, per: NoteArray.rows), noteRows, name)
                XCTAssertEqual(layout.notes.count, noteCols.count * noteRows.count, "\(name): one bezel per Note")
            } else {
                XCTAssertTrue(layout.notes.isEmpty, "\(name): one merged grid")
            }
        }
    }

    /// The counts are a flag the viewer polls every ten seconds: a value it
    /// can't use is dropped, never a reason to lose the panel.
    func testMalformedNoteCountsAreIgnoredAndNeverThrow() throws {
        for bad: Any in [-1, "two", 2.5, 257, true] {
            let panel = try Self.panel(Self.body(notesWide: bad, notesTall: 2))
            XCTAssertNil(panel.notesWide, "\(bad)")
            XCTAssertFalse(panel.isNoteArray, "\(bad)")
        }
        XCTAssertEqual(try Self.panel(Self.body(notesWide: 0, notesTall: 2)).notesWide, 0,
                       "a board narrower than a Note is 0 wide, and still a note array")
        var flagship = Self.body(notesWide: 2, notesTall: 2)
        flagship["device_type"] = "flagship"
        XCTAssertFalse(try Self.panel(flagship).isNoteArray, "only a note_array board splits")
        var removed = Self.body(notesWide: 2, notesTall: 2)
        removed["device_type"] = NSNull()
        XCTAssertFalse(try Self.panel(removed).isNoteArray, "a removed board stays merged")
    }

    /// Panels are cached by encoding them; the counts survive the trip.
    func testTheCountsSurviveEncoding() throws {
        let panel = try Self.panel(case: "partial-note")
        let again = try JSONDecoder().decode(Panel.self, from: JSONEncoder().encode(panel))
        XCTAssertEqual(again, panel)
        XCTAssertEqual(again.notesWide, 2)
        XCTAssertTrue(again.isNoteArray)
    }

    // MARK: Spans

    func testSpansAreWholeNotesThenTheTrailingPartial() {
        XCTAssertEqual(NoteArray.spans(34, per: 15), [15, 15, 4])
        XCTAssertEqual(NoteArray.spans(30, per: 15), [15, 15])
        XCTAssertEqual(NoteArray.spans(7, per: 3), [3, 3, 1])
        XCTAssertEqual(NoteArray.spans(10, per: 15), [10])
        XCTAssertEqual(NoteArray.spans(0, per: 15), [])
    }

    // MARK: Seams (07b 149:184613)

    /// At 07b's tile height (46): tiles 28 in, the in-Note pitch is the merged
    /// grid's, and a seam is padding + gap + padding between two tiles.
    func testTheSeamsMatch07b() throws {
        let h = 46.0
        let layout = BoardLayout.make(rows: 6, cols: 30, cells: [], tileHeight: h, noteArray: true)
        func tile(_ row: Int, _ col: Int) -> TileRect { layout.tiles[row * 30 + col] }
        let tileWidth = h * BoardGeometry.tileWidthRatio, gutter = h * BoardGeometry.tileGutterRatio
        XCTAssertEqual(tile(0, 0).x, 28, accuracy: 1e-9)
        XCTAssertEqual(tile(0, 0).y, 28, accuracy: 1e-9)
        XCTAssertEqual(tile(0, 1).x - tile(0, 0).x, tileWidth + gutter, accuracy: 1e-9, "in-Note column pitch")
        XCTAssertEqual(tile(1, 0).y - tile(0, 0).y, h + gutter, accuracy: 1e-9, "in-Note row pitch")
        XCTAssertEqual(tile(0, 15).x - (tile(0, 14).x + tileWidth), 28 + 40 + 28, accuracy: 1e-9, "column seam")
        XCTAssertEqual(tile(3, 0).y - (tile(2, 0).y + h), 28 + 40 + 28, accuracy: 1e-9, "row seam")
        XCTAssertEqual(tile(0, 16).x - tile(0, 15).x, tileWidth + gutter, accuracy: 1e-9)

        XCTAssertEqual(layout.notes.count, 4)
        guard layout.notes.count == 4 else { return }
        let first = layout.notes[0].rect, second = layout.notes[1].rect, third = layout.notes[2].rect
        XCTAssertEqual(first.minX, 0, accuracy: 1e-9)
        XCTAssertEqual(first.minY, 0, accuracy: 1e-9)
        // 07b draws its tiles on whole pixels (32 / 46 wide, a 7 / 46 gutter),
        // so its Note is 634 × 208; the canonical ratios give 632.4 × 207.3.
        XCTAssertEqual(first.width, 634, accuracy: 634 * 0.005, "Note width vs 07b")
        XCTAssertEqual(first.height, 208, accuracy: 208 * 0.005, "Note height vs 07b")
        XCTAssertEqual(first.maxX - (tile(0, 14).x + tileWidth), 28, accuracy: 1e-9, "a whole Note closes 28 past its last tile")
        XCTAssertEqual(second.minX - first.maxX, 40, accuracy: 1e-9, "Notes are 40 apart")
        XCTAssertEqual(third.minY - first.maxY, 40, accuracy: 1e-9)
        XCTAssertEqual(layout.width, second.maxX, accuracy: 1e-9)
        XCTAssertEqual(layout.height, layout.notes[3].rect.maxY, accuracy: 1e-9)
        XCTAssertEqual(layout.bezelBorder, 4, accuracy: 1e-9)
        XCTAssertEqual(layout.bezelRadius, 18, accuracy: 1e-9)
        XCTAssertFalse(layout.notes.contains { $0.openRight || $0.openBottom }, "whole Notes are closed")
        let size = BoardLayout.size(rows: 6, cols: 30, tileHeight: h, noteArray: true)
        XCTAssertEqual(size.width, layout.width, accuracy: 1e-9)
        XCTAssertEqual(size.height, layout.height, accuracy: 1e-9)
    }

    /// DD5: a 34 × 7 panel is 238 cells in 9 Notes. The trailing column and
    /// row of Notes are cut open, one in-Note gutter past their last tile.
    func testAPartialNoteIsCutOpenOneGutterPastItsLastTile() throws {
        let h = 46.0, gutter = h * BoardGeometry.tileGutterRatio
        let layout = BoardLayout.make(rows: 7, cols: 34, cells: [], tileHeight: h, noteArray: true)
        XCTAssertEqual(layout.tiles.count, 238)
        XCTAssertEqual(layout.notes.count, 9)
        guard layout.notes.count == 9 else { return }
        for (index, note) in layout.notes.enumerated() {
            XCTAssertEqual(note.openRight, index % 3 == 2, "note \(index)")
            XCTAssertEqual(note.openBottom, index / 3 == 2, "note \(index)")
        }
        let last = try XCTUnwrap(layout.tiles.last)
        let corner = layout.notes[8].rect
        XCTAssertEqual(corner.maxX, last.x + last.width + gutter, accuracy: 1e-9)
        XCTAssertEqual(corner.maxY, last.y + last.height + gutter, accuracy: 1e-9)
        XCTAssertEqual(corner.width, 28 + 4 * (h * 0.70 + gutter), accuracy: 1e-9, "padding, then four cells")
        XCTAssertEqual(layout.width, corner.maxX, accuracy: 1e-9)
        XCTAssertEqual(layout.height, corner.maxY, accuracy: 1e-9)
        // Every tile sits inside exactly one Note, past its padding.
        for tile in layout.tiles {
            let rect = CGRect(x: tile.x, y: tile.y, width: tile.width, height: tile.height)
            let owners = layout.notes.filter { $0.rect.contains(rect) }
            XCTAssertEqual(owners.count, 1, "tile \(tile.row),\(tile.col)")
            if let note = owners.first {
                XCTAssertGreaterThanOrEqual(rect.minX - note.rect.minX, 28 - 1e-9)
                XCTAssertGreaterThanOrEqual(rect.minY - note.rect.minY, 28 - 1e-9)
            }
        }
    }

    /// androidtv #28 N28-1: narrower than one Note (`notes_wide` 0) is one
    /// partial Note, open on the right. Never dropped.
    func testANoteArrayNarrowerThanOneNoteIsOneOpenNote() {
        let layout = BoardLayout.make(rows: 3, cols: 10, cells: [], tileHeight: 46, noteArray: true)
        XCTAssertEqual(layout.tiles.count, 30)
        XCTAssertEqual(layout.notes.map(\.openRight), [true])
        XCTAssertEqual(layout.notes.map(\.openBottom), [false])
    }

    /// The merged grid is untouched: same tiles, no bezels.
    func testAMergedGridIsUnchanged() {
        let merged = BoardLayout.make(rows: 6, cols: 30, cells: [], tileHeight: 46)
        let flag = BoardLayout.make(rows: 6, cols: 30, cells: [], tileHeight: 46, noteArray: false)
        XCTAssertEqual(merged.tiles, flag.tiles)
        XCTAssertTrue(merged.notes.isEmpty)
        // Whole-point width and gutter (FiestaUI board-metrics, A5): 32 + 7.
        XCTAssertEqual(merged.tiles[15].x, 15 * 39, accuracy: 1e-9, "no seam")
        XCTAssertEqual(merged.width, 30 * 39 - 7, accuracy: 1e-9)
    }

    // MARK: Sizing

    /// Fit sizes the whole array, full-bleed at 1920 (DD24), centred: A5
    /// `166:193912` redrawn draws it 1920 × 669.36 with h = 67.52.
    func testFitSizesTheWholeArrayFullBleed() throws {
        let layout = try BoardLayout.fitting(rows: 6, cols: 30, cells: [], in: CGSize(width: 1920, height: 1080),
                                             mode: .fit, diagonalInches: 55, calibration: 1,
                                             colPitchIn: BoardGeometry.colPitchIn, noteArray: true)
        XCTAssertEqual(layout.width, 1920, accuracy: 1e-6)
        XCTAssertEqual(layout.height, 669.36, accuracy: 669.36 * 0.05, "board height within ±5 % (N18-4)")
        XCTAssertEqual(layout.tileHeight, 67.52, accuracy: 67.52 * 0.01)
        XCTAssertEqual(layout.notes.count, 4)
        let trueScale = try BoardLayout.fitting(rows: 6, cols: 30, cells: [], in: CGSize(width: 1920, height: 1080),
                                                mode: .trueScale, diagonalInches: 55, calibration: 1,
                                                colPitchIn: BoardGeometry.colPitchIn, noteArray: true)
        XCTAssertEqual(trueScale.notes.count, 4)
        XCTAssertLessThanOrEqual(trueScale.width, 1920 + 1e-6, "true scale never overflows a 55-inch TV for two Notes")
    }
}
