import XCTest
@testable import FiestaBoardTV

/// The card's spoken summary is worked out once per panel and picture.
/// For an LED-matrix frame with no server message it is a full pixel build,
/// and with every card in the view tree each remote press re-runs every
/// card body: about 100 builds a press at 48 panels before this cache.
@MainActor
final class PanelBoardMessageCacheTests: XCTestCase {
    private func panel(id: String = "one") throws -> Panel {
        let json = Fixtures.panelJSON.replacingOccurrences(of: "\"id\":\"abc123def456\"", with: "\"id\":\"\(id)\"")
        return try JSONDecoder().decode(Panel.self, from: Data(json.utf8))
    }

    private func preview(_ message: String?) -> PanelPreview {
        PanelPreview(rows: 1, cols: 2, cells: [[.character("H"), .character("I")]], message: message)
    }

    func testTheSamePanelAndPictureAreSummarisedOnce() throws {
        let cache = PanelBoardMessageCache()
        let one = try panel()
        var builds = 0
        for _ in 0..<5 {
            XCTAssertEqual(cache.message(for: one, preview: preview("HI")) { builds += 1; return "HI" }, "HI")
        }
        XCTAssertEqual(builds, 1)
    }

    func testANewPictureOrPanelIsSummarisedAgain() throws {
        let cache = PanelBoardMessageCache()
        let one = try panel(), two = try panel(id: "two")
        var builds = 0
        _ = cache.message(for: one, preview: preview("HI")) { builds += 1; return "HI" }
        _ = cache.message(for: one, preview: preview("BYE")) { builds += 1; return "BYE" }
        _ = cache.message(for: two, preview: preview("BYE")) { builds += 1; return "BYE" }
        XCTAssertEqual(builds, 3)
    }

    /// "Nothing to say" is an answer too, and is kept like any other.
    func testANilSummaryIsKept() throws {
        let cache = PanelBoardMessageCache()
        let one = try panel()
        var builds = 0
        for _ in 0..<3 { XCTAssertNil(cache.message(for: one, preview: preview(nil)) { builds += 1; return nil }) }
        XCTAssertEqual(builds, 1)
    }

    /// The card reads the same with and without the cache.
    func testTheCardSaysTheSameThingThroughTheCache() throws {
        let one = try panel()
        let ready = PanelPreviewState.ready(preview("HI THERE"))
        let plain = PanelCard(panel: one, preview: ready, action: {})
        let cached = PanelCard(panel: one, preview: ready, action: {}, boardMessages: PanelBoardMessageCache())
        XCTAssertEqual(cached.subtitle, plain.subtitle)
        XCTAssertEqual(cached.accessibilityLabel, plain.accessibilityLabel)
    }
}
