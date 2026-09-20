import SwiftUI

/// Brand-filled button with a visible focus state.
///
/// tvOS navigation is focus, not a pointer, so the focused state has to be
/// unmistakable from across a room — scale alone is not enough.
struct FiestaButton: View {
    private let title: String
    private let action: () -> Void
    @FocusState private var focused: Bool

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Fiesta.Text.body.weight(.semibold))
                .padding(.horizontal, 40)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .background(focused ? Fiesta.Colors.brand : Fiesta.Colors.surfaceRaised)
        .foregroundStyle(focused ? Color.black : Fiesta.Colors.foreground)
        .clipShape(RoundedRectangle(cornerRadius: Fiesta.Metrics.cornerRadius))
        .focused($focused)
        .scaleEffect(focused ? 1.04 : 1.0)
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}
