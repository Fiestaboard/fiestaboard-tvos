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

    private let directory: URL
    private var manifestURL: URL { directory.appendingPathComponent("manifest.json") }

    public static func shared() -> TopShelfSnapshotStore? {
        guard let directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier) else { return nil }
        return TopShelfSnapshotStore(directory: directory.appendingPathComponent("TopShelf"))
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
    public func replace(_ previews: [Preview]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let previous = items()
        var current: [Item] = []
        for preview in previews {
            let digest = SHA256.hash(data: preview.imageData)
                .map { String(format: "%02x", $0) }.joined()
            let filename = "preview-\(digest).png"
            let url = directory.appendingPathComponent(filename)
            if !FileManager.default.fileExists(atPath: url.path) {
                try preview.imageData.write(to: url, options: .atomic)
            }
            current.append(Item(panelID: preview.panelID, name: preview.name, imageFile: filename))
        }
        try JSONEncoder().encode(current).write(to: manifestURL, options: .atomic)
        let currentFiles = Set(current.map(\.imageFile))
        for item in previous where !currentFiles.contains(item.imageFile) {
            try? FileManager.default.removeItem(at: imageURL(for: item))
        }
    }

    public func clear() throws { try replace([]) }
}
