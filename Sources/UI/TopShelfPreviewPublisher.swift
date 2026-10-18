import Foundation
import CoreGraphics
import ImageIO
import TVServices
import os

/// Keeps Home's local cards in step with already-fetched panel previews.
@MainActor
enum TopShelfPreviewPublisher {
    /// One running publication and one replaceable pending request. A burst
    /// of frame replies must not queue a burst of 1080p renders behind input.
    @MainActor
    final class Cache {
        struct Entry {
            let panel: Panel
            let state: PanelPreviewState
            let image: Data
        }
        var images: [String: Entry] = [:]
        private var pending: Request?
        private var pendingClear: URL?
        private var needsNotification = false
        private var revision = UUID()
        private var generation = UUID()
        private var task: Task<Void, Never>?
        private let writer: Writer

        init(encode: @escaping @Sendable (CGImage) -> Data? = { Writer.png($0) }) {
            writer = Writer(encode: encode)
        }

        /// Invalidate work from an old refresh even if no new frame arrives.
        /// The drain itself is never cancelled: it owns ordered disk cleanup.
        func invalidate() {
            generation = UUID()
            revision = UUID()
            pending = nil
        }

        fileprivate func enqueue(_ request: Request) -> Task<Void, Never> {
            revision = UUID()
            pending = request
            return start()
        }

        fileprivate func clear(directory: URL) -> Task<Void, Never> {
            invalidate()
            images.removeAll()
            pendingClear = directory
            return start()
        }

        private func start() -> Task<Void, Never> {
            if let task { return task }
            let task = Task { await drain() }
            self.task = task
            return task
        }

        private func drain() async {
            while pendingClear != nil || pending != nil {
                // Clearing cannot be coalesced away by a reconnect. It also
                // runs after any write that was already in progress.
                if let directory = pendingClear {
                    pendingClear = nil
                    await writer.clear(directory: directory)
                    needsNotification = false
                    TVTopShelfContentProvider.topShelfContentDidChange()
                    continue
                }
                guard let request = pending else { continue }
                pending = nil
                await publish(request, revision: revision, generation: generation)
            }
            task = nil
        }

        private func publish(_ request: Request, revision: UUID, generation: UUID) async {
            guard request.isAuthorized else { return }
            let available = request.panels.filter { !$0.boardMissing }
            let ids = Set(available.map(\.id))
            images = images.filter { ids.contains($0.key) }
            var snapshots: [Writer.Preview] = []
            for panel in available {
                guard self.revision == revision, request.isAuthorized else { return }
                var state = request.previews[panel.id] ?? .unavailable
                if case .loading = state, let entry = images[panel.id], entry.panel == panel,
                   case .ready = entry.state {
                    state = entry.state
                }
                let image: Data?
                if let entry = images[panel.id], entry.panel == panel, entry.state == state {
                    image = entry.image
                } else {
                    let rendered: CGImage?
                    let unavailable: Bool
                    if case .ready(let preview) = state {
                        unavailable = preview.rows <= 0 || preview.cols <= 0
                        rendered = TopShelfPreviewRenderer.image(panel: panel, preview: preview)
                    } else {
                        unavailable = true
                        rendered = TopShelfPreviewRenderer.unavailable
                    }
                    guard let rendered else {
                        log.error("Could not render a Top Shelf preview.")
                        continue
                    }
                    image = await writer.encode(rendered, unavailable: unavailable)
                    guard self.generation == generation, request.isAuthorized else { return }
                    // Reuse completed encoding if the pending request still
                    // wants it, but never resurrect a cleared connection.
                    if let image { images[panel.id] = .init(panel: panel, state: state, image: image) }
                }
                guard self.revision == revision else { return }
                if let image { snapshots.append(.init(panelID: panel.id, name: panel.name, imageData: image)) }
            }
            guard self.revision == revision, request.isAuthorized else { return }
            guard let changed = await writer.replace(snapshots, directory: request.directory) else { return }
            // An obsolete write may already have committed before a newer
            // request arrived. Its successor still owes Home a reload even
            // when that successor wants exactly the bytes now on disk.
            needsNotification = needsNotification || changed
            guard self.revision == revision, self.generation == generation, request.isAuthorized else { return }
            if needsNotification {
                needsNotification = false
                TVTopShelfContentProvider.topShelfContentDidChange()
            }
        }
    }

    @MainActor
    fileprivate struct Request {
        let panels: [Panel]
        let previews: [String: PanelPreviewState]
        let connection: ConnectionStore
        let client: FiestaClient?
        let directory: URL

        var isAuthorized: Bool {
            connection.saved != nil && !connection.isSignedOut && connection.client === client
        }
    }

    nonisolated private static let log = Logger(subsystem: "com.fiestaboard.tv", category: "topshelf")

    @discardableResult
    static func publish(panels: [Panel], previews: [String: PanelPreviewState] = [:],
                        connection: ConnectionStore, store: TopShelfSnapshotStore,
                        cache: Cache? = nil) -> Task<Void, Never>? {
        guard connection.saved != nil, !connection.isSignedOut else { return nil }
        return (cache ?? Cache()).enqueue(Request(panels: panels, previews: previews, connection: connection,
                                     client: connection.client, directory: store.directory))
    }

    @discardableResult
    static func clear(store: TopShelfSnapshotStore?, cache: Cache) -> Task<Void, Never>? {
        guard let store else { cache.invalidate(); return nil }
        return cache.clear(directory: store.directory)
    }

    /// Only immutable pixels and value snapshots cross from the main actor.
    /// Compression, hashing and filesystem work all execute on this actor.
    private actor Writer {
        struct Preview: Sendable {
            let panelID: String
            let name: String
            let imageData: Data
        }
        private let encoder: @Sendable (CGImage) -> Data?
        init(encode: @escaping @Sendable (CGImage) -> Data?) { encoder = encode }
        private var unavailableImage: Data?
        func encode(_ image: CGImage, unavailable: Bool) -> Data? {
            if unavailable, let unavailableImage { return unavailableImage }
            let data = encoder(image)
            if data == nil { log.error("Could not encode a Top Shelf preview.") }
            if unavailable { unavailableImage = data }
            return data
        }

        nonisolated static func png(_ image: CGImage) -> Data? {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)
            else { return nil }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return data as Data
        }

        func replace(_ previews: [Preview], directory: URL) -> Bool? {
            do {
                return try TopShelfSnapshotStore(directory: directory).replace(previews.map {
                    .init(panelID: $0.panelID, name: $0.name, imageData: $0.imageData)
                })
            } catch {
                log.error("Publishing Top Shelf items failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }

        func clear(directory: URL) {
            do { try TopShelfSnapshotStore(directory: directory).clear() }
            catch { log.error("Clearing Top Shelf cards failed: \(error.localizedDescription, privacy: .public)") }
        }
    }
}
