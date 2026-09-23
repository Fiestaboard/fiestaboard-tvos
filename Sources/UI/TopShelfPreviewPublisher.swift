import Foundation
import TVServices

/// Keeps the Top Shelf carousel in step with the board's panel list.
///
/// The carousel exists for the shortcut, not the picture: each item deep
/// links straight into its panel. So publishing is local work — it needs the
/// panel list, which the caller already has, and nothing off the network.
@MainActor
enum TopShelfPreviewPublisher {

    static func publish(panels: [Panel], connection: ConnectionStore,
                        store: TopShelfSnapshotStore) {
        // Nothing is written for a board we are no longer entitled to show.
        guard connection.saved != nil, !connection.isSignedOut,
              let poster = TopShelfPreviewRenderer.poster else { return }

        let previews = panels
            .filter { !$0.boardMissing }
            .map { TopShelfSnapshotStore.Preview(panelID: $0.id, name: $0.name,
                                                 imageData: poster) }

        guard (try? store.replace(previews)) != nil else { return }
        TVTopShelfContentProvider.topShelfContentDidChange()
    }

    static func clear(store: TopShelfSnapshotStore?) {
        guard let store else { return }
        try? store.clear()
        TVTopShelfContentProvider.topShelfContentDidChange()
    }
}
