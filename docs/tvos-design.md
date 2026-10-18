# Design rules for FiestaBoard on tvOS

The app should look like it came with the Apple TV, and be recognisably
FiestaBoard. Those are not in tension: on tvOS the platform owns *structure*
— focus, row heights, spacing, the lift when something is selected — and the
app owns *content*. The board is the brand. Everything around it gets out of
its way.

This file is the contract. When a screen disagrees with it, the screen is
wrong.

## Principles

1. **Stock first.** If tvOS ships a control for it, use that control. A
   hand-rolled equivalent will be subtly wrong at a distance of ten feet and
   will not match the rest of the system.
2. **Fewer controls.** Every button has to earn its place. Prefer one list of
   choices over a screen of buttons; prefer a selected state over a button
   whose title changes.
3. **Content over chrome.** A panel's board is the most interesting thing on
   any screen it appears on. Show it. Labels explain it; they do not replace
   it.
4. **Brand is an accent.** Amber marks selection, warnings and the icon. It
   is not the structure. Filling every control with brand colour is what made
   this app look like a website.

## Structure

**Browsing content — panels, boards, anything with a picture:**
`Button { … } .buttonStyle(.card)`. `CardButtonStyle` is the tvOS
focus treatment: lift, shadow, and the parallax tilt users already expect.
Lay cards out in a `LazyVGrid` or a row. The panel browser uses two flexible
columns sized from its actual safe-area width, not a hard-coded 1920-point
screen. Keep the full board inside an inset 16:9 preview; the card also names
the hardware style and shows a readable message summary. Returning from the
viewer restores that panel and scroll position. A later refresh must not
move focus away from Settings or Try again.

Top Shelf snapshots reserve a 64-point inset within the 1920×1080 image, so
Home's rounded corners and focus rim never eat the board's edge LEDs/flaps.
The image uses the same charcoal mount as panel cards, with native Home titles.

**Settings-like screens — choices, switches, values:**
`List` of `Section`s, `.listStyle(.grouped)`. Put explanatory copy in the
Section `footer`, not in a `Text` above the control. `SettingsScreen` is the
worked example. Its two-column layout has a short category list and a detail
pane: This Apple TV, Panel appearance, Connection, About & help. Select changes
category; merely moving focus does not replace the controls. TV preferences
and shared panel changes have distinct scope labels. Show only the selected
panel's controls and preview. Calibration draws at true scale in the full
viewport with controls overlaid, so adjusting the value changes what is seen.
Menu pops a detail before leaving settings.

**Single-select:** a row per choice with a `checkmark` on the current one.
Never a button whose title grows a tick.

## Hard rules

- **Never hand-roll focus.** No `.scaleEffect(focused ? …)`, no
  `@FocusState` driving a background colour, no `.buttonStyle(.plain)` with
  manual styling on top. This is not a style preference: a `scaleEffect`
  inside a `ScrollView` grows the view past its layout bounds and the scroll
  view clips it, so a selected item visibly gets its edges cut off.
- **Give focus room.** Anything that lifts on focus needs padding inside its
  scroll container, or the lift is clipped at the edges.
- **Screen edges** use `Fiesta.Metrics.safeInset`. Overscan is still real.
- **Typography** is the system face at system-ish sizes. Spline Sans Mono is
  for board glyphs only — it is the board's voice, not the app's.
- **Colour** comes from `Fiesta.Colors`. Neutral charcoal separates app
  ground (`#0c0c0e`), cards (`#1c1c1e`) and raised content (`#2c2c2e`).
  Keep FiestaBoard amber for accents and warnings. The app deliberately
  stays dark even though tvOS offers Light, Dark and Automatic appearance.
  Native controls own their focus colours.
- **Materials** use the platform's own rendering. Viewer overlays use
  `.regularMaterial` with semantic text colours for legibility over a live
  board. Stock controls supply system focus effects; avoid adding custom
  glow or glass to settings rows. LED lens lighting belongs to the board's
  `Canvas`, independent of the surrounding interface material.
- **Three different blacks, and they are not interchangeable.** The app
  ground is `#0c0c0e`. The viewer's surround is `#000000`, so an OLED can
  switch the pixel off entirely. Board black — an unlit flap — is `#1a1a1a`,
  because a real flap reflects light and pure black reads as a dead panel.
- **Keep accessibility labels.** Anything focusable needs one, and the board
  itself stays `.accessibilityHidden(true)` — 810 flaps is not browsable.
- **Every screen that is not the root handles Menu.** A native navigation
  stack returns to its parent; the settings root's `.onExitCommand` returns
  to the viewer or panel list. Unhandled at the app root, Menu exits to Home.

## Build hazard

Do not build `Binding(get:set:)` inline inside a `Picker` or `Toggle` that
sits inside a `Section`. It puts the Swift type checker past its budget and
the file stops compiling — "unable to type-check this expression in
reasonable time". Declare bindings as explicitly-typed properties:

```swift
private var sizingBinding: Binding<BoardSizing> {
    Binding(get: { model?.sizing ?? .fit }, set: { model?.setSizing($0) })
}
```

A clean build of `SettingsScreen.swift` went from over two minutes to about
three seconds on that change alone.

Measure before repeating that claim about any other file. The only signal
worth acting on is the compiler's; SourceKit's index for this project is not
configured for the generated `.xcodeproj` and reports both missing modules and
type-checking cost that a real build does not have.

```bash
xcrun swiftc -typecheck -sdk "$(xcrun --sdk appletvsimulator --show-sdk-path)" \
  -target arm64-apple-tvos18.0-simulator \
  Sources/UI/*.swift Sources/Core/*.swift Sources/Render/*.swift \
  -Xfrontend -warn-long-expression-type-checking=300 \
  -Xfrontend -warn-long-function-bodies=300
```

That writes nothing into `build/`, so it is safe to run while something else
is building. Today it is silent: the whole 43-file type-check finishes
in about five seconds, and lowering the threshold to 20ms turns up only
`BoardCanvas.body` (31ms), `DiscoveredBoardCard.body` (25ms),
`BoardFont.init(hex:)` (24ms) and `SettingsScreen.body` (23ms) — the last of
those being the file quoted above, now that its bindings are properties.

Note the size of the gap before you factor a view for build time.
`ViewerScreen.body` measures 18ms as it stands and 42ms with all of its layer
properties inlined back into one expression: a real difference, and still
three orders of magnitude short of a hazard whose symptom is a file that will
not compile at all. Split a view up because it reads better. Do not report it
as a compile fix without numbers like these.
