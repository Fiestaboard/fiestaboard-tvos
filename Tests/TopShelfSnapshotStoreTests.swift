import Foundation
import XCTest
@testable import FiestaBoardTV

final class TopShelfSnapshotStoreTests: XCTestCase {

    private func makeStore() -> (TopShelfSnapshotStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("topshelf-test-\(UUID().uuidString)")
        return (TopShelfSnapshotStore(directory: directory), directory)
    }

    func testReplacingPreviewsPublishesOnlyTheCurrentPanelImages() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

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
        XCTAssertEqual(try Data(contentsOf: store.imageURL(for: current[0])), Data([7, 8]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.imageURL(for: original[0]).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.imageURL(for: original[1]).path),
                       "the superseded image should not be left behind")

        try store.clear()
        XCTAssertTrue(store.items().isEmpty)
    }

    /// Home caches a Top Shelf image against its URL, so new artwork has to
    /// arrive at a URL Home has not already cached — otherwise it keeps
    /// showing the old picture.
    func testNewArtworkForTheSamePanelGetsANewURL() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try store.replace([.init(panelID: "one", name: "Kitchen", imageData: Data([1, 2, 3]))])
        let before = try XCTUnwrap(store.items().first)

        try store.replace([.init(panelID: "one", name: "Kitchen", imageData: Data([9, 9, 9]))])
        let after = try XCTUnwrap(store.items().first)

        XCTAssertNotEqual(after.imageFile, before.imageFile)
        XCTAssertEqual(try Data(contentsOf: store.imageURL(for: after)), Data([9, 9, 9]))
    }

    /// The other half of the same rule: republishing what Home already has
    /// must not move the URL, or Home restarts a load it is partway through.
    func testUnchangedArtworkKeepsItsURL() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try store.replace([.init(panelID: "one", name: "Kitchen", imageData: Data([1, 2, 3]))])
        let before = try XCTUnwrap(store.items().first)

        try store.replace([.init(panelID: "one", name: "Kitchen Renamed", imageData: Data([1, 2, 3]))])
        let after = try XCTUnwrap(store.items().first)

        XCTAssertEqual(after.imageFile, before.imageFile)
        XCTAssertEqual(after.name, "Kitchen Renamed")
    }

    /// Every panel shares one brand poster, so it is stored once.
    func testPanelsSharingArtworkShareOneFile() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let poster = Data([4, 2])
        try store.replace([
            .init(panelID: "one", name: "Kitchen", imageData: poster),
            .init(panelID: "two", name: "Office", imageData: poster),
            .init(panelID: "three", name: "Hall", imageData: poster)
        ])

        let items = store.items()
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(Set(items.map(\.imageFile)).count, 1)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files.filter { $0.hasSuffix(".png") }.count, 1)
    }
}
