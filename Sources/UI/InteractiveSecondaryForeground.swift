import SwiftUI

/// Secondary copy inside native focusable labels keeps FiestaUI's dark
/// muted token at rest. Native tvOS focus uses a light surface, so its
/// content takes FiestaUI's light foreground token instead. Surrounding
/// captions and footers deliberately do not use this interactive style.
private struct InteractiveSecondaryForeground: ViewModifier {
    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content.foregroundStyle(isFocused
            ? Color(token: FiestaTokenValues.Light.foreground)
            : Fiesta.Colors.mutedForeground)
    }
}

extension View {
    func interactiveSecondaryForeground() -> some View {
        modifier(InteractiveSecondaryForeground())
    }
}
