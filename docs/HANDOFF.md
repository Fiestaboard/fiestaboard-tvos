# Orientation

## Store media capture follow-up (2026-10-24)

Media run `40123717805` opened the normal resize offer for authored flap grids
whose proportions differ substantially from a TV. The remote automation did
not successfully activate **Later**: the recording retained primary-button
focus and showed viewer controls after a directional press. Reproduce this
interaction with a physical Siri Remote before public launch; check the
viewer movement handler while the resize offer is visible.

Follow-up run `40131427161` reproduced the defect with focused tests: the
model exposed viewer controls during the resize offer, and native Right
could not focus Later. `ViewerModel.showOverlay()` now leaves controls
hidden while the offer owns focus. The regression checks Right → Later →
Select, then ordinary viewer controls after dismissal. Hosted GREEN is
required before merging; physical Siri Remote verification remains unavailable.

Store examples now use distinct TV-fitted grids (24×10 weather, 28×12
departures, 18×8 personal messages), calculated from the existing tile aspect
ratio. This avoids a resizing decision during the showcase and preserves the
different compositions. No production focus behavior was changed.

## Whole-app UX pass (2026-10-18)

Reviewed Connect and sign-in, panel browsing and focus restoration, the viewer
and its controls, local/shared settings, calibration, privacy, FiestaBot, and
Home Top Shelf using source review, simulator navigation and screenshot evidence.
The pass preserves the native layouts and the stationary panel focus treatment.

The pass reproduced these problems:

- Native navigation titles and section labels had insufficient contrast on the
  dark background in simulator captures. Navigation title attributes and
  noninteractive section text now use explicit readable colors; focused control
  colors remain native. Before/after screenshots verified the change.
- A first discovery result took focus from manual address entry. Connect now
  tracks its manual controls as well as board cards. The UI regression holds a
  discovery response until the address field has focus, then releases it. Its
  loopback discovery driver is DEBUG-only and explicitly launch-argument gated;
  real LAN services cannot affect this test.
- Shared display fields lost their meaning once a value replaced the placeholder.
  Names, numeric units/ranges and schedule fields now retain visible labels.
  Save stays focusable while editable fields are disabled; synchronous guards
  prevent duplicate writes. A remote test exercises failure and retry.
- FiestaBot retained a stale error after a successful availability retry, allowed
  sending with stale availability, and presented a loading/failed page list as
  empty. Availability refresh now blocks sending and rejects stale responses.
  Page loading has distinct loading, failure/retry and loaded-empty states;
  cancelling it does not report a chat failure or stop an unrelated reply.

The 14-panel cache-traversal test also exposed an upward move from the second
row reaching Settings while the preceding lazy row was absent. The browser now
recovers that directional escape using its existing scroll/focus task. It keeps
lazy previews and allows normal Settings access from the first available row.

The simulator and automated tests do not establish physical Siri Remote feel,
VoiceOver usability, couch-distance legibility on the target TV, or a long-running
hardware performance/thermal soak. Those remain device acceptance checks. This
pass also does not create the App Store Connect record or distribution signing.

## Visual refresh (2026-10-17)

The panel grid now sizes two columns from its actual safe area. Fixed 860-point
cards previously produced one column on a real tvOS screen despite the old
arithmetic-only unit test passing. `PanelsPresentationTests` exercises six
panels with remote focus, complete last-row visibility, viewer return, and a
reordered foreground refresh while Settings is focused. Initial focus is
restored once per screen; subsequent refreshes must never steal it.

Cards label split-flap / square / round matrix hardware, summarize actual
content (including frames without a plain message, using rendered flap text
instead of server colour markup), and distinguish blank,
loading, and unavailable states. A clipped preview mount prevents SwiftUI's
Canvas background from spilling over one edge. Top Shelf uses a 64-point
inset with complete board proportions. Connection and sign-in share heading
hierarchy; settings has category icons and a compact board/message preview.

Visual evidence is collected in
`build/display-review/FiestaBoard-TV-Design-Review-2026-10-17/`.
`DesignReleaseRegression.xcresult`: 447 passed, zero failures, ten opt-in recording
tests skipped. `TopShelfClockIndependent.xcresult`: Home navigation passed again.
The earlier GitHub informational Home job failed because the fixture's night
schedule appended “Dimmed for the night” to the expected accessibility value.
Its attachment confirmed correct content and focus. This navigation test now
launches with a temporary never-dim override, independent of runner timezone.

## Actual Top Shelf board snapshots (2026-10-17)

