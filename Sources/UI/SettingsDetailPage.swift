import SwiftUI

/// DD19 / A8f (`277:138880`): a long text page as **one focus target** the
/// remote scrolls. Unfocusable text in a List can't be reached by D-pad, so
/// the body text is a single focusable view: Up and Down move the scroll
/// view a few lines at a time, and focus never leaves it until Menu.
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
    @FocusState private var focused: Bool

    /// One move: about three lines of Body (36 pt line height).
    static let step: CGFloat = 108

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 07b tvOS/Title 3: 48 semibold.
            Text(title)
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(Fiesta.Colors.foreground)
                .accessibilityAddTraits(.isHeader)
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
            .onScrollGeometryChange(for: CGFloat.self) { max(0, $0.contentSize.height - $0.containerSize.height) } action: { _, new in
                maxOffset = new
            }
            .scrollIndicators(.visible)
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
