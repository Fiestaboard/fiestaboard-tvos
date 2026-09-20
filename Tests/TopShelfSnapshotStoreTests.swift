import Foundation
import XCTest
@testable import FiestaBoardTV

final class TopShelfSnapshotStoreTests: XCTestCase {
    func testReplacingPreviewsPublishesOnlyTheCurrentPanelImages() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("topshelf-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TopShelfSnapshotStore(directory: directory)

        try store.replace([
            .init(panelID: "one", name: "Kitchen", imageData: Data([1, 2, 3])),
            .init(panelID: "two", name: "Office", imageData: Data([4, 5, 6]))
        ])
        let original = store.items()
        XCTAssertEqual(original.map(\.panelID), ["one", "two"])
        XCTAssertEqual(try Data(contentsOf: store.imageURL(for: original[0])), Data([1, 2, 3]))

        try store.replace([.init(panelID: "two", name: "Office", imageData: Data([7, 8]))])
        let current = store.items()
        XCTAssertEqual(current.map(\.panelID), ["two"])
        XCTAssertEqual(current[0].imageFile, original[1].imageFile,
                       "a stable URL lets Home finish loading an image during refresh")
        XCTAssertEqual(try Data(contentsOf: store.imageURL(for: current[0])), Data([7, 8]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.imageURL(for: original[0]).path))

        try store.clear()
        XCTAssertTrue(store.items().isEmpty)
    }
}
