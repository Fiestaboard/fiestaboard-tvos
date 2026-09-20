import SwiftUI

/// The glyph face for board flaps.
///
/// Spline Sans Mono is FiestaUI's `--font-mono`, so using it here is what
/// makes the letterforms on the TV the same shapes as in the web viewer.
/// The face is registered from the bundle at launch; if registration fails
/// the monospaced system face stands in rather than the board going blank.
public enum BoardFont {

    public static let familyName = "Spline Sans Mono"

    private static var registered = false

    /// Register the bundled face. Idempotent; safe to call repeatedly.
    public static func registerIfNeeded() {
        guard !registered else { return }
        registered = true
        guard let url = Bundle.main.url(forResource: "SplineSansMono", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    public static func glyph(size: Double) -> Font {
        registerIfNeeded()
        if UIFont(name: familyName, size: size) != nil {
            return .custom(familyName, fixedSize: size).weight(.semibold)
        }
        return .system(size: size, weight: .semibold, design: .monospaced)
    }
}

extension BoardColor {
    public var swiftUI: Color { Color(hex: hex) }
}

extension Color {
    /// `#rrggbb`. Board pigments are the only source, so the parse is strict
    /// and falls back to board black.
    init(hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            self = Color(red: 0x1a / 255, green: 0x1a / 255, blue: 0x1a / 255)
            return
        }
        self = Color(red: Double((value >> 16) & 0xff) / 255,
                     green: Double((value >> 8) & 0xff) / 255,
                     blue: Double(value & 0xff) / 255)
    }
}
