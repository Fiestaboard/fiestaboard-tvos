import Foundation
import TVServices

/// Builds the same content in the extension and its host-app tests.
///
/// A7 (07b A9 `166:207117`, DD2): a full-screen carousel, one item per
/// panel, in the `.actions` style — the system's own Play and More Info
/// buttons, the panel's latest frame as the hero, its name as the title,
/// and its status (only) as the contextTitle. `.actions` hides `summary`,
/// so nothing else is set.
enum TopShelfContent {
    /// More Info opens Panels; Play opens the panel's viewer.
    static let panelsURL = URL(string: "fiestaboard://panels")!

    static func viewerURL(panelID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "fiestaboard"
        components.host = "panel"
        components.path = "/\(panelID)"
        return components.url
    }

    static func make(store: TopShelfSnapshotStore, now: Date = Date()) -> (any TVTopShelfContent)? {
        let items = store.items().compactMap { saved -> TVTopShelfCarouselItem? in
            let oneX = store.imageURL(for: saved)
            guard FileManager.default.fileExists(atPath: oneX.path),
                  let viewer = viewerURL(panelID: saved.panelID) else { return nil }
            // The legacy manifest has one image: it serves both scales.
            let twoX = store.imageURL2x(for: saved).flatMap {
                FileManager.default.fileExists(atPath: $0.path) ? $0 : nil
            } ?? oneX

            let item = TVTopShelfCarouselItem(identifier: saved.panelID)
            item.title = saved.name
            item.contextTitle = store.statusLine(for: saved, now: now)
            item.setImageURL(oneX, for: .screenScale1x)
            item.setImageURL(twoX, for: .screenScale2x)
            item.playAction = TVTopShelfAction(url: viewer)
            item.displayAction = TVTopShelfAction(url: panelsURL)
            return item
        }
        guard !items.isEmpty else { return nil }
        return TVTopShelfCarouselContent(style: .actions, items: items)
    }
}
