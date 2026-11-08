import CoreGraphics

/// Figma "Platform · TV" values for tvOS (`Tokens/platform-tv.json`,
/// generated into `PlatformTVValues`). Points at 1920×1080.
///
/// A1 makes these available; it does not apply them. The safe-area values
/// are the **spec**: A4a first reads the simulator's real `safeAreaInsets`
/// and then either uses `.safeAreaPadding` or these, on every screen at
/// once (the user-complete rule). The card radius lands with the panel
/// cards (A5) and the focus outline with the board previews.
public enum PlatformTV {
    /// tvOS HIG title-safe, left and right.
    public static let safeSide = CGFloat(PlatformTVValues.safeSide)
    /// tvOS HIG title-safe, top and bottom.
    public static let safeTopBottom = CGFloat(PlatformTVValues.safeTopBottom)
    /// Card and platter corner radius.
    public static let cardRadius = CGFloat(PlatformTVValues.cardRadius)
    /// Focus outline on dense board previews.
    public static let focusOutline = CGFloat(PlatformTVValues.focusOutline)
}
