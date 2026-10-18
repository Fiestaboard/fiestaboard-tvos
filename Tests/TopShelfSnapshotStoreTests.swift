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
        // An empty manifest is not an empty store. This lives in the group
        // container's `Library/Caches`, which tvOS purges on its own terms
        // and which the app has no other way to tidy — so a clear that only
        // rewrote the manifest would leave every poster it ever published
        // behind, and `items().isEmpty` would say nothing about it.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".png") }
        XCTAssertEqual(leftovers, [])
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

    /// The bug that cost the feature its entire life.
    ///
    /// `shared()` used to hand back the ROOT of the app-group container,
    /// which tvOS lets neither the app nor the extension write to: every
    /// `replace()` threw on real hardware, `items()` stayed empty, and Home
    /// fell back to a static poster that looks exactly like a working
    /// carousel item. The simulator does not enforce the restriction, so the
    /// other tests in this file — which all run against a temp directory —
    /// could never have caught it.
    ///
    /// This one deliberately uses the real container. The unit target is
    /// hosted by the app, so it runs under the app's entitlements and the
    /// group resolves for real.
    func testTheSharedStoreResolvesAWritableContainer() throws {
        let store = try XCTUnwrap(TopShelfSnapshotStore.shared(),
                                  "the app-group entitlement should resolve a container")
        defer { try? store.clear() }

        XCTAssertEqual(Array(store.directory.pathComponents.suffix(3)),
                       ["Library", "Caches", "TopShelf"],
                       "only Library/Caches inside the group container is writable on tvOS")

        try store.replace([.init(panelID: "one", name: "Kitchen", imageData: Data([1, 2, 3]))])
        let item = try XCTUnwrap(store.items().first,
                                 "a round trip through the real container must work")
        XCTAssertEqual(item.panelID, "one")
        XCTAssertEqual(try Data(contentsOf: store.imageURL(for: item)), Data([1, 2, 3]))
    }
}
