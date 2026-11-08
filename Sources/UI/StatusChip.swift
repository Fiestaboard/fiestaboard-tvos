import SwiftUI

/// Which 07b `tvOS / Status chip` (`152:4203`) kind a chip is drawn as. The
/// copy comes from `PanelStatusChip` (A6a, DD22), so the kind is read back
/// from it rather than carried twice.
enum StatusChipVariant: Equatable, Sendable {
    case override
    case overrideUntilCanceled
    case silencedMessage
    case silencedFreeze
    case silencedPage
    case paused
    case hubUnreachable
    case schedule
    case scheduleNoNextChange
    case reconnected

    init(_ content: StatusChipContent) {
        switch content.kind {
        case .override: self = content.text == "Holds until canceled" ? .overrideUntilCanceled : .override
        case .silenced:
            if content.text.hasSuffix("· showing the last update") { self = .silencedFreeze }
            else if content.text.hasSuffix("· showing the silence page") { self = .silencedPage }
            else { self = .silencedMessage }
        case .paused: self = .paused
        case .hubUnreachable: self = .hubUnreachable
        case .schedule: self = content.text == "Schedule" ? .scheduleNoNextChange : .schedule
        case .reconnected: self = .reconnected
        }
    }

    #if DEBUG
    /// The 07b variant node, per material (Liquid Glass / Regular / Opaque).
    func node(_ material: ViewerMaterial) -> String {
        let nodes: (String, String, String)
        switch self {
        case .override: nodes = ("152:4184", "250:110500", "250:110504")
        case .overrideUntilCanceled: nodes = ("275:138737", "275:138755", "275:138773")
        case .silencedMessage: nodes = ("152:4188", "250:110508", "250:110511")
        case .silencedFreeze: nodes = ("275:138741", "275:138759", "275:138777")
        case .silencedPage: nodes = ("275:138745", "275:138763", "275:138781")
        case .paused: nodes = ("152:4192", "250:110514", "250:110517")
        case .hubUnreachable: nodes = ("152:4196", "250:110520", "250:110523")
        case .schedule: nodes = ("152:4200", "250:110526", "250:110529")
        case .scheduleNoNextChange: nodes = ("275:138752", "275:138770", "275:138788")
        case .reconnected: nodes = ("275:138749", "275:138767", "275:138785")
        }
        switch material {
        case .liquidGlass: return nodes.0
        case .regularMaterial: return nodes.1
        case .opaque: return nodes.2
        }
    }
    #endif
}

/// The read-only status chip (4.6; 07b `152:4203`). Never a button: the TV
/// cannot change what the hub is doing. Words plus an icon, never colour alone.
///
/// DD25: in the overlay bar it is **plain content** (the bar is the glass;
/// glass is not nested). On its own, with the overlay down, it draws its own
/// capsule in the viewer material (`StandaloneStatusChip`).
struct StatusChipView: View {
    enum Placement { case inBar, standalone }

    let content: StatusChipContent
    var placement: Placement = .standalone

    @Environment(\.viewerMaterial) private var inherited
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        chip
            // One element, read once; it never takes focus (nothing here is focusable).
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(StatusChipPresenter.label(content))
            .accessibilityIdentifier("status-chip")
    }

    @ViewBuilder
    private var chip: some View {
        switch placement {
        case .inBar:
            row
        case .standalone:
            // 07b: padding leading 24, trailing 32, vertical 16, in a capsule.
            row
                .padding(.leading, 24)
                .padding(.trailing, 32)
                .padding(.vertical, 16)
                .viewerSurface(in: Capsule())
                #if DEBUG
                .figmaNode(StatusChipVariant(content).node(
                    ViewerMaterial.effective(explicit: nil, inherited: inherited, reduceTransparency: reduceTransparency)))
                #endif
        }
    }

    private var row: some View {
        HStack(spacing: 18) {
            leading
            Text(content.text)
                .font(Fiesta.Text.callout)
                .foregroundStyle(Fiesta.Colors.foreground)
                .lineLimit(1)
                .fixedSize()
        }
    }

    @ViewBuilder
    private var leading: some View {
        switch content.kind {
        case .override:
            // 07b "Override badge": --primary capsule, Caption 1, padding 16 × 6.
            Text(content.badge ?? "Override")
                .font(Fiesta.Text.caption1)
                .foregroundStyle(Fiesta.Colors.brandForeground)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Fiesta.Colors.brand, in: Capsule())
                .fixedSize()
        case .silenced: icon("moon", Fiesta.Colors.foreground)
        case .paused: icon("pause", Fiesta.Colors.foreground)
        case .hubUnreachable: icon("wifi.slash", Fiesta.Colors.warning)
        case .schedule, .reconnected:
            Circle().fill(Fiesta.Colors.success).frame(width: 18, height: 18)
        }
    }

    /// 07b draws Lucide icons at 32 pt; the app's icons are SF Symbols
    /// (platform-native), so the nearest symbol stands in, at the same box.
    private func icon(_ name: String, _ tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 26, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 32, height: 32)
    }
}

