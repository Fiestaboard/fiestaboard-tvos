import CoreGraphics

/// Figma "Platform · TV" values for tvOS (`Tokens/platform-tv.json`,
/// generated into `PlatformTVValues`). Points at 1920×1080.
///
/// The safe-area values are the **spec**. A4a measured the Apple TV 4K
/// root `safeAreaInsets` at exactly 80/60, so screens use the system safe
/// area and these are applied explicitly only inside the full-bleed viewer
/// (overlay bar, status pill, message card); `scripts/insets/check-insets.mjs`
/// guards it. The card radius lands with the panel cards (A5) and the focus
/// outline with the board previews.
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
