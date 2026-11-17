import SwiftUI

/// The material under the viewer's chrome (A4b; D15 (a); DD4).
///
/// 07b draws `tvOS / Viewer overlay` (`250:110554`) and `tvOS / Status chip`
/// (`152:4203`) in three named materials, and this is the one place that
/// picks between them:
/// - **Liquid Glass** on tvOS 26 and later: the system `.glassEffect`, tinted
///   dark so brand text reads over a lit board (HIG: system glass, brand
///   content inside);
/// - **Regular material** below tvOS 26: the D15 (a) interim, because the
///   app keeps its tvOS 18 floor;
/// - **Opaque** under Reduce Transparency: tvOS already dims glass, but 07b
///   asks for an explicitly solid `--card` surface so the board never reads
///   through the words.
enum ViewerMaterial: Equatable, Sendable {
    case liquidGlass
    case regularMaterial
    case opaque

    /// Whether this OS has `.glassEffect` at all.
    static var glassAvailable: Bool {
        if #available(tvOS 26.0, *) { return true } else { return false }
    }

    /// Reduce Transparency always wins; a force (DEBUG shots) picks a named
    /// interim but can't produce glass where the OS has none.
    static func resolve(reduceTransparency: Bool, glassAvailable: Bool, forced: ViewerMaterial?) -> ViewerMaterial {
        if reduceTransparency { return .opaque }
        let wanted = forced ?? (glassAvailable ? .liquidGlass : .regularMaterial)
        if wanted == .liquidGlass && !glassAvailable { return .regularMaterial }
        return wanted
    }

    #if DEBUG
    /// `-fiestaboard.viewerMaterial glass|regular|opaque`. DEBUG only: nothing
    /// in Release reads the launch argument.
    init?(launchArgument: String?) {
        switch launchArgument {
        case "glass": self = .liquidGlass
        case "regular": self = .regularMaterial
        case "opaque": self = .opaque
        default: return nil
        }
    }
    #endif

    /// What a surface actually draws. Reduce Transparency wins here as well
    /// as in `ViewerGlassContainer`, so a surface outside any container (A6b's
    /// standalone chip) is never glass under it (#23 review S1).
    static func effective(explicit: ViewerMaterial?, inherited: ViewerMaterial, reduceTransparency: Bool) -> ViewerMaterial {
        reduceTransparency ? .opaque : (explicit ?? inherited)
    }

    /// DEBUG only: neither CI (tvOS 26.2) nor a current Xcode can run the
    /// pre-26 branch natively, so its shots force it. Nil in Release.
    static var launchForce: ViewerMaterial? {
        #if DEBUG
        ViewerMaterial(launchArgument: UserDefaults.standard.string(forKey: "fiestaboard.viewerMaterial"))
        #else
        nil
        #endif
    }

    /// The glass tint: 07b's "Dark" glass, from the app ground token.
    static var glassTint: Color { Fiesta.Colors.background.opacity(0.55) }

    /// The pre-26 regular material's dark tint (#23 review S3). Stock
    /// `.regularMaterial` lets a bright board through; at this opacity the
    /// muted subtitle keeps 4.5:1 even over white, before the material's own
    /// darkening (`StatusChipFoldInTests`), which is 07b `250:110532`'s neutral dark.
    static let regularTintOpacity = 0.82
    static var regularTint: Color { Fiesta.Colors.background.opacity(regularTintOpacity) }

    /// The overlay subtitle (07b `154:8173`) on this material (TV wrap-up
    /// S-T3, G-1; DD27). Muted over Liquid Glass measured 4.33:1 over a
    /// pure-white board, under the 4.5:1 bar, so on glass only it draws in
    /// --foreground at `glassCaptionOpacity`, which stays a step quieter
    /// than the title. The regular material (6.75) and opaque (7.49) keep
    /// --muted-foreground. Revisit when the designer's glass-tint token ships:
    /// if muted then passes on glass, go back to one token.
    var captionUsesForeground: Bool { self == .liquidGlass }
    static let glassCaptionOpacity = 0.78
    var captionOpacity: Double { captionUsesForeground ? Self.glassCaptionOpacity : 1 }
    var captionColor: Color {
        captionUsesForeground ? Fiesta.Colors.foreground.opacity(captionOpacity) : Fiesta.Colors.mutedForeground
    }

