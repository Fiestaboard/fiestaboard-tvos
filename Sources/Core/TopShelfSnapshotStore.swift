import Foundation
import CryptoKit

/// Board previews shared with the Top Shelf extension. No address, session,
/// or credential is written here; the extension only reads local images.
public struct TopShelfSnapshotStore {
    public static let groupIdentifier = "group.com.fiestaboard.tv"

    public struct Preview {
        public let panelID: String
        public let name: String
        /// The carousel hero at @1x (1920×1080).
        public let imageData: Data
        /// The same hero at @2x (3840×2160), A7.
        public let imageData2x: Data?
        /// The carousel's contextTitle (A7, DD2): status only, absolute
        /// times, already formatted. Never a credential or an address.
        public let statusLine: String?
        /// When the app last confirmed `statusLine`.
        public let statusAt: Date?

        public init(panelID: String, name: String, imageData: Data, imageData2x: Data? = nil,
                    statusLine: String? = nil, statusAt: Date? = nil) {
            self.panelID = panelID
            self.name = name
            self.imageData = imageData
            self.imageData2x = imageData2x
            self.statusLine = statusLine
            self.statusAt = statusAt
        }
    }

    /// The manifest entry. Every A7 field is optional, so the manifest the
    /// shipping app wrote (`panelID`, `name`, `imageFile`) still decodes:
    /// no status line, and the one image serves both scales (S3).
    public struct Item: Codable, Equatable {
        public let panelID: String
        public let name: String
        public let imageFile: String
        public var imageFile2x: String? = nil
        public var statusLine: String? = nil
        public var statusAt: Date? = nil

        /// Everything Home shows. A renewed `statusAt` alone is not a change.
        fileprivate var shown: [String?] { [panelID, name, imageFile, imageFile2x, statusLine] }
    }

    /// Home refreshes only when told to (`topShelfContentDidChange`), so a
    /// status line older than this is dropped rather than shown as current.
    public static let statusLifetime: TimeInterval = 600

    /// The item's status line, if it was confirmed within `statusLifetime`.
    public func statusLine(for item: Item, now: Date) -> String? {
        guard let line = item.statusLine, let at = item.statusAt else { return nil }
        let age = now.timeIntervalSince(at)
        guard age >= 0, age <= Self.statusLifetime else { return nil }
        return line
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

    /// The @2x hero, when this entry has one (nil for the legacy format).
    public func imageURL2x(for item: Item) -> URL? {
        item.imageFile2x.map { directory.appendingPathComponent($0) }
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
        func write(_ data: Data) throws -> String {
            let digest = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }.joined()
            let filename = "preview-\(digest).png"
            let url = directory.appendingPathComponent(filename)
            if !FileManager.default.fileExists(atPath: url.path) {
                try data.write(to: url, options: .atomic)
                changed = true
            }
            return filename
        }
        for preview in previews {
            let filename = try write(preview.imageData)
            let filename2x = try preview.imageData2x.map(write)
            current.append(Item(panelID: preview.panelID, name: preview.name, imageFile: filename,
                                imageFile2x: filename2x, statusLine: preview.statusLine,
                                statusAt: preview.statusLine == nil ? nil : preview.statusAt))
        }
        if current != previousManifest {
            try JSONEncoder().encode(current).write(to: manifestURL, options: .atomic)
            // A renewed `statusAt` is written (the stale rule reads it) but
            // does not make Home reload artwork it already has.
            if previousManifest?.map(\.shown) != current.map(\.shown) { changed = true }
        }
        let currentFiles = Set(current.flatMap { [$0.imageFile, $0.imageFile2x].compactMap { $0 } })
        for item in previous {
            for file in [item.imageFile, item.imageFile2x].compactMap({ $0 }) where !currentFiles.contains(file) {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
            }
        }
        return changed
    }

    public func clear() throws { try replace([]) }
}
