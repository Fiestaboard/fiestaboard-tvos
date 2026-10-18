import Foundation
import TVServices
import os

/// Keeps the Top Shelf cards in step with the board's panel list.
///
/// Each card opens its panel directly. Publishing is local work — it needs the
/// panel list, which the caller already has, and nothing off the network.
@MainActor
enum TopShelfPreviewPublisher {

    /// Owned by AppModel and cleared at sign-out. Each arrival renders only
    /// its changed card, not every board that has already answered.
    final class Cache {
        struct Entry {
            let panel: Panel
            let state: PanelPreviewState
            let image: Data
        }
        var images: [String: Entry] = [:]
    }

    /// Every way this can fail is invisible from the sofa: Home simply keeps
    /// showing the static poster, which looks exactly like a full-screen carousel item
    /// that worked. That is how an unwritable store went unnoticed for the
    /// life of the feature. So each refusal says which one it was, and a
    /// failed write is logged rather than discarded — the log is the only
    /// place the difference exists.
    ///
    /// The logging lives here and not in `TopShelfSnapshotStore`: that file
    /// is also compiled into the Top Shelf extension, which builds with
    /// `APPLICATION_EXTENSION_API_ONLY`, and it sits in Core, which the
    /// layering guard keeps free of anything the Android port cannot have.
    private static let log = Logger(subsystem: "com.fiestaboard.tv", category: "topshelf")

    static func publish(panels: [Panel], previews: [String: PanelPreviewState] = [:],
                        connection: ConnectionStore, store: TopShelfSnapshotStore,
                        cache: Cache? = nil) {
        // Nothing is written for a board we are no longer entitled to show.
        guard connection.saved != nil else {
            log.debug("Not publishing: no board is saved.")
            return
        }
        guard !connection.isSignedOut else {
            log.debug("Not publishing: signed out of the saved board.")
            return
        }
        let available = panels.filter { !$0.boardMissing }
        let ids = Set(available.map(\.id))
        if let cache { cache.images = cache.images.filter { ids.contains($0.key) } }
        let snapshots = available.compactMap { panel -> TopShelfSnapshotStore.Preview? in
            var state = previews[panel.id] ?? .unavailable
            if case .loading = state, let entry = cache?.images[panel.id], entry.panel == panel,
               case .ready = entry.state {
                // A new grid model can reuse the previous truthful snapshot
                // while refreshing; an actual failed response still replaces it.
                state = entry.state
            }
            let image: Data?
            if let entry = cache?.images[panel.id], entry.panel == panel, entry.state == state {
                image = entry.image
            } else if case .ready(let preview) = state {
                image = TopShelfPreviewRenderer.image(panel: panel, preview: preview)
            } else {
                image = TopShelfPreviewRenderer.unavailable
            }
            guard let image else {
                log.error("Could not render a Top Shelf preview.")
                return nil
            }
            cache?.images[panel.id] = .init(panel: panel, state: state, image: image)
            return .init(panelID: panel.id, name: panel.name, imageData: image)
        }

        do {
            try store.replace(snapshots)
        } catch {
            log.error("Publishing \(snapshots.count) Top Shelf item(s) failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        TVTopShelfContentProvider.topShelfContentDidChange()
    }

    static func clear(store: TopShelfSnapshotStore?) {
        guard let store else { return }
        do {
            try store.clear()
        } catch {
            // Tell Home anyway. A clear that failed still leaves items the
            // app no longer stands behind, and asking Home to reload gives
            // the extension its chance to decline to vend them.
            log.error("Clearing the Top Shelf cards failed: \(error.localizedDescription, privacy: .public)")
        }
        TVTopShelfContentProvider.topShelfContentDidChange()
    }
}
