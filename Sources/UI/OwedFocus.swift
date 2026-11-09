import Foundation

/// Focus owed back to a card that a refresh moved into another row.
///
/// The rows carry the focus sections, so a card that changes row is rebuilt
/// there, and the focus engine hands its focus to the neighbour that took
/// its place, passing through nothing on the way. The first card focus
/// lands on after that is given back, once. The debt expires quickly
/// (#21 N4): if the engine never moved focus, the next remote press must
/// not be pulled back to the refreshed card.
struct OwedFocus {
    /// Long enough for the engine's hand-off, short of a deliberate press.
    static let expiry: TimeInterval = 1

    private var owed: (id: String, since: Date)?

    mutating func owe(_ id: String, at now: Date = .now) {
        owed = (id, now)
    }

    /// Where focus should go back to now that it `landedOn` a card, if
    /// anywhere. Focus on nothing keeps the debt for the next landing.
    mutating func take(landedOn id: String?, at now: Date = .now) -> String? {
        guard let debt = owed else { return nil }
        if now.timeIntervalSince(debt.since) > Self.expiry {
            owed = nil
            return nil
        }
        guard let id else { return nil }
        owed = nil
        return id == debt.id ? nil : debt.id
    }

    mutating func cancel() { owed = nil }
}
