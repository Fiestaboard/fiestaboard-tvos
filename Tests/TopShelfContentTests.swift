import TVServices
import XCTest
@testable import FiestaBoardTV

final class TopShelfContentTests: XCTestCase {
    func testAvailablePanelsBecomeSelectableCards() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TopShelfSnapshotStore(directory: directory)
        try store.replace([
            .init(panelID: "kitchen", name: "Kitchen", imageData: Data([1])),
            .init(panelID: "bedroom", name: "Bedroom", imageData: Data([2]))
        ])

        let content = try XCTUnwrap(TopShelfContent.make(store: store) as? TVTopShelfSectionedContent,
                                   "Available panels must appear as a row of cards, not a full-screen poster carousel")
        let section = try XCTUnwrap(content.sections.first)
        XCTAssertEqual(content.sections.count, 1)
        XCTAssertEqual(section.items.map(\.identifier), ["kitchen", "bedroom"])
        XCTAssertEqual(section.items.map(\.title), ["Kitchen", "Bedroom"])
        for item in section.items {
            XCTAssertEqual(item.imageShape, .hdtv)
            let expected = URL(string: "fiestaboard://panel/\(item.identifier)")!
            XCTAssertEqual(item.displayAction?.url, expected, "Select should open the focused panel")
            XCTAssertEqual(item.playAction?.url, expected, "Play should open the same panel")
            XCTAssertNotNil(item.imageURL(for: [.screenScale1x, .screenScale2x]))
        }
    }

    func testPurgedImagesDoNotProduceDeadCards() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TopShelfSnapshotStore(directory: directory)
        XCTAssertNil(TopShelfContent.make(store: store))
        try store.replace([.init(panelID: "one", name: "Kitchen", imageData: Data([1]))])
        let item = try XCTUnwrap(store.items().first)
        try FileManager.default.removeItem(at: store.imageURL(for: item))
        XCTAssertNil(TopShelfContent.make(store: store))
    }
}
