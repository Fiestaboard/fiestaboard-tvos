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
Lay cards out in a `LazyVGrid` or a row.

**Settings-like screens — choices, switches, values:**
`List` of `Section`s, `.listStyle(.grouped)`. Put explanatory copy in the
Section `footer`, not in a `Text` above the control. `SettingsScreen` is the
worked example.

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
- **Colour** comes from `Fiesta.Colors`. Amber for selection, accents and
  warnings. The app's ground is near-black, not grey: a TV is a very large
  bright surface in a dark room, and theme.css's dark ground — correct on a
  monitor — reads as flat grey at sixty-five inches. `background`, `surface`
  and `surfaceRaised` are deliberately darker than FiestaUI's values for
  that reason; every other token is FiestaUI's untouched.
- **Three different blacks, and they are not interchangeable.** The app
  ground is `#0e0d0b`. The viewer's surround is `#000000`, so an OLED can
  switch the pixel off entirely. Board black — an unlit flap — is `#1a1a1a`,
  because a real flap reflects light and pure black reads as a dead panel.
- **Keep accessibility labels.** Anything focusable needs one, and the board
  itself stays `.accessibilityHidden(true)` — 810 flaps is not browsable.
- **Every screen that is not the root handles `.onExitCommand`.** Unhandled,
  tvOS takes the Menu press and quits the app.

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
