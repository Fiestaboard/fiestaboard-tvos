import SwiftUI

/// FiestaBoard's dark TV palette: neutral surfaces and a restrained amber
/// brand accent. The app deliberately chooses dark appearance even when
/// tvOS uses Light or Automatic. Native controls still own their focus
/// treatment and materials; these tokens style the surrounding content.
/// Board pigments are defined separately in `BoardColor`.
public enum Fiesta {

    public enum Colors {
        /// --primary / --brand, identical in both FiestaUI themes.
        public static let brandHex = "#f5a623"

        public static let brand = Color(hex: brandHex)
        /// App ground, distinct from the viewer's true-black surround.
        public static let background = Color(hex: "#0c0c0e")
        /// Cards and panels, visibly separated from the ground.
        public static let surface = Color(hex: "#1c1c1e")
        /// Raised content; native controls supply their own focused state.
        public static let surfaceRaised = Color(hex: "#2c2c2e")
        public static let foreground = Color(hex: "#f5f5f7")
        public static let mutedForeground = Color(hex: "#aeaeb2")
        /// --border (dark): foreground at 12%
        public static let border = Color.white.opacity(0.12)
        /// --destructive (dark): oklch(0.7 0.17 29)
        public static let destructive = Color(hex: "#f2705c")
        /// The amber "lost the board" dot, matching the web viewer.
        public static let offline = Color(hex: "#f5a623")
    }

    public enum Metrics {
        public static let gutter: CGFloat = 24
        public static let cornerRadius: CGFloat = 16
        /// tvOS title-safe inset. Overscan is still real on many sets.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(context)
                .font(Fiesta.Text.caption.weight(.medium))
                .foregroundStyle(Fiesta.Colors.brand)
                .lineLimit(1)
            Text(title)
                .font(Fiesta.Text.title)
                .foregroundStyle(Fiesta.Colors.foreground)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(Fiesta.Text.caption)
                .foregroundStyle(Fiesta.Colors.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
