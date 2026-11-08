import SwiftUI

/// FiestaBoard's dark TV palette: FiestaUI's dark theme tokens, generated
/// from `@fiestaboard/ui` tokens.json (`FiestaTokenValues`, A1 token bridge).
/// The app deliberately chooses dark appearance even when tvOS uses Light or
/// Automatic. Native controls still own their focus treatment and materials;
/// these tokens style the surrounding content. Board pigments are in
/// `BoardColor`, which reads `FiestaTokenValues.Board`.
public enum Fiesta {

    /// The roles screens use, each bound to one FiestaUI token.
    public struct Palette: Equatable, Sendable {
        public var background: TokenColor
        public var surface: TokenColor
        public var surfaceRaised: TokenColor
        public var foreground: TokenColor
        public var mutedForeground: TokenColor
        public var brand: TokenColor
        public var border: TokenColor
        public var destructive: TokenColor
        public var offline: TokenColor

        /// The bindings the 07b frames use: A1 binds --background,
        /// --foreground, --muted-foreground, --primary and --secondary; the
        /// tvOS panel card binds --card.
        public static let tokens = Palette(
            background: FiestaTokenValues.Dark.background,
            surface: FiestaTokenValues.Dark.card,
            surfaceRaised: FiestaTokenValues.Dark.secondary,
            foreground: FiestaTokenValues.Dark.foreground,
            mutedForeground: FiestaTokenValues.Dark.mutedForeground,
            brand: FiestaTokenValues.Dark.primary,
            border: FiestaTokenValues.Dark.border,
            destructive: FiestaTokenValues.Dark.destructive,
            // The amber "lost the board" dot, matching the web viewer.
            offline: FiestaTokenValues.Dark.primary)
    }

    /// What every `Fiesta.Colors` role reads. Always `.tokens` in the app;
    /// tests swap one role for a sentinel to prove a screen reads the token
    /// rather than a literal that happens to equal it (PHASE-4-TV-PLAN §2.1
    /// check 1). Read and written on the main thread only.
    nonisolated(unsafe) public static var palette = Palette.tokens

    public enum Colors {
        /// --primary / --brand, identical in both FiestaUI themes.
        public static let brandHex = FiestaTokenValues.Dark.primary.hex

        public static var brand: Color { Color(token: palette.brand) }
        /// App ground, distinct from the viewer's true-black surround.
        public static var background: Color { Color(token: palette.background) }
        /// Cards and panels, visibly separated from the ground.
        public static var surface: Color { Color(token: palette.surface) }
        /// Raised content; native controls supply their own focused state.
        public static var surfaceRaised: Color { Color(token: palette.surfaceRaised) }
        public static var foreground: Color { Color(token: palette.foreground) }
        public static var mutedForeground: Color { Color(token: palette.mutedForeground) }
        public static var border: Color { Color(token: palette.border) }
        public static var destructive: Color { Color(token: palette.destructive) }
        public static var offline: Color { Color(token: palette.offline) }
    }

    public enum Metrics {
        public static let gutter: CGFloat = 24
        /// Unchanged in A1: the 07b card radius (`PlatformTV.cardRadius`, 24)
        /// lands with the panel cards (A5), so no screen mixes the two.
        public static let cornerRadius: CGFloat = 16
        /// tvOS title-safe inset. Overscan is still real on many sets.
        /// Unchanged in A1: A4a moves every screen to `PlatformTV` at once.
        public static let safeInset: CGFloat = 60
    }

    public enum Text {
        public static let title = Font.system(size: 56, weight: .bold)
        public static let heading = Font.system(size: 38, weight: .semibold)
        public static let body = Font.system(size: 29, weight: .regular)
        public static let caption = Font.system(size: 24, weight: .regular)
    }
}

/// Shared hierarchy for the app's browsing and connection screens.
struct FiestaScreenHeading: View {
    let title: String
    let subtitle: String
    var context: String = "FiestaBoard"

    #if DEBUG
    /// The 07b text nodes a heading is measured against (parity probes).
    /// DEBUG only: a stored id would ship its literal in Release.
    struct FigmaNodes {
        let eyebrow: String
        let title: String
        let subtitle: String
    }
    var figma: FigmaNodes? = nil
    private var probes: (eyebrow: String, title: String, subtitle: String)? {
        figma.map { ($0.eyebrow, $0.title, $0.subtitle) }
    }
    #else
    private var probes: (eyebrow: String, title: String, subtitle: String)? { nil }
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(context)
                .font(Fiesta.Text.caption.weight(.medium))
                .foregroundStyle(Fiesta.Colors.brand)
                .lineLimit(1)
                .figmaNode(probes?.eyebrow ?? "", label: context, enabled: probes != nil)
            Text(title)
                .font(Fiesta.Text.title)
                .foregroundStyle(Fiesta.Colors.foreground)
                .accessibilityAddTraits(.isHeader)
                .figmaNode(probes?.title ?? "", label: title, enabled: probes != nil)
            Text(subtitle)
                .font(Fiesta.Text.caption)
                .foregroundStyle(Fiesta.Colors.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
                .figmaNode(probes?.subtitle ?? "", label: subtitle, enabled: probes != nil)
        }
    }
}

extension Color {
    /// A generated token colour, in sRGB with its alpha.
    init(token: TokenColor) {
        self.init(.sRGB, red: token.red, green: token.green, blue: token.blue, opacity: token.alpha)
    }
}