The named cards now render the latest fetched frame through `PanelPreviewBoard`,
with animations disabled, into 1920×1080 PNGs. Flaps and square/round LED
hardware share the app's existing renderers. Missing frames use explicit
“Preview unavailable” artwork; loading can retain a matching previous image.
The extension still reads local files and opens the existing panel deep links.

`PanelsModel` publishes its existing frame responses without extra requests.
Foreground reloads the active panel grid, while viewer launches use the same
four-at-a-time fetcher. Per-panel image caching avoids rerendering unchanged
boards. Publication generation, originating client identity, and cancellation
guards reject stale list/frame replies after reload, sign-out, or reconnect.
The behavioral RED tests proved the old brand image and stale-response bugs.
All six `TopShelfPreviewRendererTests` passed in `FinalPreviewRegression2`,
including actual flap pixels, distinct square/round LED corners, changed-frame
image URLs, request reuse, truthful fallback, and rejection of a late frame
after reconnect. The parent session is recording the actual Home cards next.

## Animation and settings verification (2026-10-17)

The v2 review package is in `build/display-review/FiestaBoard-TV-Review-2026-10-17-v2`.
It contains 348/810-tile split-flap clips plus square/round clips for character
wipe, row scan, pixel dissolve, and stepped marquee. LED effects use fixed pegs
and discrete pixel changes, without message-opacity crossfades. All 24 LED
transitions were audited: maximum source gaps 55 ms for intentional 50 ms
wipe/dissolve steps and 20 ms for row scan/marquee. Earlier recurring 4K capture
loss was confirmed by simultaneous recordings; 1080p captures and correct PTS
export remove those long pauses. Physical Apple TV 4K remains unmeasured.

The tvOS native Picker destinations opened empty lists. Settings now uses
explicit choice lists; remote tests verify transitions, matrix sizes, TV
size/LED spacing and split-flap sizes. Focus tests first move up into the
category column's vertical range before moving left. Final unit run:
`FinalUnitGreen.xcresult`, 428 passed, zero failures. A rendering test now uses
isolated SignageSettings so simulator sizing preferences cannot contaminate it.

## Top Shelf cards verified (2026-10-17)

Final visual/runtime check: `TopShelfPreviewCapture2.xcresult` passes. Home shows
actual split-flap Living Room and circular LED Kitchen Review snapshots;
remote focus reaches both, Select opens Kitchen Review with its real frame,
and its controls are reachable. The review package includes the video and
screenshots. Simulator restored to 3840×2160@2 and the live FiestaPi connection.


The shared cache already contained both available panels and valid artwork;
the full-screen carousel hid their names behind the brand poster. Top Shelf
now returns a sectioned row of named 16:9 panel cards. Select and Play both
open the corresponding panel directly. `TopShelfContentTests` verifies the
extension's shared builder, deep links, and empty/purged caches. The actual
Home UI test passed with two fixture cards and opened the second panel's
viewer. This is simulator verification, not a physical Apple TV run.

On tvOS 27, Home's icons and cards belong to `com.apple.HeadBoard`, while
PineBoard exposes scene containers and system status controls. Section titles
are accessibility `Other` elements; cards are `Cell` elements. The UI test
focuses FiestaBoard's actual `Icon` before awaiting cards, so delayed content
loading cannot make it navigate away from the correct app.

## `next` compatibility check (2026-10-05)

Compared app calls with sibling repo `origin/next` at `fddd7a541` (October 5).
Auth, panel list, public config/frame and panel PATCH routes are available.
Found and fixed an actual response-shape mismatch: PATCH returns a flat
`PanelUpdateResponse`, whereas our client fixtures expected `{panel: ...}`.
FiestaClient now decodes the real flat response and still accepts the wrapped
fixture shape. Resize warnings map `page_id`, `page_name`, `surface`, retaining
fallbacks for `id`, `name`, `type`. Five supplemental actual Core/network-fixture
checks pass; two failed on flat responses before the fix. Includes null warnings
and rejection of malformed success responses. Layering/syntax/diff checks pass.
Regression tests are in `FiestaClientTests`; harness is `/tmp/next-compat/`.

The sibling checkout is on `main`; its local `next` ref is stale at `c5f874d03`
(July 21), while `origin/next` has the newer contract. No refs were changed.
Use an instance built from current `next`, create a panel via the web app, then
connect the TV to the host's LAN address and published HTTP port (normally
4420), without an `/api` suffix. A read-only probe of localhost:4420 timed out;
this was source/fixture compatibility checking, not a live integration run.
The tvOS runtime verification limitations below still apply.

## Active work checkpoint (2026-10-04)

