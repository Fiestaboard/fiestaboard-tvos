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
    ///   - enabled: `false` records nothing (for shared views tagged only on
    ///     some screens).
    ///   - coversSafeArea: record the frame extended by the safe-area insets,
    ///     for a Screen slot: the slot is the whole 1920×1080 screen while
    ///     the view itself sits inside the 80/60 title-safe (A4a).
    func figmaNode(_ id: String, label: String? = nil, identify: Bool = false,
                   enabled: Bool = true, coversSafeArea: Bool = false) -> some View {
        modifier(FigmaNodeModifier(id: id, label: label, identify: identify && enabled, enabled: enabled,
                                   coversSafeArea: coversSafeArea))
    }
    #else
    @inline(__always)
    func figmaNode(_ id: String, label: String? = nil, identify: Bool = false,
                   enabled: Bool = true, coversSafeArea: Bool = false) -> Self { self }
    #endif
}

#if DEBUG
private struct FigmaNodeModifier: ViewModifier {
    let id: String
    let label: String?
    let identify: Bool
    let enabled: Bool
    let coversSafeArea: Bool

    func body(content: Content) -> some View {
        let probed = content.onGeometryChange(for: CGRect.self) { proxy in
            let frame = proxy.frame(in: .global)
            guard coversSafeArea else { return frame }
            let inset = proxy.safeAreaInsets
            return CGRect(x: frame.minX - inset.leading, y: frame.minY - inset.top,
                          width: frame.width + inset.leading + inset.trailing,
                          height: frame.height + inset.top + inset.bottom)
        } action: { frame in
            if enabled { FigmaGeometryRegistry.shared.record(id, label: label, frame: frame) }
        }
        if identify {
            probed.accessibilityIdentifier("figma:\(id)")
        } else {
            probed
        }
    }
}
#endif
