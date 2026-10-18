import SwiftUI

/// A browser-scoped working set. Focus and scroll positions are deliberately
/// absent from the request: neither changes the picture on the board.
@MainActor
final class PanelPreviewImageCache {
    struct Request: Equatable {
        let panel: Panel
        let preview: PanelPreview
        var size: CGSize
        var scale: CGFloat = 1
        var colorScheme: ColorScheme = .dark
        var reduceTransparency = false
        var increasedContrast = false
    }

    private struct Entry {
        let request: Request
        let image: CGImage
        let byteCount: Int
        var lastUse: UInt64
    }

    private let byteLimit: Int
    private let countLimit: Int
    private var entries: [String: Entry] = [:]
    private var byteCount = 0
    private var clock: UInt64 = 0

    init(byteLimit: Int = 32 * 1024 * 1024, countLimit: Int = 12) {
        self.byteLimit = max(0, byteLimit)
        self.countLimit = max(0, countLimit)
    }

    func image(for request: Request, render: () -> CGImage?) -> CGImage? {
        #if DEBUG
        let began = CACurrentMediaTime()
        var hit = false
        defer { PanelNavigationProbe.shared.event(hit ? "thumbnail.hit" : "thumbnail.render", began: began) }
        #endif
        clock &+= 1
        let id = request.panel.id
        if var entry = entries[id], entry.request == request {
            #if DEBUG
            hit = true
            #endif
            entry.lastUse = clock
            entries[id] = entry
            return entry.image
        }

        // Keep only the latest picture for a panel, including when a new
        // render fails. Never let a failed render become a permanent hit.
        remove(id)
        guard let image = render() else { return nil }
        let cost = image.bytesPerRow * image.height
        guard countLimit > 0, cost <= byteLimit else { return image }
        while entries.count >= countLimit || byteCount + cost > byteLimit {
            guard let oldest = entries.min(by: { $0.value.lastUse < $1.value.lastUse })?.key else { break }
            remove(oldest)
        }
        entries[id] = Entry(request: request, image: image, byteCount: cost, lastUse: clock)
        byteCount += cost
        return image
    }

    func removeAll() {
        entries.removeAll()
        byteCount = 0
    }

    private func remove(_ id: String) {
        if let removed = entries.removeValue(forKey: id) { byteCount -= removed.byteCount }
    }
}
