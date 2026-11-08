import Foundation

/// What the carousel can say about a panel (A7; DD2, DD22).
///
/// UI-side on purpose: the hub's panel status is decoded by A6a
/// (`Core/PanelStatus*`, #22). Until that lands nothing produces one of
/// these, so no carousel item has a contextTitle — which is the honest
/// state. The follow-up maps `PanelStatus` onto this in a few lines.
enum TopShelfStatus: Equatable, Sendable {
    /// An override holds the panel, until a time or until canceled.
    case override(until: Date?)
    /// The schedule is driving the panel.
    case schedule
    /// Changes are paused.
    case paused
    /// The panel is silenced, until a time or indefinitely.
    case silenced(until: Date?)
    /// Nothing worth a line: Top Shelf shows status only.
    case manual
}

/// The carousel's `contextTitle`: status only, with **absolute** times.
///
/// Home redraws Top Shelf only when the app calls
/// `topShelfContentDidChange`, so a countdown ("2h 42m left") would be
/// wrong a minute later. "Holds until 9:00 PM" stays true until it isn't,
/// and the 10-minute stale rule (`TopShelfSnapshotStore.statusLifetime`)
/// drops a line nobody has reconfirmed.
enum TopShelfStatusLine {
    static func make(_ status: TopShelfStatus?, timeZone: TimeZone = .current) -> String? {
        guard let status else { return nil }
        switch status {
        case .override(let until):
            return "Now showing · Override · holds until " + (until.map { time($0, timeZone) } ?? "canceled")
        case .schedule:
            return "Now showing · Schedule"
        case .paused:
            return "Paused"
        case .silenced(let until):
            return until.map { "Silenced · until " + time($0, timeZone) } ?? "Silenced"
        case .manual:
            return nil
        }
    }

    /// 12-hour clock, as the rest of the TV copy ("9:00 PM").
    private static func time(_ date: Date, _ zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
