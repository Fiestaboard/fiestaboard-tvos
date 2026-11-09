import Foundation

/// What the carousel can say about a panel (A7; DD2, DD22).
///
/// Built from A6a's `PanelReading` (`init(reading:receivedAt:)` below); the
/// carousel needs only what fits one absolute-time line.
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

extension TopShelfStatus {
    /// A6a's reading of `GET /panel/{id}`, through A6a's chip precedence on
    /// the hub's clock (the response's `Date`), as the carousel's status.
    /// Nil for a panel with nothing to say (manual) and for an old hub.
    init?(reading: PanelReading, receivedAt: Date) {
        let hubNow = HubClock(hubDate: reading.hubDate, receivedAt: receivedAt).now(at: receivedAt)
        guard let chip = PanelStatusChip.chip(status: reading.panel.status, hubNow: hubNow) else { return nil }
        switch chip.kind {
        case .override: self = .override(until: chip.overrideEndsAt)
        case .silenced: self = .silenced(until: chip.silencedUntil)
        case .paused: self = .paused
        case .schedule: self = .schedule
        case .hubUnreachable, .reconnected: return nil
        }
    }
}

/// A status and when the app read it: the store's 10-minute rule runs
/// from the read, not from the publish.
struct TopShelfStatusReading: Equatable, Sendable {
    let status: TopShelfStatus
    let at: Date
}
