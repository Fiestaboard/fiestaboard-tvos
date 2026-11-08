import SwiftUI

extension View {
    #if DEBUG
    /// Names this view after a Figma node for parity probes
    /// (PHASE-4-TV-PLAN §2.1): its global frame and `label` are recorded in
    /// `FigmaGeometryRegistry` on every geometry change.
    ///
    /// - Parameters:
    ///   - id: the Figma node id, e.g. a Screen slot's `I166:147296;149:182603`.
    ///   - label: the text the node shows, for the text probe.
    ///   - identify: also set `accessibilityIdentifier("figma:<id>")` so
    ///     XCUITest can find the view. Off by default: on a real screen it
    ///     would replace an identifier other UI tests may query.
    ///
    /// Compiled out of Release, where it returns `self` unchanged.
    func figmaNode(_ id: String, label: String? = nil, identify: Bool = false) -> some View {
        modifier(FigmaNodeModifier(id: id, label: label, identify: identify))
    }
    #else
    @inline(__always)
    func figmaNode(_ id: String, label: String? = nil, identify: Bool = false) -> Self { self }
    #endif
}

#if DEBUG
private struct FigmaNodeModifier: ViewModifier {
    let id: String
    let label: String?
    let identify: Bool

    func body(content: Content) -> some View {
        let probed = content.onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            FigmaGeometryRegistry.shared.record(id, label: label, frame: frame)
        }
        if identify {
            probed.accessibilityIdentifier("figma:\(id)")
        } else {
            probed
        }
    }
}
#endif
