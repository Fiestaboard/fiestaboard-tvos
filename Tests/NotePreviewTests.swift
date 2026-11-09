import SwiftUI
import XCTest
@testable import FiestaBoardTV

/// A10 follow-up in A5: the card, Settings and Top Shelf previews draw a
/// note-array panel as separate Notes (A10's `noteArray:` layout), and
/// every cache of a picture re-renders when a panel becomes, or stops
/// being, a note array.
@MainActor
final class NotePreviewTests: XCTestCase {

    /// 07b A5 `166:193912`'s Lobby wall: 2 × 2 Notes, 6 × 30 cells.
    private func notePanel() throws -> Panel { try NoteArrayTests.panel(case: "note-array-2x2") }

    /// The same panel, as a merged grid: same id, no Notes.
    private func mergedPanel() throws -> Panel {
        var body = try XCTUnwrap(NoteArrayTests.cases()["note-array-2x2"]?["body"] as? [String: Any])
        body["device_type"] = "flagship"
        body["notes_wide"] = NSNull()
        body["notes_tall"] = NSNull()
        return try NoteArrayTests.panel(body)
    }

    private func preview() -> PanelPreview {
        var grid = Array(repeating: Array(repeating: 0, count: 30), count: 6)
        for (index, letter) in "LOBBY WALL".utf8.enumerated() {
            grid[1][3 + index] = (65...90).contains(letter) ? Int(letter) - 64 : 0
        }
        for col in 0..<30 { grid[4][col] = 63 + col % 6 }
        return PanelPreview(rows: 6, cols: 30, cells: BoardTables.cells(from: grid, code62: .heart),
                            message: "LOBBY WALL")
    }

    // MARK: Layouts

    func testTheCardPreviewDrawsSeparateNotes() throws {
        let layout = try XCTUnwrap(PanelPreviewBoard.layout(panel: notePanel(), preview: preview(),
                                                            in: CGSize(width: 768, height: 442)))
        XCTAssertEqual(layout.notes.count, 4, "2 × 2 Notes")
        XCTAssertEqual(layout.tiles.count, 180, "every cell is drawn")
        XCTAssertTrue(try XCTUnwrap(PanelPreviewBoard.layout(panel: mergedPanel(), preview: preview(),
                                                             in: CGSize(width: 768, height: 442))).notes.isEmpty)
    }

    func testTheSettingsPreviewDrawsSeparateNotes() throws {
        for calibration in [nil, 1.0] as [Double?] {
            let layout = try XCTUnwrap(SettingsPanelPreview.layout(panel: notePanel(), preview: preview(),
                                                                   in: CGSize(width: 960, height: 540),
                                                                   calibrationScale: calibration))
            XCTAssertEqual(layout.notes.count, 4, "calibration \(String(describing: calibration))")
        }
    }

    // MARK: Goldens (no 07b frame draws a note-array card, Settings or Top Shelf preview; A5 `166:193912` is the viewer's)

    func testTheCardPreviewGolden() throws {
        let card = PanelCard(panel: try notePanel(), preview: .ready(preview()), action: {})
        let image = TVSnapshot.image(ZStack { Fiesta.Colors.background; card }, fullBleed: true)
        TVSnapshot.assertMatches(image, named: "card-note-array")
    }

    func testTheSettingsPreviewGolden() throws {
        let view = SettingsPanelPreview(panel: try notePanel(), state: .ready(preview()))
            .frame(width: 960, height: 540)
        let image = TVSnapshot.image(ZStack { Fiesta.Colors.background; view }, fullBleed: true)
        TVSnapshot.assertMatches(image, named: "settings-note-array")
    }

    func testTheTopShelfHeroGolden() throws {
        let hero = try XCTUnwrap(TopShelfPreviewRenderer.hero(panel: notePanel(), preview: preview()))
        TVSnapshot.assertMatches(UIImage(cgImage: hero.twoX, scale: 2, orientation: .up), named: "top-shelf-note-array")
    }

    // MARK: Caches

    /// A card's cached thumbnail is keyed by the whole panel: becoming a
    /// note array (or not) is a different picture, rendered again.
    func testTheThumbnailCacheRerendersWhenThePanelBecomesANoteArray() throws {
        let cache = PanelPreviewImageCache()
        var renders = 0
        func image(_ panel: Panel) {
            let request = PanelPreviewImageCache.Request(panel: panel, preview: preview(),
                                                         size: CGSize(width: 768, height: 442))
            _ = cache.image(for: request) {
                renders += 1
                return PanelPreviewThumbnail.render(request, environment: EnvironmentValues())
            }
        }
        image(try mergedPanel())
        image(try mergedPanel())
        XCTAssertEqual(renders, 1, "unchanged: the cached picture")
        image(try notePanel())
        XCTAssertEqual(renders, 2, "now a note array: rendered again")
        image(try mergedPanel())
        XCTAssertEqual(renders, 3, "and back")
    }

    /// The Top Shelf image follows too: same panel id, now a note array,
    /// a different picture and so a different file.
    func testTheTopShelfImageRerendersWhenThePanelBecomesANoteArray() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TopShelfSnapshotStore(directory: directory)
        let connection = ConnectionStore(
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await connection.connect(to: URL(string: "http://host:4420")!, displayName: "Board")
        defer { StubURLProtocol.reset() }
        let app = AppModel(connection: connection, topShelfStore: store)

        let merged = try mergedPanel(), note = try notePanel()
        await app.publishTopShelf(panels: [merged], previews: [merged.id: .ready(preview())])?.value
        let first = try XCTUnwrap(store.items().first.map { store.imageURL(for: $0) })
        await app.publishTopShelf(panels: [merged], previews: [merged.id: .ready(preview())])?.value
        XCTAssertEqual(store.items().first.map { store.imageURL(for: $0) }, first, "unchanged: the same file")
        await app.publishTopShelf(panels: [note], previews: [note.id: .ready(preview())])?.value
        let second = try XCTUnwrap(store.items().first.map { store.imageURL(for: $0) })
        XCTAssertNotEqual(second, first, "now a note array: a new picture")
    }
}
