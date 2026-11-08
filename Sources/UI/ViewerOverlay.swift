import SwiftUI

/// Transient chrome over the board.
///
/// The board is the content; this is the only furniture allowed on top of
/// it, so it stays a single bar pinned to the top. A4b draws it as 07b's
/// `tvOS / Viewer overlay` (`250:110554`): system Liquid Glass on tvOS 26,
/// the regular material below it, an opaque `--card` bar under Reduce
/// Transparency (`ViewerMaterial`). The brand content sits inside: the
/// panel's name and what it is, a **chip host** for A6b's read-only status
/// chip, then the actions.
/// The actions are stock tvOS buttons — the platform supplies their shape,
/// metrics and focus lift, so they read from across a room the same way
/// every other Apple TV button does, and nothing here hand-rolls a focus
/// effect (DD15: tvOS uses the system focus effect).
struct ViewerOverlay: View {
    #if DEBUG
    /// 07b A4 "tvOS / Viewer overlay" instance. The children are the
    /// component's own nodes under that instance (`154:8170`).
    static let barNode = "I166:191865;149:182603;166:193875"
    static let titleNode = "I166:191865;149:182603;166:193875;154:8171"
    static let chipHostNode = "I166:191865;149:182603;166:193875;154:8174"
    #endif

    /// 07b `154:8170`: the bar's corner radius and insets.
    static let barRadius: CGFloat = 48
    static let spacing: CGFloat = 28

    let panelName: String
    /// "Split-flap · Living room hub" (07b `154:8173`).
    var subtitle: String? = nil
    /// The chip host (07b `154:8174`): A6b's `StatusChipView(placement: .inBar)`.
    /// DD25: the chip is plain content here, because the bar is already the
    /// glass and glass is not nested. It draws its own surface only on its own
    /// (`StandaloneStatusChip`). Nil when there is no status; the host then
    /// takes no space.
    var chip: AnyView? = nil
    /// Called whenever someone is plainly still using the bar.
    ///
    /// The board cannot see this: while the bar is up the wake target has
    /// given up its focusability, so a directional press consumed by the
    /// focus engine moving between these buttons never reaches the
    /// screen's `onMoveCommand`. Without this the bar's four seconds ran out
    /// under the user's thumb.
    let onInteraction: () -> Void
    let onPanels: () -> Void
    let onSettings: () -> Void
    let onFiestaBot: (() -> Void)?

    /// Chrome that appears with nothing focused strands the user: the board
    /// itself has given up its focus target while this is on screen, so the
    /// first action has to take focus as the bar arrives.
    private enum Action: Hashable { case panels, settings, bot }
    @FocusState private var focusedAction: Action?

    var body: some View {
        VStack(spacing: 0) {
            ViewerGlassContainer(spacing: Self.spacing) { bar }
            Spacer(minLength: 0)
        }
        .transition(.opacity)
        .onAppear {
            focusedAction = .panels
            // The bar is the whole of what changed on screen, and nothing
            // about a focus move says so out loud.
            Announce.screenChanged()
        }
        .onChange(of: focusedAction) { _, _ in onInteraction() }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(panelName)
                .font(Fiesta.Text.heading)
                .foregroundStyle(Fiesta.Colors.foreground)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(Fiesta.Text.caption1)
                    .foregroundStyle(Fiesta.Colors.mutedForeground)
                    .lineLimit(1)
            }
        }
        #if DEBUG
        .figmaNode(Self.titleNode, label: panelName)
        #endif
    }

    private var bar: some View {
        HStack(spacing: Self.spacing) {
            title
            if let chip {
                chip
                    #if DEBUG
                    .figmaNode(Self.chipHostNode)
                    #endif
            }

            Spacer(minLength: 0)

            HStack(spacing: Self.spacing) {
                Button("Panels", action: onPanels)
                    .focused($focusedAction, equals: .panels)
                Button("Settings", action: onSettings)
                    .focused($focusedAction, equals: .settings)
                if let onFiestaBot {
                    Button("FiestaBot", action: onFiestaBot)
                        .focused($focusedAction, equals: .bot)
                }
            }
        }
        .buttonStyle(.bordered)
        .padding(.leading, 40)
        .padding(.trailing, 24)
        .padding(.vertical, 22)
        .viewerSurface(in: RoundedRectangle(cornerRadius: Self.barRadius, style: .continuous),
                       tagsOverlayVariant: true)
        #if DEBUG
        .figmaNode(Self.barNode)
        #endif
        // A4 `166:193875`: the bar spans title-safe, (80, 60), 1760 wide. The
        // viewer is full-bleed, so the inset is applied here.
        .padding(.horizontal, PlatformTV.safeSide)
        .padding(.top, PlatformTV.safeTopBottom)
    }
}
