import Foundation
import CryptoKit

/// Board previews shared with the Top Shelf extension. No address, session,
/// or credential is written here; the extension only reads local images.
public struct TopShelfSnapshotStore {
    public static let groupIdentifier = "group.com.fiestaboard.tv"

    public struct Preview {
        public let panelID: String
        public let name: String
        public let imageData: Data

        public init(panelID: String, name: String, imageData: Data) {
            self.panelID = panelID
            self.name = name
            self.imageData = imageData
        }
    }

    public struct Item: Codable, Equatable {
        public let panelID: String
        public let name: String
        public let imageFile: String
    }

    public let directory: URL
    private var manifestURL: URL { directory.appendingPathComponent("manifest.json") }

    /// The group container's ROOT is not writable on tvOS. Only
    /// `Library/Caches` inside it is, and these three components are the
    /// difference between a working carousel and no carousel at all.
    ///
    /// Without them `replace()`'s `createDirectory` threw on every real Apple
    /// TV, the manifest was never written, `items()` came back empty, and the
    /// extension handed Home nothing — which Home answers with the static
    /// poster from the asset catalogue, a picture pixel-identical to the one
    /// a working carousel item would show. So the feature looked plausible
    /// and had never once run. The simulator does not enforce the
    /// restriction, which is why the tests stayed green throughout.
    ///
    /// Do not "tidy" this path back to the container root. The cost of
    /// `Library/Caches` is that tvOS may purge it whenever it likes, which is
    /// why the app republishes on every foreground rather than trusting what
    /// it wrote last week to still be there.
    public static func shared() -> TopShelfSnapshotStore? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier) else { return nil }
        let directory = container
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("TopShelf", isDirectory: true)
        return TopShelfSnapshotStore(directory: directory)
    }

    public init(directory: URL) { self.directory = directory }

    public func items() -> [Item] {
        guard let data = try? Data(contentsOf: manifestURL) else { return [] }
        return (try? JSONDecoder().decode([Item].self, from: data)) ?? []
    }

    public func imageURL(for item: Item) -> URL {
        directory.appendingPathComponent(item.imageFile)
    }

    /// Files are named for their CONTENTS, not for the panel they belong to.
    ///
    /// Home caches a Top Shelf image against its URL. Naming the file after
    /// the panel meant new artwork arrived at a URL Home had already cached,
    /// so it kept showing the old picture. Hashing the bytes gives identical
    /// artwork a stable URL — which is what stops Home restarting a load it
    /// is halfway through — while changed artwork gets a URL Home has never
    /// seen and must fetch. It also means one poster shared by every panel
    /// is written once rather than once per panel.
    /// Returns whether Home needs to reload: changed metadata or restored files.
    @discardableResult
    public func replace(_ previews: [Preview]) throws -> Bool {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let previousManifest = (try? Data(contentsOf: manifestURL)).flatMap {
            try? JSONDecoder().decode([Item].self, from: $0)
        }
        let previous = previousManifest ?? []
        var current: [Item] = []
        var changed = false
        for preview in previews {
            let digest = SHA256.hash(data: preview.imageData)
                .map { String(format: "%02x", $0) }.joined()
            let filename = "preview-\(digest).png"
            let url = directory.appendingPathComponent(filename)
            if !FileManager.default.fileExists(atPath: url.path) {
                try preview.imageData.write(to: url, options: .atomic)
                changed = true
            }
            current.append(Item(panelID: preview.panelID, name: preview.name, imageFile: filename))
        }
        if current != previousManifest {
            try JSONEncoder().encode(current).write(to: manifestURL, options: .atomic)
            changed = true
        }
        let currentFiles = Set(current.map(\.imageFile))
        for item in previous where !currentFiles.contains(item.imageFile) {
            try? FileManager.default.removeItem(at: imageURL(for: item))
        }
        return changed
    }

    public func clear() throws { try replace([]) }
}
