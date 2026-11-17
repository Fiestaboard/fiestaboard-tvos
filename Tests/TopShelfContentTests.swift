import TVServices
import XCTest
@testable import FiestaBoardTV

/// A7 — the Top Shelf carousel (PHASE-4-TV-PLAN §2.2 A7; 07b A9 `166:207117`; DD2).
final class TopShelfContentTests: XCTestCase {
    private var directory: URL!
    private var store: TopShelfSnapshotStore!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = TopShelfSnapshotStore(directory: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func carousel(now: Date? = nil) throws -> TVTopShelfCarouselContent {
        try XCTUnwrap(TopShelfContent.make(store: store, now: now ?? self.now) as? TVTopShelfCarouselContent,
                      "DD2: a carousel with one item per panel, not a sectioned row")
    }

    /// 07b A9: `.actions` with the system Play / More Info; title = panel
    /// name; Play opens the viewer, More Info opens Panels.
    func testEachPanelIsACarouselItemWithSystemActions() throws {
        try store.replace([
            .init(panelID: "living", name: "Living room TV", imageData: Data([1]), imageData2x: Data([2])),
            .init(panelID: "kitchen", name: "Kitchen", imageData: Data([3]), imageData2x: Data([4])),
        ])
        let content = try carousel()
        XCTAssertEqual(content.style, .actions)
        XCTAssertEqual(content.items.map(\.identifier), ["living", "kitchen"])
        XCTAssertEqual(content.items.map(\.title), ["Living room TV", "Kitchen"])
        for item in content.items {
            XCTAssertEqual(item.playAction?.url, URL(string: "fiestaboard://panel/\(item.identifier)"),
                           "Play opens that panel's viewer")
            XCTAssertEqual(item.displayAction?.url, URL(string: "fiestaboard://panels"),
                           "More Info opens Panels")
            XCTAssertNil(item.summary, "DD2: no summary/body line")
        }
    }

    /// HIG: a full-screen carousel image at both scales, distinct files.
    func testBothScalesAreSupplied() throws {
        try store.replace([.init(panelID: "living", name: "Living room TV", imageData: Data([1]), imageData2x: Data([2]))])
        let item = try XCTUnwrap(try carousel().items.first)
        let one = try XCTUnwrap(item.imageURL(for: .screenScale1x))
        let two = try XCTUnwrap(item.imageURL(for: .screenScale2x))
        XCTAssertNotEqual(one, two)
        XCTAssertEqual(try Data(contentsOf: one), Data([1]))
        XCTAssertEqual(try Data(contentsOf: two), Data([2]))
    }

    /// DD2: the status line is the contextTitle, status only, absolute time.
    func testTheStatusLineIsTheContextTitle() throws {
        try store.replace([
            .init(panelID: "a", name: "A", imageData: Data([1]),
                  statusLine: "Now showing · Override · holds until 9:00 PM", statusAt: now),
            .init(panelID: "b", name: "B", imageData: Data([2])),
        ])
        let items = try carousel().items
        XCTAssertEqual(items.map(\.contextTitle), ["Now showing · Override · holds until 9:00 PM", nil])
    }

    /// Home only refreshes on `topShelfContentDidChange`: a line older than
    /// ten minutes is dropped rather than shown as current.
    func testAStaleStatusLineIsDropped() throws {
        try store.replace([.init(panelID: "a", name: "A", imageData: Data([1]),
                                 statusLine: "Paused", statusAt: now)])
        XCTAssertEqual(try carousel(now: now.addingTimeInterval(599)).items.first?.contextTitle, "Paused")
        XCTAssertNil(try carousel(now: now.addingTimeInterval(601)).items.first?.contextTitle)
    }

    /// S3: the manifest the shipping app wrote (no status, no @2x) still
    /// produces items, using the one image for both scales.
    func testTheCurrentOnDiskFormatStillProducesItems() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([9]).write(to: directory.appendingPathComponent("preview-legacy.png"))
        try Data(#"[{"panelID":"old","name":"Old","imageFile":"preview-legacy.png"}]"#.utf8)
            .write(to: directory.appendingPathComponent("manifest.json"))
        let item = try XCTUnwrap(try carousel().items.first)
        XCTAssertEqual(item.title, "Old")
        XCTAssertNil(item.contextTitle)
        XCTAssertEqual(item.imageURL(for: .screenScale1x), item.imageURL(for: .screenScale2x))
    }

    func testPurgedImagesDoNotProduceDeadItems() throws {
        XCTAssertNil(TopShelfContent.make(store: store, now: now))
        try store.replace([.init(panelID: "one", name: "Kitchen", imageData: Data([1]))])
        let item = try XCTUnwrap(store.items().first)
        try FileManager.default.removeItem(at: store.imageURL(for: item))
        XCTAssertNil(TopShelfContent.make(store: store, now: now))
    }
}

/// DD2 / DD22 copy for the carousel's contextTitle.
final class TopShelfStatusLineTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/Los_Angeles")!
    /// 2026-11-08 21:00 in Los Angeles.
    private let ninePM = Date(timeIntervalSince1970: 1_794_200_400)

    private func line(_ status: TopShelfStatus?) -> String? {
        TopShelfStatusLine.make(status, timeZone: zone)
    }

    func testTheCopyTable() {
        XCTAssertEqual(line(.override(until: ninePM)), "Now showing · Override · holds until 9:00 PM")
        XCTAssertEqual(line(.override(until: nil)), "Now showing · Override · holds until canceled")
        XCTAssertEqual(line(.schedule), "Now showing · Schedule")
        XCTAssertEqual(line(.paused), "Paused")
        XCTAssertEqual(line(.silenced(until: ninePM.addingTimeInterval(10 * 3600))), "Silenced · until 7:00 AM")
        XCTAssertEqual(line(.silenced(until: nil)), "Silenced")
        XCTAssertNil(line(.manual), "status only: a manual panel has nothing to say")
        XCTAssertNil(line(nil))
    }

    func testNoCountdownsOnlyAbsoluteTimes() {
        let text = line(.override(until: ninePM)) ?? ""
        XCTAssertFalse(text.contains(" left"), "Top Shelf can't tick: no countdowns (DD2)")
    }
}
