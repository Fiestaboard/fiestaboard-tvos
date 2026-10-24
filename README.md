# FiestaBoard for Apple TV

A native tvOS viewer for FiestaBoard panels. It finds your board on the local network, signs in when needed, and shows a panel as a live split-flap or LED matrix display.

[![CI](https://github.com/Fiestaboard/fiestaboard-tvos/actions/workflows/ci.yml/badge.svg)](https://github.com/Fiestaboard/fiestaboard-tvos/actions/workflows/ci.yml)

## Requirements

- Xcode with a tvOS 26 or newer SDK and the tvOS simulator runtime
- XcodeGen: brew install xcodegen

Run the app with ./build-and-run.sh. Run tests with ./build-and-run.sh --test.

## Continuous integration

[GitHub Actions](https://github.com/Fiestaboard/fiestaboard-tvos/actions/workflows/ci.yml)
runs on every pull request and push to `main`, using standard Apple Silicon
`macos-26` runners. These runners are free for this public repository.

- `build-and-test` runs the repository guards, app/render tests, and remote
  navigation UI tests on a tvOS simulator.
- `Release archive` independently builds an unsigned device archive, including
  the Top Shelf extension. It runs even when simulator tests fail.
- The informational Home Top Shelf screenshot test runs on pushes to `main`.
  Use **Actions → CI → Run workflow** and enable `home_ui` to run it on demand.

`main` is protected: changes must use a pull request, be up to date with `main`,
and pass `build-and-test` and `Release archive` from GitHub Actions. No approving
review, code-owner review, or organization-admin approval is required. Contributors
with write access can merge their own PRs once these requirements pass. The rules
also apply to repository admins; force-pushes and deletion of `main` are blocked.
The Home screenshot check remains optional. Test result bundles, including screenshots, are
available as run artifacts for seven days. Open the `.xcresult` bundle in Xcode
to inspect failures. Verbose simulator diagnostic collection is disabled because
it can stall for ten minutes; XCTest assertions and attachments are still saved.

The workflow cancels superseded runs, limits job duration, and uses the runner's
installed Xcode and tvOS runtimes. It checks both SDKs are version 26 or newer.
There are no external Swift packages to cache, and the small app builds from a
clean checkout instead of transferring DerivedData between runners. Signing and
TestFlight uploads are separate from CI; see [publishing](docs/PUBLISHING.md).

## Local development

Start each change on a branch from the latest `main`, commit and push that branch,
then open a pull request targeting `main`. Wait for the two required CI checks
before merging. Keep changes scoped so a failing check is easy to investigate.

Export simulator demos with `bash scripts/export-demo-video.sh source.mov demo.mp4`.
This preserves 60 fps output and retains the original recording. A 30 fps export
discards half the samples of the 80 ms split-flap steps. Run
`bash scripts/test-demo-video-export.sh` to check that 60 distinct source frames
survive the export. Export frame rate is not a measurement of device frame rate;
profile animation on real Apple TV hardware before claiming sustained 60 fps.

To connect from the simulator, enter the Mac's LAN address and FiestaBoard's
mapped port in the manual address field, for example `192.168.0.50:4420`.
Port 4420 is filled in for you when the address is a bare host, or a plain
`http://` host with no port and no path; the app adds the public `/api`
prefix itself. A FiestaBoard running in Docker bridge mode may not appear in
Bonjour discovery, so use the manual address field in that setup. Existing
FiestaPi images are also checked through their `fiestapi.local` host name
while newer images advertise a Bonjour HTTP service.

The taco icon and static Top Shelf fallback are drawn from `TacoMark`, a
30 x 26 grid of flat colours in `Sources/Render/TacoMark.swift`, and can be
regenerated with `./scripts/generate-brand-assets.sh`. Because the mark is
geometry rather than a bitmap, it is exact at every size tvOS asks for;
`scripts/check-brand-assets.swift` fails the build if it ever regresses to a
resampled image.

## Display style

On servers that support panel presentation settings, **Settings → Panel
appearance → Display style** lets you choose Split flap or LED matrix for the
selected panel. The choice is
saved on the server and applies to that panel's other viewers. Older servers
keep the split-flap display and do not show this control.

LED matrices use the server's pixel dimensions, bitmap font and appearance,
with a 192 × 96, 5 × 7 default when no model is provided. The viewer and panel
cards share the same renderer. Rich frames preserve case, colors, block
backgrounds and supported icons; character-code frames also work. Matrices
use square LEDs by default, or round LEDs when specified by the panel model,
with subtle lens shading and a short glow. Increase Contrast or Reduce
Transparency removes that decorative lighting.

LED displays also render pixel-canvas layers supplied by the server's panel
frame endpoint. This requires a FiestaBoard version that includes `layers` in
panel frames; older servers continue rendering text and rich cells as before.
Pixel artwork appears in the viewer, panel cards, Settings previews and Top
Shelf. Layers paint after text in array order. Each layer uses integer `x`, `y`,
`width`, `height` and standard base64 `rgba` containing row-major RGBA bytes.
Alpha zero preserves the underlying pixel; any nonzero alpha replaces its RGB
without blending. Offscreen pixels are clipped without wrapping. Monochrome
models light their configured color when `299R + 587G + 114B >= 127500` and
otherwise clear the pixel.

The receiver processes the first 64 layer entries, with bitmap dimensions from
1 to 256 pixels per axis and exactly four decoded bytes per pixel. Malformed
layers are skipped individually. Missing, null or empty layers clear earlier
artwork on the next successful frame; a connection outage retains the last
frame. The panel's existing display dimensions still bound the visible canvas.

**Settings → This Apple TV → LED matrix** sets the fallback matrix sizing.
When a panel has **Matrix size** configured in FiestaBoard’s panel editor,
that shared choice takes precedence and updates on the next configuration
refresh (about 10 seconds). Older servers and unconfigured panels retain
the local choice:

- **Fill TV** (default) extends the LED field across the screen with unlit LEDs,
  retaining the source message's scale and position. A 192 × 96 panel on a
  16:9 TV gets six extra unlit LED rows above and below its content.
- **Fit panel** preserves the source panel's proportions with black space around it.
- **True LED size** uses the TV diagonal and LED center-to-center spacing in
  millimeters. TV geometry is fixed at 16:9. A panel too large for the TV scales
  down to keep all content visible. Set the diagonal to your actual TV size;
  it cannot be inferred from screen resolution.

All modes preserve square pixel pitch and circular peg shapes. These settings
apply only to this Apple TV; panel cards retain the source proportions. Flap
calibration and resize prompts do not apply to matrices. Night dimming, drift, last-frame
display during outages and Top Shelf navigation still apply.

Matrix frame changes reveal the new message from left to right in whole-character
steps when **Panel appearance → Matrix transitions** is enabled. This follows
the Divoom output's wipe direction, with character boundaries instead of a
continuous curtain. Pegs stay fixed and colors switch directly without opacity
blending. This uses the panel's shared animation setting. Reduce Motion or
disabling transitions makes changes instant. Prepared message images and a
compositor mask avoid repainting every LED on every animation tick.
Choose **Transition style** under **This Apple TV → LED matrix** for character
wipe, row scan, pixel dissolve, or stepped marquee. The effect choice is local
to this TV; the shared panel toggle still enables or disables playback.
Upstream transition effects and custom character-set bitmaps are not implemented. Model dimensions are capped at
256 pixels per axis. The matrix contract and vendored font data were taken
from the upstream output-development stack; see
[the matrix design](docs/superpowers/specs/2026-10-04-matrix-output-design.md)
and [asset provenance](Resources/Matrix/README.md).

The interface stays dark, with neutral charcoal surfaces and native tvOS
controls. Settings has four categories: **This Apple TV**, **Panel appearance**,
**Connection**, and **About & help**. TV preferences stay separate from shared
panel changes. Panel appearance shows the selected panel's preview and offers
flap animation or matrix transitions, resize and full-screen calibration where supported. Settings
opened from a viewer starts with that panel selected.

## Animation review

Large animated split-flap boards prepare a bounded texture atlas when their
geometry or appearance changes. Playback reuses those faces through one shared
animation clock; the clock pauses when the board settles.

The opt-in `AnimationReview` scheme records normal and 810-tile split-flap
transitions plus square and round LED transitions through the app's HTTP viewer,
and a Home-screen card-selection demonstration:

```sh
xcodegen generate
# Capture at 1080p: the 4K simulator capture paths can omit animation samples.
xcrun simctl io booted screenConfig geometry 1920x1080@1
xcodebuild -project FiestaBoardTV.xcodeproj -scheme AnimationReview \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  -collect-test-diagnostics never -resultBundlePath build/AnimationReview.xcresult test
xcrun xcresulttool export attachments --path build/AnimationReview.xcresult \
  --output-path build/AnimationReview-media
```

Use a fresh result-bundle path for each run. These recording tests are skipped
by the ordinary test scheme. For debug profiling, the launch argument
`-fiestaboard.renderProfile YES` writes bounded timing samples to the app's cache
as `flap-pacing.json` and `matrix-preparation.json`. Canvas submission timings
measure simulator work, not physical Apple TV presentation timing. Inspect the
original recording timestamps and decoded motion, not just nominal FPS.
`scripts/check-recording-pacing.py MOVIE --motion START:END` rejects gaps
over 50 ms in a known moving interval before frame-rate conversion can hide
them. Discrete LED effects intentionally hold each hardware step; choose
intervals and limits appropriate to the effect. Restore a 4K simulator with
`xcrun simctl io booted screenConfig geometry 3840x2160@2` after capturing.

## Browsing panels

The panel browser shows two preview cards per row, sized to the TV's available
space. Each card names the display style and shows its current message. Return
from a viewer to keep your place in the list; background refreshes preserve
remote focus. Empty boards and unavailable previews have distinct labels.

## Top Shelf

Loading the panel list publishes an **Available panels** row on Top Shelf,
with one named 16:9 card per available panel. Each card shows the latest
fetched board frame, including split-flap colors and square or round LED
pixels, and opens its panel directly with Select or Play. These are static
snapshots, not live displays. A frame that cannot be fetched shows
**Preview unavailable**; an existing snapshot stays visible while refreshing.
The panel list reuses its existing preview requests, with at most four frames
in flight. Launching directly into a viewer uses the same bounded fetcher.

The manifest and rendered images live in the app group's `Library/Caches/TopShelf`,
the only part of that container tvOS lets the app write. Caches are purgeable,
so the app refreshes every time it comes to the foreground. The extension
reads local panel names and board images only; no address, session, or
credential is shared with it. Sign-out and Forget clear these images, and
late responses from the previous connection cannot republish them.

Two things have to be true before any of this is visible. The app must be in
the **top row of the Home screen** — tvOS asks only that app for Top Shelf
content, and a freshly installed app is never there, so hold Select on the
icon and drag it up. And you must be signed in to a saved board; the app
publishes nothing for a board it is no longer entitled to show. Settings
carries the same instructions for people who do not read this file.

Release submission steps are in [docs/PUBLISHING.md](docs/PUBLISHING.md).

Sources/Core holds board and network logic and is the future Android port
target, so it must stay free of SwiftUI, UIKit, Combine, `@Observable` and
TVServices. `scripts/check-layering.sh` enforces this in CI and in the build
script.

The approved [design](docs/superpowers/specs/2026-09-19-fiestaboard-tvos-design.md) and [implementation plan](docs/superpowers/plans/2026-09-19-fiestaboard-tvos.md) describe the app's scope and architecture.

### OLED care

Settings → This Apple TV → OLED care offers device-local output brightness,
gentle movement, custom night dimming, scheduled black-output rest, periodic
breaks, board position rotation, unavailable-board dim/rest, and an opt-in system
screensaver. The optional OLED question never enables protection. Existing
movement and panel night-dimming preferences migrate unchanged.

Brightness percentages scale app output, not TV hardware brightness. Movement
reserves a safe inset; rotation uses 80% of the available width and height for the
same live board. Reduce Motion pauses continuous movement. Schedules use TV local
time, start inclusively and end exclusively; equal endpoints disable the window.
A remote press resumes scheduled/outage rest for five minutes, or ends a periodic
break and restarts its interval. Rest releases idle inhibition; it is black output,
not standby, and automatic wake is not promised. Device preferences survive sign-out.
These options may reduce OLED wear; physical effectiveness and burn-in prevention
are not established by software tests.

Run the portable Foundation policy suite with `./scripts/test-oled-core.sh` when a
tvOS simulator is unavailable. Native UI and renderer tests remain part of
`./build-and-run.sh --test`.