Resumed on 2026-10-04. Matrix Tasks 1–3 are implemented, including the native
raster/Canvas, viewer/cards, server-saved style controls, accessibility and docs.
Independent review found four issues; code changes address all four. **tvOS
verification is still pending:** this session's sandbox blocks CoreSimulator
and Swift's Observation macro plugin. The full test script passed layering and
brand guards, then exited before tests could run. Five portable Core raster/
speech checks pass, and Core plus MatrixCanvas type-check against the tvOS SDK.
A follow-up review fixed default dot shape and a cross-panel settings race.
Three macOS Canvas rendering scenarios and seven supplemental settings-logic
checks pass; those settings checks exclude Observation and tvOS navigation.
The actual tvOS settings/UI tests have not run. The user's subsequent approved
visual polish is implemented: neutral dark surfaces, native regular-material
overlays, grouped settings with setup/help details, subtly lit square/round LEDs,
and reflective charcoal flap faces with black gutters. Independent review found
no production blocker; its navigation-test assertion improvement is applied.
The newer **settings redesign checkpoint below** supersedes that settings
layout. Earlier renderer work is recorded in the **visual polish checkpoint** in
[the matrix implementation plan](superpowers/plans/2026-10-04-matrix-output.md),
then run the targeted tests and complete suite with simulator access.
Baseline before this feature: 361 passed; Task 1's six tests passed in the prior
session. Preserve all uncommitted changes; no commits or upstream writes.

### Settings redesign direction (2026-10-04)

The user rejected the first settings polish and approved a stronger redesign:
a spacious two-column screen with This Apple TV, Panel appearance, Connection,
and About & help. Local TV preferences and settings shared by all panel viewers
must be clearly separated. Edit one selected panel with its actual preview;
calibration must show the board at true scale while adjusting it. Opening from
a viewer selects that panel, independently of the launch preference. Retain
native focus, existing settings, error handling, accessibility and capability
checks. This immediate scope is now implemented in `SettingsScreen`,
`SettingsPanelPreview`, `SettingsModel` and the viewer-context accessor in
`AppModel`. The Xcode project has been regenerated to include the new files.

Preview and panel-list requests follow the screen's task lifetime and reject
older replies. Retry cannot silently redirect the app after leaving settings.
Calibration shows the actual board over a true-black full-screen background;
its controls overlay that viewport, and Save returns only after a confirmed
server response. The selected panel remains independent of the launch choice.
Scope labels, loading/retry/empty states, privacy text and existing panel-write
guards are retained. Independent review has no unresolved findings.

Verification: 13 supplemental preview/model/geometry tests and seven existing
settings-write checks pass, using copies without Observation and stubbed app
navigation. Six navigation-context assertions pass using the actual AppModel
flow without Observation/platform sinks. Source typechecks against the tvOS 27
SDK with a tvOS 18 target pass for the five UI tests and for the screen/preview/
render code with temporary State expansion and Observation substitutions.
Syntax, layering, brand assets and whitespace checks pass. These are NOT a full
app build or a tvOS runtime pass. `./build-and-run.sh --test` still exits 1 at
CoreSimulator connection refused; log `/tmp/settings-redesign-suite.log`.
The UI tests now attach screenshots for This Apple TV, Panel appearance and
calibration, but actual screenshots/focus/Menu behavior still need simulator
execution. Useful supplemental scripts: `/tmp/settings-preview-checks.py` and
`/private/tmp/settings-redesign-typecheck.py`. No commits or upstream writes.

The endorsed product direction is settings first, then a few content controls
(choose an existing page, resume its schedule, show a short message), then a
small FiestaBot trial. Content controls and chat are future phases, not shipped
features. Upstream chat already streams responses and approval events, but has
broad administration tools. A scoped TV trial needs explicit board targeting
and server-enforced tool restrictions, plus updated privacy wording. Do not
claim the existing blanket no-third-party statement covers AI-provider traffic.

