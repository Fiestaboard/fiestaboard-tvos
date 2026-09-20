import TVServices

final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        guard let store = TopShelfSnapshotStore.shared() else { return nil }
        let items = store.items().compactMap { saved -> TVTopShelfCarouselItem? in
            let imageURL = store.imageURL(for: saved)
            guard FileManager.default.fileExists(atPath: imageURL.path) else { return nil }
            var actionURL = URLComponents()
            actionURL.scheme = "fiestaboard"
            actionURL.host = "panel"
            actionURL.path = "/\(saved.panelID)"
            guard let url = actionURL.url else { return nil }

            let item = TVTopShelfCarouselItem(identifier: saved.panelID)
            item.title = saved.name
            item.setImageURL(imageURL, for: [.screenScale1x, .screenScale2x])
            item.playAction = TVTopShelfAction(url: url)
            return item
        }
        guard !items.isEmpty else { return nil }
        return TVTopShelfCarouselContent(style: .details, items: items)
    }
}
