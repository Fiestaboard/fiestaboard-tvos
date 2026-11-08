import Foundation

/// A panel with the hub's `Date` header from the same response.
public struct PanelReading: Equatable, Sendable {
    public let panel: Panel
    /// Nil when the hub sent no `Date` header (or one that does not parse).
    public let hubDate: Date?

    public init(panel: Panel, hubDate: Date?) {
        self.panel = panel
        self.hubDate = hubDate
    }
}

/// The hub's clock: the panel response's `Date` header against the local time
/// it arrived. Without a `Date` header, the local clock.
///
/// An HTTP date has whole seconds, so the offset carries up to a second of
/// error; the chip counts whole minutes rounded up, which absorbs it.
public struct HubClock: Equatable, Sendable {
    /// Hub minus local, in seconds.
    public let offset: TimeInterval

    public init(hubDate: Date?, receivedAt: Date) {
        offset = hubDate.map { $0.timeIntervalSince(receivedAt) } ?? 0
    }

    private init(offset: TimeInterval) { self.offset = offset }

    /// The local clock, for a hub that sent no `Date` (and before any reading).
    public static let local = HubClock(offset: 0)

    public func now(at local: Date) -> Date { local.addingTimeInterval(offset) }
}

/// Whether the TV can reach its hub. Client-side: the status cannot say.
public enum HubConnection: Equatable, Sendable {
    case reachable
    case unreachable
    /// Back after being unreachable; the chip says so briefly (A6b).
    case reconnected
}

public enum StatusChipKind: String, Equatable, Sendable {
    case override
    case silenced
    case paused
    case schedule
    case hubUnreachable = "hub_unreachable"
    case reconnected
}

/// The chip to show and the facts its copy needs.
public struct StatusChip: Equatable, Sendable {
    public let kind: StatusChipKind
    /// Persistent chips stay up; the rest show briefly on change (A6b).
    public let persistent: Bool
    public var overrideEndsAt: Date? = nil
    /// Time left on the override, on the hub's clock.
    public var remaining: TimeInterval? = nil
    public var silencedUntil: Date? = nil
    public var silenceMode: SilenceMode? = nil
    /// The schedule's next change, only when it is still ahead on the hub's clock.
    public var nextChangeAt: Date? = nil
}

/// What the UI draws: the one value A4b's chip host and A6b's chip view need.
public struct StatusChipContent: Equatable, Sendable {
    public let kind: StatusChipKind
    /// "Override", or nil.
    public let badge: String?
    public let text: String
    public let persistent: Bool
}

/// The read-only status chip (4.6; DD22 copy; same table as Android TV G6a).
///
/// Precedence follows the hub's display loop: hub unreachable (client-side)
/// first, then "Reconnected", then paused (a paused board keeps its last frame
/// even under an override), then an override still running on the hub's
/// clock, then silence, then the schedule. A manual board shows no chip.
///
/// The status carries no trigger state, and a primary-board trigger can show
/// while `override_active` is true (H1 review). So the override chip names the
/// board's mode and never says what is showing.
public enum PanelStatusChip {

    public static func chip(status: PanelStatus?, hubNow: Date,
                            connection: HubConnection = .reachable) -> StatusChip? {
        switch connection {
        case .unreachable: return StatusChip(kind: .hubUnreachable, persistent: true)
        case .reconnected: return StatusChip(kind: .reconnected, persistent: false)
        case .reachable: break
        }
        guard let status else { return nil }
        if status.paused { return StatusChip(kind: .paused, persistent: false) }
        let ends = status.overrideExpiresAt
        if status.overrideActive, ends.map({ $0 > hubNow }) ?? true {
            return StatusChip(kind: .override, persistent: false, overrideEndsAt: ends,
                              remaining: ends.map { $0.timeIntervalSince(hubNow) })
        }
        if status.silenced {
            return StatusChip(kind: .silenced, persistent: status.silenceMode == .indicator,
                              silencedUntil: status.silencedUntil, silenceMode: status.silenceMode)
        }
        // An override that ran out on the hub's clock before the hub noticed
        // hands back to the schedule when the schedule is on.
        if status.mode == .schedule || (status.mode == .override && status.scheduleEnabled) {
            return StatusChip(kind: .schedule, persistent: false,
                              nextChangeAt: status.nextChangeAt.flatMap { $0 > hubNow ? $0 : nil })
        }
        return nil
    }

    public static func content(_ chip: StatusChip, timeZone: TimeZone = .current) -> StatusChipContent {
        let at = { (date: Date) in time(date, timeZone) }
        let text: String
        var badge: String? = nil
        switch chip.kind {
        case .override:
            badge = "Override"
            if let ends = chip.overrideEndsAt {
                text = "\(left(chip.remaining ?? 0)) · Holds until \(at(ends))"
            } else {
                text = "Holds until canceled"
            }
        case .silenced:
            let head = chip.silencedUntil.map { "Silenced until \(at($0))" } ?? "Silenced"
            switch chip.silenceMode {
            case .freeze: text = head + " · showing the last update"
            case .page: text = head + " · showing the silence page"
            case .indicator: text = head + " · showing a message"
            case nil: text = head
            }
        case .paused: text = "Paused · showing the last update"
        case .schedule: text = chip.nextChangeAt.map { "Schedule · next change \(at($0))" } ?? "Schedule"
        case .hubUnreachable: text = "Hub unreachable · showing the last update"
        case .reconnected: text = "Reconnected"
        }
        return StatusChipContent(kind: chip.kind, badge: badge, text: text, persistent: chip.persistent)
    }

    /// "2h 42m left": whole minutes rounded up, so the last seconds never read "0m left".
    static func left(_ remaining: TimeInterval) -> String {
        let minutes = max(Int((remaining / 60).rounded(.up)), 0)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m left" : "\(minutes)m left"
    }

    /// "9:00 PM", with a plain space whatever ICU puts before the period.
    static func time(_ date: Date, _ zone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = "h:mm a"
        return f.string(from: date)
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}

extension PanelSnapshot {
    /// The chip for this snapshot at `localNow` (the TV's clock), counted on
    /// the hub's clock. A stale connection reads "Hub unreachable"; the
    /// viewer passes `reconnected` for the moment after it comes back.
    public func statusChip(localNow: Date, reconnected: Bool = false,
                           timeZone: TimeZone = .current) -> StatusChipContent? {
        let connection: HubConnection = connection == .stale ? .unreachable : (reconnected ? .reconnected : .reachable)
        return PanelStatusChip.chip(status: panel?.status, hubNow: hubClock.now(at: localNow), connection: connection)
            .map { PanelStatusChip.content($0, timeZone: timeZone) }
    }
}
