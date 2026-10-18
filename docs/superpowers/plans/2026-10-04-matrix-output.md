# Matrix Output Implementation Plan

> Execute inline using superpowers:executing-plans; test-first using
> superpowers:test-driven-development. User requested research, proposal and
> implementation in one pass.

**Goal:** Show FiestaPanel split-flap and LED matrix outputs natively on tvOS.

**Architecture:** Retain the existing panel pull API. Decode additive model and
rich frame fields, rasterize matrix pixels in Core, and share a Canvas between
viewer and cards. Save presentation style through existing panel settings.

**Tech stack:** Swift, Foundation, SwiftUI Canvas, XCTest; zero dependencies.

**Spec:** `docs/superpowers/specs/2026-10-04-matrix-output-design.md`

## Global constraints

Preserve the existing dirty checkout; leave changes uncommitted. Keep Core free
of UI frameworks. Retain tvOS 18 support, 2s/10s polling, authentication, Top
Shelf and signage. Bound dimensions to 256. Unknown/missing style is split-flap.

## Review focus

Legacy servers must not receive style PATCHes. Invalid model dimensions must
not allocate unbounded rasters. Rich-only content and color-only changes must
survive snapshots and previews. Outages retain pixels but clear stale speech.
Matrix displays must not trigger flap resize/calibration actions.

## Task 1: Additive wire models and snapshots

Files: `Sources/Core/Models.swift`, new `Sources/Core/MatrixDisplay.swift`,
`Sources/Core/PanelStore.swift`, `Sources/UI/PanelsModel.swift`,
`Sources/Core/FiestaClient.swift`, `Tests/MatrixDisplayTests.swift`.

Produces: `PanelRenderStyle`, `Panel.renderStyle`, `Panel.supportsRenderStyle`,
`Panel.deviceModelSpec`, `PanelFrame.richCells`, `PanelSnapshot.richCells`,
`PanelPreview.richCells`. Matrix model types decode only the required fields.

- [ ] Add tests for style round-trip, legacy defaults, bounded geometry and rich cells.
- [ ] Run targeted tests; confirm missing style support fails.
- [ ] Implement models, propagate rich frames, add optional `renderStyle` PATCH.
- [ ] Run targeted tests, including outage preservation and wire request assertions.

## Task 2: Native matrix raster and presentation

Files: new `Sources/Core/MatrixRaster.swift`, `Sources/Render/MatrixCanvas.swift`,
`Resources/Matrix/`, `Sources/UI/ViewerScreen.swift`, `ViewerModel.swift`,
`PanelPreviewBoard.swift`, `Tests/MatrixDisplayTests.swift`.

Consumes Task 1; produces `MatrixRaster.make(panel:cells:richCells:)` with
bounded row-major RGB pixels and `MatrixCanvas` shared by viewer and cards.

- [ ] Add failing tests for exact bitmap pixels, colors/backgrounds/icons,
      model dimensions, clipping/padding, viewer sizing and preview dispatch.
- [ ] Vendor upstream font/icon data through apply_patch with provenance/license.
- [ ] Implement rasterization and square-pixel Canvas rendering.
- [ ] Select renderer from panel style; suppress matrix flap resize offer.
- [ ] Run targeted model/raster/render tests.

## Task 3: Settings and handoff

Files: `Sources/UI/SettingsModel.swift`, `SettingsScreen.swift`,
`Tests/SettingsScreenTests.swift`, README and handoff.

Consumes Task 1 style API. Produces style selection saved on the server,
with legacy controls withheld and matrix flap-only actions withheld.

- [ ] Add failing tests for save success, rollback/failure and legacy refusal.
- [ ] Implement style picker and exclude matrix panels from flap-only controls.
- [ ] Update setup and limitations documentation.
- [ ] Run `./build-and-run.sh --test` and review the complete task diff.

## Execution record

Working in place is intentional: a clean worktree would omit the user's large
pending app changes that this feature must preserve and build upon. No automatic
commits, branch changes, or upstream writes. Baseline suite started before edits.

### Restart checkpoint — 2026-10-04

The user requested a restart checkpoint before continuing. Research and design
are complete; product implementation has NOT started. No new commits or upstream
writes. The only files added for this task are this plan, its linked design spec,
and `Tests/MatrixDisplayTests.swift`. All other modified/untracked files predate
this task and belong to the user; preserve them.

