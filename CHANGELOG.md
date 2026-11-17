# Changelog

FiestaBoard for Apple TV. The newest release is first. Its heading must match `MARKETING_VERSION`
in `project.yml` (`A12ReleaseReadinessTests`). The App Store build number, and any patch version
such as 1.0.1, is assigned at upload by `scripts/app-store-release.py` (docs/PUBLISHING.md).

## 1.0 (unreleased universal TV release; the App Store's 1.0, build 2.1, was rejected: O10)

Built to the universal TV design (07b) alongside the Android TV app.

- **Connect:** finds your FiestaBoard hub on the network or takes its address. Approve the TV from
  your phone (QR or code), which shows "Approved by …" and the name the hub will use for this TV,
  or sign in with your hub password. Each TV's sign-in is revocable and kept in the Keychain; Sign
  out and Forget revoke it on the hub.
- **Your panels:** FiestaPanel displays with previews, an open-at-launch panel, and deep links.
- **Viewer:** full-screen split-flap and LED matrix panels: animated flaps, rounded LED dots (0.15
  of the dot), pixel canvases over cells, matrix transitions, note arrays drawn as separate Notes,
  and a "Resize for this TV" offer for grids that don't suit the screen. The board fills the screen
  at 1920 wide, and the controls sit inside the 80 / 60 pt title-safe area.
- **Controls:** Liquid Glass on tvOS 26 and later, the regular material before it, and an opaque
  surface under Reduce Transparency.
- **Status:** the panel's status chip (schedule, override, silence, paused) on the hub's clock, and
  "Hub unreachable · showing the last update" while the hub can't be reached.
- **Top Shelf:** previews of your panels, with the status in the system's own text.
- **OLED care:** brightness, movement, night dimming, scheduled rest, what to do when the hub can't
  be reached, and whether the Apple TV screen saver may take over.
- **Settings:** This Apple TV, Panel appearance, Connection and About & help, with the Home screen
  shortcut, Screen protection, Privacy and Licenses pages.
- **Accessibility:** VoiceOver reads the board and announces status changes once; follows Reduce
  Motion, Reduce Transparency, Increase Contrast and Bold Text.
- **Notices:** the Licenses page lists every bundled notice, including the taco artwork credit.
