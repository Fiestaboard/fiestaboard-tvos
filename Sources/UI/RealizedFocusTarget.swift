/// Focus that is only ever handed to a card that exists.
///
/// The panel grid is a `LazyVGrid`: a card far down the list isn't a view
/// until its row is realised. Assigning `@FocusState` to a card that isn't
/// realised yet is silently dropped by SwiftUI, and the focus engine picks
/// something else. Restoring the last-watched card used to `scrollTo` it,
/// `Task.yield()` once and assign focus, which raced realisation: idle it
/// won, under load it lost (30% of 20 runs; `program/status/tv-panels-flake.md`).
///
/// This holds the card focus is owed to, applies it at once if that card is
/// realised, and otherwise applies it when the card appears.
struct RealizedFocusTarget {
    private(set) var pending: String?
    private var realized: Set<String> = []

    /// - Returns: the card to focus now, or nil to wait for its appearance.
    mutating func request(_ id: String) -> String? {
        if realized.contains(id) {
            pending = nil
            return id
        }
        pending = id
        return nil
    }

    /// - Returns: the card to focus now, if it was the one being waited for.
    mutating func cardAppeared(_ id: String) -> String? {
        realized.insert(id)
        guard pending == id else { return nil }
        pending = nil
        return id
    }

    func isRealized(_ id: String) -> Bool { realized.contains(id) }

    mutating func cardDisappeared(_ id: String) {
        realized.remove(id)
    }

    mutating func cancel() {
        pending = nil
    }
}