    #if DEBUG
    /// The 07b `tvOS / Viewer overlay` variant this material is drawn as.
    var overlayVariantNode: String {
        switch self {
        case .liquidGlass: return "154:8170"
        case .regularMaterial: return "250:110532"
        case .opaque: return "250:110540"
        }
    }
    #endif
}

extension EnvironmentValues {
    /// What a `ViewerGlassContainer` resolved, for everything inside it —
    /// including the chip A6b plugs into the overlay's chip host.
    @Entry var viewerMaterial: ViewerMaterial = ViewerMaterial.glassAvailable ? .liquidGlass : .regularMaterial
    /// A DEBUG force for shots and tests (see `ViewerMaterial.launchForce`).
    @Entry var viewerMaterialForce: ViewerMaterial? = ViewerMaterial.launchForce
}

/// Groups the viewer's glass so neighbouring shapes blend and morph as the
/// system intends (`GlassEffectContainer` on tvOS 26), and hands the resolved
/// material to everything inside through `\.viewerMaterial`.
struct ViewerGlassContainer<Content: View>: View {
    var spacing: CGFloat = 28
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.viewerMaterialForce) private var force

    var body: some View {
        let material = ViewerMaterial.resolve(reduceTransparency: reduceTransparency,
                                              glassAvailable: ViewerMaterial.glassAvailable, forced: force)
        Group {
            if #available(tvOS 26.0, *), material == .liquidGlass {
                GlassEffectContainer(spacing: spacing) { content }
            } else {
                content
            }
        }
        .environment(\.viewerMaterial, material)
    }
}

extension View {
    /// Draw this view on `material`, in `shape`.
    func viewerSurface<S: InsettableShape>(_ material: ViewerMaterial, in shape: S) -> some View {
        modifier(ViewerSurfaceModifier(material: material, shape: shape, tagsOverlayVariant: false))
    }

    /// Draw this view on the enclosing `ViewerGlassContainer`'s material.
    func viewerSurface<S: InsettableShape>(in shape: S, tagsOverlayVariant: Bool = false) -> some View {
        modifier(ViewerSurfaceModifier(material: nil, shape: shape, tagsOverlayVariant: tagsOverlayVariant))
    }
}

private struct ViewerSurfaceModifier<S: InsettableShape>: ViewModifier {
    let material: ViewerMaterial?
    let shape: S
    let tagsOverlayVariant: Bool
    @Environment(\.viewerMaterial) private var inherited
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let material = ViewerMaterial.effective(explicit: material, inherited: inherited,
                                                reduceTransparency: reduceTransparency)
        surfaced(content, material)
        #if DEBUG
            .figmaNode(material.overlayVariantNode, enabled: tagsOverlayVariant)
        #endif
    }

    @ViewBuilder
    private func surfaced(_ content: Content, _ material: ViewerMaterial) -> some View {
        switch material {
        case .liquidGlass:
            if #available(tvOS 26.0, *) {
                content.glassEffect(.regular.tint(ViewerMaterial.glassTint), in: shape)
            } else {
                regular(content)
            }
        case .regularMaterial:
            regular(content)
        case .opaque:
            // 07b `250:110540` / `250:110504`: --card with a 2 pt --border.
            content
                .background(Fiesta.Colors.surface, in: shape)
                .overlay(shape.strokeBorder(Fiesta.Colors.border, lineWidth: 2))
        }
    }

    private func regular(_ content: Content) -> some View {
        content
            .background(ViewerMaterial.regularTint, in: shape)
            .background(.regularMaterial, in: shape)
    }
}