/// The chip on its own, with the overlay down: A7 `I166:204936;149:182603`
/// puts it top-trailing inside title-safe, on its own surface (DD25), in its
/// own `ViewerGlassContainer` so it resolves the material itself.
struct StandaloneStatusChip: View {
    /// Registry probe (A4a inset check).
    static let probe = "tv:status-chip"
    #if DEBUG
    /// The A7 chip instance.
    static let a7Node = "I166:204936;149:182603;166:206937"
    #endif

    let content: StatusChipContent

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                ViewerGlassContainer {
                    StatusChipView(content: content, placement: .standalone)
                }
                .figmaNode(Self.probe)
                #if DEBUG
                .figmaNode(Self.a7Node)
                #endif
            }
            Spacer(minLength: 0)
        }
        // A4a: inside the full-bleed viewer, title-safe is applied here.
        .padding(.horizontal, PlatformTV.safeSide)
        .padding(.vertical, PlatformTV.safeTopBottom)
        .allowsHitTesting(false)
    }
}

/// When the chip shows on its own, and when a change is news (07b strip
/// `166:206938`): with the overlay (in the bar), and on its own for 6 s
/// whenever the hub's state changes; "Reconnected" for 3 s (DD22); the
/// persistent chips (hub unreachable, silence showing a message) stay.
/// VoiceOver hears each change once. Pure: the viewer model owns the clock.
struct StatusChipPresenter: Equatable {
    static let transient: TimeInterval = 6
    static let reconnectedFor: TimeInterval = 3

    private(set) var chip: StatusChipContent?
    private(set) var shownUntil: Date?
    /// The last status chip's identity, outside an outage: coming back to it
    /// after "Hub unreachable" and "Reconnected" is not a change.
    private var stableIdentity: String?

    /// Take the current chip; true when it is a change worth showing and saying.
    mutating func update(_ new: StatusChipContent?, at now: Date) -> Bool {
        let old = chip
        chip = new
        guard let new else {
            stableIdentity = nil
            return false
        }
        let changed: Bool
        switch new.kind {
        case .hubUnreachable, .reconnected:
            changed = old?.kind != new.kind
        default:
            let identity = Self.identity(new)
            changed = identity != stableIdentity
            stableIdentity = identity
        }
        if changed {
            shownUntil = now.addingTimeInterval(new.kind == .reconnected ? Self.reconnectedFor : Self.transient)
        }
        return changed
    }

    func standaloneVisible(at now: Date, overlayVisible: Bool) -> Bool {
        guard !overlayVisible, let chip else { return false }
        return chip.persistent || (shownUntil.map { now < $0 } ?? false)
    }

    /// When the standalone chip next needs another look; nil while persistent.
    var nextDeadline: Date? {
        guard let chip, !chip.persistent else { return nil }
        return shownUntil
    }

    /// The chip minus what moves on its own: "2h 43m left · Holds until 9:00 PM"
    /// and "2h 42m left · Holds until 9:00 PM" are the same override, and a
    /// schedule is one schedule whatever its next change says. A hand-off
    /// ("· next change 9:00 PM", then "Schedule" as it passes, then the next
    /// read's new time) is the board on its schedule, not news (#25 review N2).
    static func identity(_ chip: StatusChipContent) -> String {
        if chip.kind == .schedule { return chip.kind.rawValue }
        var text = chip.text
        if chip.kind == .override, let range = text.range(of: " left · ") { text = String(text[range.upperBound...]) }
        return "\(chip.kind.rawValue)|\(text)"
    }

    /// The chip as one VoiceOver element.
    static func label(_ chip: StatusChipContent) -> String {
        chip.badge.map { "\($0), \(chip.text)" } ?? chip.text
    }

    /// The one announcement per change, in the strip's phrasing (`166:206938`:
    /// "Living room TV: override until 9:00 PM"): no countdown, which is stale
    /// by the time it is heard, and a comma where the chip has a middle dot.
    static func spoken(_ chip: StatusChipContent, panelName: String) -> String {
        "\(panelName): \(phrase(chip))"
    }

    static func phrase(_ chip: StatusChipContent) -> String {
        if chip.kind == .override {
            guard let until = chip.text.range(of: "Holds until ") else { return "override" }
            return "override until " + chip.text[until.upperBound...]
        }
        let text = chip.text.replacingOccurrences(of: " · ", with: ", ")
        return text.prefix(1).lowercased() + text.dropFirst()
    }
}