Baseline verification: `./build-and-run.sh --test` completed successfully.
The result bundle `build/Logs/Test/Test-FiestaBoardTV-2026.10.04_20-43-19--0700.xcresult`
reports **361 tests passed, 0 failed** (356 unit tests + 5 UI tests). Layering and
brand asset guards passed. Test execution finished promptly, but simulator
diagnostic collection kept xcodebuild alive for several extra minutes. The
completed bundle includes an existing QoS warning in ConnectionStoreTests.
At checkpoint time no xcodebuild process remains running.

The new regression test checks that decoding then encoding a panel preserves
`render_style: led_matrix`. It has NOT been run yet. The targeted test command
was interrupted during approval and did not create a result bundle. Its expected
failure is that today's Panel model ignores render_style, so the encoded value
is nil. First resume step: regenerate the XcodeGen project and run that test to
confirm RED before changing production code.

Upstream research checkout (read-only reference):
`/private/tmp/fiestaboard-research.GESKaA/core`, branch
`feat/split-flap-extended-markup`, commit
`043227c018b9a9d0f6a7a3730a77ec3eeec49bdd`. Local sibling `../FiestaBoard` is on
main, so it does NOT contain the researched stack. Do not switch its branch.
`next` was at `6cb728812e5a0a97d48a788118ee23f82e1c26bc`; modular outputs and LED
support are still an unmerged stacked PR series (#2166–#2197 and related).

Authoritative upstream files:

- `src/panels/models.py` and `src/panels/routes.py`: additive public config and
  frame fields; protected list/PATCH routes remain unchanged.
- `docs/development/output-stream-api.md`: complete TV pull contract, 2s frame /
  10s config cadence, nullable characters, optional rich cells.
- `src/led/matrix.py`: raster layout, clipping/padding, block gutter joining,
  palette, heart/icon colors, monochrome behavior; port relevant behavior.
- `src/fiestaui/led-fonts.json`: both 3x5 and 5x7 bitmap fonts and icons.
- `src/markup_icons.json`: icon palette/labels/fallbacks/aliases.
- `src/fiestaui/provenance.json` and `LICENSE`: vendored source provenance/license.
- `web/src/components/panel/panel-board.tsx`: LED fits the screen; split-flap
  uses physical sizing. Matrix uses the server model's pixel grid.

External FiestaPanel repo main has `output/device-models.json`:
`fiestapanel_led_matrix` = 192x96 pixels, font 5x7, square pixels, dotRatio .82,
offColor #1a1a1a, substrateColor #000000, RGB. `fiestapanel_split_flap` remains
the default. Its output is pull delivery and currently `markup_follows_charset =
False`, so an LED-style FiestaPanel may still send only codes; rich cells are
available for panels observing rich physical outputs. Support both payloads.

Implementation decisions already proposed to the user: shared native matrix
renderer for viewer/cards; additive models and rich snapshot propagation;
server-saved style picker when render_style is supported; legacy split-flap
fallback; matrix always fits, excludes flap calibration/resize prompts; retain
signage/auth/Top Shelf. Matrix transitions are instant in this iteration.

Proceed inline in the existing dirty checkout as the user authorized research,
planning, proposal AND implementation. Do not add extra design approval stops.
Do not commit the user's pending work. Use apply_patch for edits and test-first
for new behavior. No new dependencies. Core must stay free of UI frameworks.
The user has now disabled sandbox restrictions; omit sandbox_permissions from
tool calls. Simulator id: `3AAC4E7C-8279-4E61-B3B6-BD64370C5AFD` (tvOS 27.0).

Suggested first commands:

```sh
xcodegen generate
xcodebuild -project FiestaBoardTV.xcodeproj -scheme FiestaBoardTV -destination 'platform=tvOS Simulator,id=3AAC4E7C-8279-4E61-B3B6-BD64370C5AFD' -derivedDataPath build -only-testing:FiestaBoardTVTests/MatrixDisplayTests -quiet test
```

Then implement Task 1, add meaningful raster/render/settings tests before Tasks
2–3, and run the complete suite. Update this execution record as work progresses.

### Second restart checkpoint — 2026-10-04, approximately 21:08 local

The user explicitly requested another pause/restart. Stop work here until they
resume. This checkpoint supersedes the "implementation has NOT started" text
above. No commits, branch changes, publishing, or upstream writes occurred.

**Completed:** Task 1 implementation. New `Sources/Core/MatrixDisplay.swift`
contains `PanelRenderStyle`, bounded `MatrixDisplay` config (geometry, font,
appearance, monochrome fields), and `MatrixCell` rich tokens. `Models.swift`
preserves the raw style, exposes effective style/support/model, and decodes rich
frame cells clipped to declared dimensions. `PanelStore.swift` carries rich
cells into snapshots and preserves them during outages. `PanelsModel.swift`
carries rich cells into previews. `FiestaClient.updatePanel` accepts an optional
renderStyle and only sends it when explicitly provided.

**Verification:** The original style round-trip test failed at runtime as
expected. Six Task 1 tests then passed with xcodebuild exit 0 at 21:05:24.
They cover legacy/unknown styles, geometry bounds/defaults, rich-only frame
clipping and previews, exact style PATCH body, outage preservation and clearing
speech, plus the original round-trip test. A Swift initializer capture error
was corrected by copying row/col bounds to locals before decode-map closures.
The complete suite has NOT run since these changes.

**Current deliberate RED state:** Four more Task 2 tests were added to
`Tests/MatrixDisplayTests.swift`, then run. The build exited 65 because
`MatrixRaster` does not exist (secondary `.character`/`.color` inference errors
follow from that). The test process has ended. These tests cover exact 3x5/5x7
bitmap pixels, mixed-case rich color, block gutters and monochrome inverse
video, tiles/heart/sun icon/clipping/padding, and actual viewer/card rendering
with matrix sizing and suppression/dismissal of flap resize offers.
No Task 2 production code or vendored assets have been written.

**Next:** Implement `MatrixRaster.make(panel:cells:richCells:)`, returning a
bounded raster with `pixels: [UInt32]` (`0xRRGGBB`, zero for unlit), width and
height. Vendor the upstream font/icon JSON and license/provenance via apply_patch.
Add `MatrixCanvas`, wire it into viewer and card, keep square pixel pitch, honor
model appearance, and suppress/dismiss matrix resize offers. Then Task 3 settings
and docs, full suite, and one final independent code review per executing-plans.
The new bitmap expectation strings were hand-transcribed; check their lengths
and rows against the vendored JSON if they fail after implementation (do not
weaken pixel assertions). The rich lowercase 'a' should be the seven 5-character
rows from that JSON, concatenated exactly.

Upstream raster details confirmed this turn: `grid_layout` uses
`(width + spacingX) / (glyphWidth + spacingX)` and centers leftover margins;
both fonts have 1px horizontal/vertical spacing. Same-background neighbors
join their gutters. Black tiles and black spans are unlit; a monochrome block
has lit background and unlit glyphs. Icons use registry colors and their
fallback when the face has no icon bitmap. Hearts use board red. Model fields
are `geometry.kind/width/height`, top-level `font`, `appearance.pixelShape`,
`dotRatio`, `offColor`, `substrateColor`, and `color.kind/color` for monochrome.
Font JSON and icon registry locations are in the first checkpoint above.

Execution ledger:
`.superpowers/sdd/2026-10-04-matrix-output/progress.md` (ignored scratch).
It records Task 1 complete and Task 2 started. The authorized dirty/uncommitted
workflow takes precedence over the skill's clean-worktree/commit scripts.

**Environment correction:** Despite the prior checkpoint claiming restrictions
were disabled, the active environment is workspace-write and sandboxed
CoreSimulator access failed. The successful runs used `require_escalated`.
The user has said auto approval is enabled. Follow the active permission rules,
not the obsolete instruction to omit sandbox_permissions. The following exact
command is now approved; the log name is historical and reused for all runs:

```sh
xcodegen generate
xcodebuild -project FiestaBoardTV.xcodeproj -scheme FiestaBoardTV -destination 'platform=tvOS Simulator,id=3AAC4E7C-8279-4E61-B3B6-BD64370C5AFD' -derivedDataPath build -only-testing:FiestaBoardTVTests/MatrixDisplayTests -quiet test > /tmp/matrix-task1-red.log 2>&1
```

`./build-and-run.sh --test` is also already approved. `xcresulttool` may itself
need escalation because it writes a TestReport cache outside the workspace.

### Third checkpoint — resumed implementation on 2026-10-04

Tasks 2 and 3 now have production implementations. `MatrixRaster` loads the
vendored bitmap fonts and icon registry, produces bounded RGB pixels, and derives
readable text from the clipped glyph grid. `MatrixCanvas` is shared by viewer and
cards. Matrix panels fit with square pixel pitch and suppress old flap offers.
Settings exposes supported style choices, saves via the existing PATCH, and
withholds flap controls for matrix panels. Panel writes are serialized per panel.

One independent review (gpt-6-astra, read-only) identified four important issues:
rich-only/stale speech, omission of the MIT notice from the bundle, overlapping
settings writes, and unknown icons losing wire fallbacks. All four have code
fixes. Regression tests cover the behavior, including controlled delayed replies
in the settings tests. No additional review pass is needed; execute the tests.

Verification in this session:

- Core-only Swift compilation and five portable executions of the actual raster/
  speech test bodies pass. This includes an unknown-icon regression observed
  failing before the fix. Speech APIs initially failed compilation when absent.
- Corrected the old 3x5 A test fixture: it had 16 hand-transcribed pixels for a
  15-pixel glyph. It now spells out the five exact upstream rows.
- Core and MatrixCanvas type-check against the tvOS 27 SDK for tvOS 18.
- XcodeGen places the extensionless MIT LICENSE explicitly in the app resource
  build phase. Vendored JSON hashes match the recorded upstream files.
- `./build-and-run.sh --test` passed layering/brand guards, then exited 1 because
  CoreSimulator was inaccessible. The targeted test attempt exited 70 because no
  simulator destination was available. Generic build-for-testing exited 65 on
  `sandbox-exec: sandbox_apply: Operation not permitted`, leaving Observation
  macros unavailable. These are environment errors, not passing test results.
- New settings/UI tests have not executed, so their RED/GREEN and runtime
  validation remain pending. The full suite has not passed since implementation.

Active permissions are **workspace-write, approval never**. Do not follow the
obsolete escalation instructions above. No attempt was made to bypass these
restrictions. When simulator access is available, regenerate the project, run
MatrixDisplayTests and SettingsScreenTests, fix any real failures, and run
`./build-and-run.sh --test`. Inspect resource packaging and UI pixel tests.
Keep changes uncommitted as authorized. Logs: `/tmp/matrix-full-suite.log`,
`/tmp/matrix-build.log`, `/tmp/matrix-settings-red.log`; portable harness:
`/tmp/matrix-portable/main.swift` (temporary supplemental checks, not the tvOS
suite). No commits, branch changes, publishing or upstream writes occurred.

### Refinement checkpoint — 2026-10-04

The user requested another check/refinement pass. A fresh independent review
found a cross-panel settings race: resizing A reloaded the complete panel list,
which could overwrite B's newer saved style. Resize now applies only the PATCH
response's panel. `testResizeUpdatesOnlyItsPanelAndPreservesAnotherSavedStyle`
reproduces the stale-list overwrite and covers the fix. This also removes an
unnecessary request and avoids reporting a refresh error after a successful save.

A native macOS ImageRenderer check exposed the wrong default dot shape: omitted
appearance rendered circles, but FiestaPanel's specified default is square.
Only explicit `pixelShape: round` now selects circles. New visual tests cover
square default, explicit round, model off/substrate colors and dot spacing.

Verification after these refinements:

- Seven supplemental settings-logic checks pass, including both delayed-write
  tests from the previous pass and the resize regression. The resize regression
  failed before the fix (style reverted; extra GET), then passed. Harness copies
  SettingsModel without `@Observable` and substitutes navigation/announcement
  boundaries; actual ConnectionStore, FiestaClient and URLProtocol fixtures run.
  This does not verify Observation or tvOS UI behavior.
- Three actual SwiftUI Canvas rendering scenarios pass under macOS ImageRenderer.
  The default-shape sample failed before correction and passed afterward. Model
  colors sampled exactly: off RGB 18/52/86, substrate 171/205/239, lit 255/255/255.
- Five portable raster/speech checks still pass. Core/MatrixCanvas tvOS SDK type
  checking and Swift syntax parsing pass. `git diff --check` passes.
- `./build-and-run.sh --test` remains blocked by CoreSimulator, after successful
  layering/brand checks; log `/tmp/matrix-refine-suite.log`. Full tvOS execution
  remains required before calling this release-ready.

Temporary supplemental harnesses: `/tmp/matrix-settings-refine/` and
`/tmp/matrix-render-refine/`; canonical regressions are in the repository's
SettingsScreenTests and MatrixDisplayTests. No commits or upstream writes.

### Visual polish checkpoint — 2026-10-04

The user approved a darker neutral direction, native materials, cleaner settings
and realistic square/round LEDs, and explicitly requested parallel agents. Two
implementers handled settings and board rendering; the parent handled palette,
viewer surfaces, integration and documentation. A separate read-only review found
no production blocker. Its suggestion to prove the Settings root returns to the
viewer is applied to the new UI test.

- `FiestaTokens`: neutral ground #0c0c0e, surface #1c1c1e and raised #2c2c2e;
  text #f5f5f7 / #aeaeb2. Brand amber and board pigment colors stay independent.
  Dark appearance remains deliberate; tvOS offers Light, Dark and Automatic.
- `ViewerOverlay` and `ViewerMessage`: native `.regularMaterial` with semantic
  primary/secondary text. Stock buttons retain the platform's focus treatment.
- `SettingsScreen`: grouped lists inside a native NavigationStack. Launch,
  display style and dimming remain on the root; setup/calibration/account/help
  have detail pages. Errors appear on each page. Capability checks, pending-write
  guards, matrix exclusions, privacy text and forget confirmation are retained.
  Calibration uses separate named action rows. No SettingsModel changes in this
  visual pass. Three new UI tests cover nested Menu behavior and accessibility.
- `MatrixCanvas`: model-selected square/round dots with a subtle vertical lens
  gradient and two faint, color-batched halo paths. Exact center colors persist;
  light clips to panel bounds. Dense dots below three points, Increase Contrast
  and Reduce Transparency omit decorative lighting. No per-dot views or blur.
- `BoardCanvas`: black faces use reflective #1a1a1a; gutters remain true black.
  Existing physical leaf shading and hinge drawing remain in place. Regression
  tests now express this documented physical contract.

Verification: five portable Core checks and seven supplemental settings-logic
checks pass. The actual MatrixCanvas renders successfully under macOS
ImageRenderer; the parent inspected `/tmp/fiestaboard-refined-led-shapes.png`
(both shapes and new surface swatches). This is a native renderer preview, not
a tvOS app screenshot. UI test sources type-check against the tvOS 27 SDK at
the tvOS 18 target. Supplemental SettingsScreen type-checking passes with State
wrappers manually expanded and Observation removed from a temporary model copy;
it does not prove full macro-enabled compilation. Swift syntax, layering, brand
assets and diff whitespace checks pass.

Rendering-specific checks: 18 native macOS pixel checks pass (16 lighting/flap
checks plus two checks for the no-lighting accessibility painter), after nine
assertions failed before implementation. All three prior matrix appearance
scenarios still pass, including exact custom off/substrate colors. Core and the
unchanged MatrixCanvas source type-check against the tvOS SDK. BoardCanvas pixel
checks use its extracted, unchanged paint code with an AppKit font adapter,
because the full view's State macro cannot run here; lifecycle is not verified.
Artifacts and logs are in `/tmp/fiestaboard-lighting-polish/`, including
`native-board-surfaces.png`, `native-led-detail.png`, `red.log` and `green.log`.
The parent inspected the combined board-surface sheet. Informational warm macOS
ImageRenderer snapshots at 25% lit took 11–13 ms for 192×96 and 39–43 ms for
256×256 with lighting, versus 6 ms and 17–18 ms without; these are not tvOS
frame-rate measurements.

`./build-and-run.sh --test` still exits 1 before test execution because
CoreSimulatorService is inaccessible (connection refused / operation not
permitted). Log: `/private/tmp/settings-ui-refine/full-test.log`. The earlier
macro-plugin sandbox limitation also remains. Actual settings screenshots,
remote focus/Menu behavior and the full suite still require simulator access;
device rendering performance remains a hardware check. No commits or upstream
writes. Temporary supplemental harnesses are not a replacement for tvOS tests.
