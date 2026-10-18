import Foundation
import TVServices

/// Builds the same content in the extension and its host-app tests.
enum TopShelfContent {
    static func make(store: TopShelfSnapshotStore) -> (any TVTopShelfContent)? {
        let items = store.items().compactMap { saved -> TVTopShelfSectionedItem? in
            let imageURL = store.imageURL(for: saved)
            guard FileManager.default.fileExists(atPath: imageURL.path) else { return nil }
            var actionURL = URLComponents()
            actionURL.scheme = "fiestaboard"
            actionURL.host = "panel"
            actionURL.path = "/\(saved.panelID)"
            guard let url = actionURL.url else { return nil }

            let item = TVTopShelfSectionedItem(identifier: saved.panelID)
            item.title = saved.name
            item.imageShape = .hdtv
            item.setImageURL(imageURL, for: [.screenScale1x, .screenScale2x])
            item.playAction = TVTopShelfAction(url: url)
            // Select opens a sectioned card through displayAction. A play
            // action alone only responds to the remote's Play/Pause button.
            item.displayAction = TVTopShelfAction(url: url)
            return item
        }
        guard !items.isEmpty else { return nil }
        let section = TVTopShelfItemCollection(items: items)
        section.title = "Available panels"
        return TVTopShelfSectionedContent(sections: [section])
    }
}
