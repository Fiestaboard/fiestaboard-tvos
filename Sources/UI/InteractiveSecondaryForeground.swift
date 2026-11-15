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

/// Keep the platform's passing destructive tint at rest. Its focused pink
/// is too light on the native white plate; the shared light danger token
/// keeps the role red and readable without changing the button's semantics.
private struct InteractiveDestructiveForeground: ViewModifier {
    @Environment(\.isFocused) private var isFocused

    @ViewBuilder func body(content: Content) -> some View {
        if isFocused {
            content.foregroundStyle(Color(token: FiestaTokenValues.Light.destructive))
        } else {
            content
        }
    }
}

extension View {
    func interactiveSecondaryForeground() -> some View {
        modifier(InteractiveSecondaryForeground())
    }

    func interactiveDestructiveForeground() -> some View {
        modifier(InteractiveDestructiveForeground())
    }
}
