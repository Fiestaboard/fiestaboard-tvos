import SwiftUI

/// DD19 / A8f (`277:138880`): a long text page as **one focus target** the
/// remote scrolls. Unfocusable text in a List can't be reached by D-pad, so
/// the body text is a single focusable view: Up and Down move the scroll
/// view a few lines at a time. Left returns to the categories; Menu closes.
/// S2: a thin scroll bar beside the text is the focus cue, brand-coloured
/// while focused (07b A8f's amber indicator), even when the text fits.
///
/// The focus target is the text *inside* the scroll view, not the scroll
/// view: on tvOS 26 a `.focusable()` ScrollView never takes focus (27 lets
/// it), and a focusable inside a scroll view is the platform's own pattern.
/// Focus is also requested on appear, because the page replaces a list in
/// place and `defaultFocus` alone is not re-evaluated for that on 26.
struct SettingsDetailPage: View {
    let title: String
    let text: String
    let footer: String?

    init(title: String, body: String, footer: String? = nil) {
        self.title = title
        self.text = body
        self.footer = footer
    }

    @State private var position = ScrollPosition(edge: .top)
    @State private var offset: CGFloat = 0
    @State private var maxOffset: CGFloat = 0
    @State private var viewport: CGFloat = 1
    @State private var content: CGFloat = 1
    @FocusState private var focused: Bool

    /// One move: about three lines of Body (36 pt line height).
    static let step: CGFloat = 108

    /// 07b A8f: a 6 pt track, the thumb in --primary while focused.
    private var scrollBar: some View {
        let thumb = viewport * min(1, viewport / content)
        let travel = viewport - thumb
        let y = maxOffset > 0 ? travel * offset / maxOffset : 0
        return ZStack(alignment: .top) {
            Capsule().fill(Fiesta.Colors.surfaceRaised)
            Capsule().fill(focused ? Fiesta.Colors.brand : Fiesta.Colors.mutedForeground.opacity(0.4))
                .frame(height: thumb)
                .offset(y: y)
        }
        .frame(width: 6, height: viewport)
        .accessibilityHidden(true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 07b tvOS/Title 3: 48 semibold.
            Text(title)
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(Fiesta.Colors.foreground)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: 24) {
            ScrollView {
                Text(text)
                    .font(Fiesta.Text.body)
                    .foregroundStyle(Fiesta.Colors.foreground)
                    .lineSpacing(7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .focusable()
                    .focused($focused)
                    .onMoveCommand { direction in
                        switch direction {
                        case .down: offset = min(offset + Self.step, maxOffset)
                        case .up: offset = max(offset - Self.step, 0)
                        default: return
                        }
                        withAnimation(.easeOut(duration: 0.2)) { position.scrollTo(y: offset) }
                    }
                    .accessibilityIdentifier("settings.detail.body")
            }
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGSize.self) { CGSize(width: $0.containerSize.height, height: $0.contentSize.height) } action: { _, new in
                viewport = max(new.width, 1)
                content = max(new.height, 1)
                maxOffset = max(0, new.height - new.width)
            }
            .scrollIndicators(.hidden)
            scrollBar
            }
            .frame(maxHeight: 520)
            if let footer {
                // 07b tvOS/Caption 2: 23 regular, muted.
                Text(footer)
                    .font(.system(size: 23))
                    .foregroundStyle(Fiesta.Colors.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .defaultFocus($focused, true)
        .onAppear { DispatchQueue.main.async { focused = true } }
    }
}