This file is the context that
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
split-flap or LED matrix display. Bundle `com.fiestaboard.tv`, App Store *listing* name
"FiestaBoard for Apple TV" — the bundle's `CFBundleDisplayName` is the shorter
"FiestaBoard", because 24 characters truncate under the Home-screen icon.

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
- **tvOS does not implement local network privacy.** No permission alert,
  no `Settings › Privacy & Security › Local Network` row, nothing to deny and
  nothing to re-enable. Apple's
  [TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
  carries the platform table — iOS 14, iPadOS 14, macOS 15, visionOS 1 yes;
  **tvOS no**, watchOS no — and its latest revision is 2026-02-17, after
  tvOS 26 shipped, so this is current for the 18.0 deployment target and the
  tvOS 27 SDK. The Apple TV user guide's privacy list has no Local Network
  entry either. Consequences, in the order they bite: `NWBrowser` browsing
  needs no user grant, so a board that never appears is powered off, on
  another network, or unreachable — never a denied permission; no screen may
  send the user to a Settings toggle that does not exist, which is why
  `ConnectScreen`'s empty state offers the manual address instead; and
  `NSLocalNetworkUsageDescription` / `NSBonjourServices` in `project.yml` are
  inert here, kept only so the app is already correct if tvOS adopts what the
  other platforms have. Re-read that table at the next tvOS major bump: the
  day it flips, the Connect empty state owes the user the Settings path, and
  the one place it is missing is the first screen App Review sees.
- The board font is Spline Sans Mono, vendored in `Resources/` under the OFL.
- `xcodegen` generates `FiestaBoardTV.xcodeproj` from `project.yml`. The
  project file is not committed; edit `project.yml`.

## Hard constraints

- `Sources/Core` must never `import SwiftUI` or `import UIKit`;
  `scripts/check-layering.sh` enforces it in CI and in `build-and-run.sh`.
  That layer is the future Android TV port target, so also keep Apple-only
  types out of its public interfaces — plain `async`/`await` and value types,
  no Combine publishers, no `@Observable` in Core. The guard now checks the
  whole list (SwiftUI, UIKit, AppKit, WatchKit, Combine, Observation,
  `@Observable`, TVServices) rather than the first two, and it drops comment
  lines before matching the symbol names so the comments that *explain* the
  rule do not trip it. If it fires, the code is wrong; do not soften the
  pattern.
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

3. **Top Shelf tests must prove dynamic content, not brand-colored pixels.**
   The old amber-coverage heuristic also passed for Home's static fallback.
   `HomeTopShelfUITests.testHomeTopShelfScreenshotForReview` now asserts two
   actual panel cells, moves focus between them, and opens the second panel.
   Query HeadBoard on current tvOS; see the verified checkpoint above.
   `TopShelfContentTests`, `TopShelfPreviewRendererTests`, and
   `TopShelfSnapshotStoreTests` cover the content builder and publication
   independently. The Home test still requires FiestaBoard in the top row;
   CI runs it in a separate informational job.

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

7. **The app-group container's ROOT is not writable on tvOS.** Only
   `Library/Caches` inside it is. `TopShelfSnapshotStore.shared()` built its
   directory at the container root, so `createDirectory` threw on every real
   Apple TV, the manifest was never written, `items()` came back empty, and
   the extension handed Home nothing — which Home answers with the static
   poster, a picture pixel-identical to what a working carousel item shows.
   The feature had therefore never once run, and looked fine. **The simulator
   does not enforce the restriction**, which is why the tests were green the
   whole time; a unit test cannot tell you this and neither can the Mac. Two
   consequences to keep: the path must stay `Library/Caches/TopShelf`, and
   because Caches is purgeable the app republishes on every foreground rather
   than trusting last week's write.
   The wider lesson is the `try?` that hid it — a write to a shared container
   is exactly the kind of failure that has no symptom, so log it.

8. **A `@ViewBuilder` `switch` over an enum does not rebuild when only an
   associated value changes.** `case .viewer(let ref): ViewerScreen(ref: ref)`
   puts `.viewer("a")` and `.viewer("b")` in the *same* branch of the
   generated `_ConditionalContent`, so SwiftUI keeps the view and its
   `@State` alive across the change: `onAppear` does not fire again, and a
   model that second-locks on the store it already has never notices. Every
   Top Shelf jump opened the panel you were already looking at, and a TV with
   a default panel ignored the incoming URL entirely — a TV with no default
   panel worked, which is why it hid for so long. `ViewerScreen` now carries
   an explicit `.onChange(of: ref)` that stops the old model and builds a new
   one. Teardown is spelled out rather than left to `.id(ref)`, deliberately:
   this screen does not trust appearance ordering anywhere else either.

9. **Top Shelf content is only ever asked of the app in the Home screen's top
   row.** A freshly installed app is not there, and there is no API to move
   an icon, so the only fix is telling the user: hold Select on the icon and
   drag it up. This is the second reason nobody had seen the carousel work,
   and it is independent of hazard 7 — fix the write path and a TV whose icon
   sits in the second row still shows nothing. The instruction lives in the
   Settings screen and in the README; if you are debugging "Top Shelf is
   empty", check the row before you check the code.

## Scope

The app is a portal to panels. Deliberately out: board editing, pages,
schedules, plugins, multi-board switching, an iOS companion. Resist adding to
it — raise it rather than building it.

The one thing that has since come in from that list is the Top Shelf
extension, which earns its place because it is a shortcut straight into a
panel from the Home screen rather than a second way to use the app.
