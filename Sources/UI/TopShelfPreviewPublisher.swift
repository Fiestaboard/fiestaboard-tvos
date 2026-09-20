import Foundation
import TVServices

@MainActor
enum TopShelfPreviewPublisher {
    static func publish(panels: [Panel], connection: ConnectionStore,
                        store: TopShelfSnapshotStore) async {
        guard let host = connection.saved?.host else { return }
        let cached = Dictionary(store.items().map { ($0.panelID, $0) },
                                uniquingKeysWith: { first, _ in first })
        var previews: [TopShelfSnapshotStore.Preview] = []
        for panel in panels where !panel.boardMissing {
            if Task.isCancelled { return }
            if let frame = try? await connection.authorized({
                try await $0.frame(ref: panel.id)
            }), let png = TopShelfPreviewRenderer.png(panel: panel, frame: frame) {
                previews.append(.init(panelID: panel.id, name: panel.name, imageData: png))
            } else if let item = cached[panel.id],
                      let data = try? Data(contentsOf: store.imageURL(for: item)) {
                previews.append(.init(panelID: panel.id, name: panel.name, imageData: data))
            }
        }
        guard !Task.isCancelled, !connection.isSignedOut,
              connection.saved?.host == host else { return }
        guard (try? store.replace(previews)) != nil else { return }
        TVTopShelfContentProvider.topShelfContentDidChange()
    }

    static func clear(store: TopShelfSnapshotStore?) {
        guard let store else { return }
        try? store.clear()
        TVTopShelfContentProvider.topShelfContentDidChange()
    }
}
