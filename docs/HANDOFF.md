# Orientation

The app is built and its test suite is green. This file is the context that
is not derivable from the code: why the constraints are what they are, and
the traps that have already cost someone a day.

For what the app is and how to run it, see the [README](../README.md). The
original [design](superpowers/specs/2026-09-19-fiestaboard-tvos-design.md)
and [implementation plan](superpowers/plans/2026-09-19-fiestaboard-tvos.md)
record how it was built and still describe its architecture — but they
describe the plan, not the current state. Where they disagree with the code,
the code is right.

## What it is

A native tvOS app that finds a FiestaBoard on the local network, signs in,
lists its FiestaPanels, and renders a chosen panel full-screen as a live
split-flap display. Bundle `com.fiestaboard.tv`, App Store name "FiestaBoard
for Apple TV".

The server it talks to is the FiestaBoard monorepo at `../FiestaBoard`. Read
it for reference — `src/api_server.py` for the endpoints, `src/panels/` for
panel models and autofit math, `web/src/lib/panel-scale.ts` and
`web/src/components/panel/` for what the web viewer does. Run a local
instance to test against; see its `start-dev.sh` and docker-compose files.

## Environment facts — do not rediscover these

- **tvOS ships no WebKit.** There is no `WebKit.framework` or
  `SafariServices.framework` in the SDK. This is the entire reason the board
  is rendered natively instead of loading the existing web viewer in a web
  view. A `WKWebView` approach cannot work.
- There is no server-side board-image endpoint to fall back on either
  (`board_html_renderer.py` is MCP-preview-only, not exposed over HTTP).
- The board font is Spline Sans Mono, vendored in `Resources/` under the OFL.
- `xcodegen` generates `FiestaBoardTV.xcodeproj` from `project.yml`. The
  project file is not committed; edit `project.yml`.

## Hard constraints

- `Sources/Core` must never `import SwiftUI` or `import UIKit`;
  `scripts/check-layering.sh` enforces it in CI and in `build-and-run.sh`.
  That layer is the future Android TV port target, so also keep Apple-only
  types out of its public interfaces — plain `async`/`await` and value types,
  no Combine publishers, no `@Observable` in Core.
- Zero third-party dependencies. No SPM packages, no CocoaPods.
- Board black is `#1a1a1a`, never `#000000` — a real flap reflects light.
  The viewer's *surround* is true black, for OLED; the flaps are not.
- Brand amber is `#f5a623`. It is spelled out in `Fiesta.Colors.brandHex` and
  again in `TacoMark.Ink.brand`, because the icon generator compiles TacoMark
  without the UI layer. `FiestaTokensTests` fails if they drift.
- The app is dark-only. Do not add a light palette.
- ATS: `NSAllowsLocalNetworking` only, never `NSAllowsArbitraryLoads`.
- End every commit message with:
  `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`
- If you open any PR against the FiestaBoard repo, it targets the **`next`**
  branch, never `main`.

## Method

TDD. Write the failing test, run it and confirm it fails for the expected
reason, write the implementation, run it and confirm it passes, commit.

Run tests with `./build-and-run.sh --test`. Run the app with
`./build-and-run.sh`. Do not claim work is done without running the tests and
seeing them pass. If something fails, say so with the output.

## Known trip hazards

1. **`Spec/board-spec.json` must reach the test bundle**, not just the app
   bundle. `SpecFixture` tries both. If it `fatalError`s, the folder
   reference in `project.yml` is wrong.

2. **The render tests' pixel assertions must not be loosened to pass.** An
   all-zero sample means nothing rendered, which is the bug the test exists
   to find. If they fail, check that the harness view has an explicit
   `.frame` and the window is visible at draw time.

3. **`HomeTopShelfUITests` drives the real tvOS Home screen** and samples
   pixels out of a screenshot. It depends on which icon Home last focused, so
   it can fail when it runs after other simulator tests and pass in
   isolation. Treat a lone failure there as suspect before treating it as a
   regression; the deterministic half of that behaviour is covered by
   `TopShelfPreviewRendererTests`.

4. **`RenderHarness.image` paints nothing below about 100pt.** On this
   simulator a hosting window smaller than roughly 100 points renders
   empty, so a pixel test of a small view samples all zeroes and passes
   whatever it asserts — the precise failure those tests exist to catch.
   Every pre-existing pixel test uses 200-240pt tiles, which is why nobody
   had hit it. To test something small, render at TV size pinned
   top-leading and crop; `smallBoardImage` in `Tests/BoardCanvasTests.swift`
   does exactly that.

5. **A performance checkpoint the simulator cannot answer.** The renderer
   bets a single SwiftUI `Canvas` holds 60fps at 45×18 (810 flaps) with flip
   animation on. That needs real hardware. If it cannot, the documented
   fallback is a `CALayer` per tile with `CATransform3D` flips. Measure
   before changing anything; do not preemptively rewrite the renderer.

6. **CI runs on a macOS runner, which `act` cannot emulate.** Verify locally
   with `xcodebuild` directly, but do not report a local pass as a CI pass.

## Scope

The app is a portal to panels. Deliberately out: board editing, pages,
schedules, plugins, multi-board switching, an iOS companion. Resist adding to
it — raise it rather than building it.

The one thing that has since come in from that list is the Top Shelf
extension, which earns its place because it is a shortcut straight into a
panel from the Home screen rather than a second way to use the app.
