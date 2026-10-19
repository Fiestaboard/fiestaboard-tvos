import SwiftUI

/// Transient chrome over the board.
///
/// The board is the content; this is the only furniture allowed on top of
/// it, so it stays a single bar pinned to the top, sized to its contents,
/// on the system's own `.regularMaterial` for readable dark overlays.
/// The actions are stock tvOS
/// buttons — the platform supplies their shape, metrics and focus lift, so
/// they read from across a room the same way every other Apple TV button
/// does, and nothing here hand-rolls a focus effect.
struct ViewerOverlay: View {
    let panelName: String
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
            bar
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

    private var bar: some View {
        HStack(spacing: 20) {
            Text(panelName)
                .font(.title2)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 24)

            Button("Panels", action: onPanels)
                .focused($focusedAction, equals: .panels)
            Button("Settings", action: onSettings)
                .focused($focusedAction, equals: .settings)
            if let onFiestaBot {
                Button("FiestaBot", action: onFiestaBot)
                    .focused($focusedAction, equals: .bot)
            }
        }
        .buttonStyle(.bordered)
        // Hug the top: a taller bar hides more of the board than it needs to.
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: Fiesta.Metrics.cornerRadius))
        .padding(.horizontal, Fiesta.Metrics.safeInset)
        .padding(.top, Fiesta.Metrics.safeInset)
    }
}

/// The board's status, bottom-right, where the web viewer puts its dot.
///
/// It *was* the web viewer's dot: a bare `Circle` carrying an
/// `.accessibilityLabel`. A `Shape` is not an accessibility element, so that
/// label reached nobody, and colour alone was the entire signal — which is
/// the one thing a roomful of people cannot all be relied on to see. A
/// labelled pill says the same thing in words, and keeps the tint.
struct BoardStatusPill: View {
    let title: String
    let systemImage: String
    let tint: Color
    /// What VoiceOver says. Longer than the pill, because the pill has the
    /// board behind it for context and a spoken label has nothing.
    let spoken: String

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Label(title, systemImage: systemImage)
                    .font(Fiesta.Text.caption)
                    .foregroundStyle(tint)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    // `.ignore` is what makes this an element at all, rather
                    // than an icon and a string VoiceOver reads separately.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spoken)
                    .padding(Fiesta.Metrics.safeInset)
            }
        }
    }
}
