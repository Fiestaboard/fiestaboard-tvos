import SwiftUI

/// FiestaUI's design tokens, transcribed for tvOS.
///
/// `@fiestaboard/ui` is a React package and tvOS ships no WebKit, so the
/// package cannot run here — but its token VALUES can, and this file is the
/// compatibility seam. Values come from theme.css, converted from oklch to
/// sRGB. When FiestaUI moves a token, this file is the one that changes.
///
/// Dark only: a TV lives in a dark room, an Apple TV app is conventionally
/// dark, and the viewer uses OLED black regardless. A light palette
/// would be a theme switcher nobody would ever touch.
///
/// **The three surface tokens deliberately depart from theme.css.** Every
/// other value here is FiestaUI's. Those three are darker, because a
/// browser window is a small bright rectangle in a lit room and a TV is a
/// very large one in a dark room: theme.css's dark ground is correct on a
/// monitor and reads as flat grey across sixty-five inches, which is not
/// what it looks like on the web and not what an Apple TV app looks like
/// either. The FiestaUI value each one came from is recorded beside it, so
/// the relationship between them — and the warm hue they all share — is
/// kept rather than lost.
public enum Fiesta {

    public enum Colors {
        /// --primary / --brand, identical in both FiestaUI themes.
        public static let brandHex = "#f5a623"

        public static let brand = Color(hex: brandHex)
        /// The app's ground. Darkened from --background (dark),
        /// oklch(0.145 0.004 73) / #1c1a18. Still not the viewer's true
        /// black: that one is #000000 so an OLED can switch the pixel off,
        /// and the two are not interchangeable.
        public static let background = Color(hex: "#0e0d0b")
        /// Cards and panels. Darkened from --card (dark),
        /// oklch(0.195 0.004 73) / #262320.
        public static let surface = Color(hex: "#181613")
        /// The lifted state. Darkened from --accent (dark),
        /// oklch(0.225 0.004 73) / #2d2a26.
        public static let surfaceRaised = Color(hex: "#221f1b")
        /// --foreground (dark): oklch(0.965 0.003 73)
        public static let foreground = Color(hex: "#f5f3f1")
        /// --muted-foreground (dark): oklch(0.725 0.004 73)
        public static let mutedForeground = Color(hex: "#aba7a2")
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
        public static let title = Font.system(size: 64, weight: .bold)
        public static let heading = Font.system(size: 38, weight: .semibold)
        public static let body = Font.system(size: 29, weight: .regular)
        public static let caption = Font.system(size: 24, weight: .regular)
    }
}
