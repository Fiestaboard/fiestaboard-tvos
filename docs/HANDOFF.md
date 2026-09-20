# Handoff notes

This project is designed and planned but not yet built. Nothing has been
implemented: there is no `project.yml`, no Swift, no GitHub repo.

## Read in this order

1. `docs/superpowers/specs/2026-09-19-fiestaboard-tvos-design.md` — the approved design
2. `docs/superpowers/plans/2026-09-19-fiestaboard-tvos.md` — a 15-task TDD implementation plan
3. This file — environment facts, constraints, and known trip hazards

The plan is the instruction set: each task lists exact files, exact interfaces it consumes and produces, the failing test to write, the implementation, and the commit message. Follow it task by task in order — later tasks depend on types defined in earlier ones.

## What you are building

A native tvOS app that finds a FiestaBoard on the local network, signs in, lists its FiestaPanels, and renders a chosen panel full-screen as a live split-flap display. Repo will be `Fiestaboard/fiestaboard-tvos`, bundle `com.fiestaboard.tv`, App Store name "FiestaBoard for Apple TV".

The server it talks to is at `../FiestaBoard` (the FiestaBoard monorepo). Read it for reference — `src/api_server.py` for the endpoints, `src/panels/` for panel models and autofit math, `web/src/lib/panel-scale.ts` and `web/src/components/panel/` for what the web viewer does. You can run a local instance to test against; see its `start-dev.sh` and docker-compose files.

## Verified environment facts — do not rediscover these

- Xcode 27.0 (`/Applications/Xcode-beta.app`), tvOS SDK 27.0
- `xcodegen` 2.46.0 is installed
- An "Apple TV 4K (3rd generation)" simulator is already booted
- **tvOS ships no WebKit.** There is no `WebKit.framework` or `SafariServices.framework` in the SDK. This is the entire reason the board is rendered natively instead of loading the existing web viewer in a web view. Do not attempt a `WKWebView` approach; it cannot work.
- There is no server-side board-image endpoint to fall back on either (`board_html_renderer.py` is MCP-preview-only, not exposed over HTTP)
- The board font TTF is fetchable (verified 200, 118KB): `https://github.com/google/fonts/raw/main/ofl/splinesansmono/SplineSansMono%5Bwght%5D.ttf`
- `gh` is authenticated as `jeffredodd` with `admin:org` and `repo` scopes

## Hard constraints

- `Sources/Core` must never `import SwiftUI` or `import UIKit`. Task 1 adds a CI grep that enforces this. That layer is the future Android TV port target, so also keep Apple-only types out of its public interfaces — plain `async`/`await` and value types, no Combine publishers, no `@Observable` in Core.
- Zero third-party dependencies. No SPM packages, no CocoaPods.
- Board black is `#1a1a1a`, never `#000000`.
- Brand orange is `#f5a623`.
- The app is dark-only. Do not add a light palette.
- ATS: `NSAllowsLocalNetworking` only, never `NSAllowsArbitraryLoads`.
- End every commit message with:
  `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`
- If you open any PR against the FiestaBoard repo, it targets the **`next`** branch, never `main`. (The plan lists three optional such PRs in spec §14 — all non-blocking, do them only after the app works, and ask first.)

## Method

TDD, strictly. For each task: write the failing test, run it and confirm it fails for the expected reason, write the minimal implementation, run it and confirm it passes, commit. One commit per task, using the message the plan supplies.

Run tests with `./build-and-run.sh --test` (created in Task 1). Run the app with `./build-and-run.sh`.

Do not claim a task is done without running the tests and seeing them pass. If something fails, say so with the output.

## Known trip hazards, flagged deliberately

1. **Task 4 contains a planted failure.** The `ISO8601DateFormatter` as first written demands fractional seconds, and the fixture timestamp has none. That is intentional — it is the failing half of a TDD cycle, and Step 6 fixes it with a two-formatter fallback. Do not "fix" it preemptively in Step 4; let the test catch it.

2. **Task 2's glyph table is easy to get off by one.** The `tail` array must be exactly 25 entries (codes 37–61), with `nil` landing precisely on 43, 45, 51, 57, 58 and 61 — those codes are undefined in the official Vestaboard table and render blank. Total table length is 62 (indices 0–61); code 62 is device-dependent and 63–71 are colors.

3. **Task 8's pixel assertions must not be loosened to pass.** An all-zero sample means nothing rendered, which is the bug the test exists to find. If they fail, check that the harness view has an explicit `.frame` and the window is visible at draw time.

4. **`Spec/board-spec.json` must reach the test bundle, not just the app bundle.** The plan's `SpecFixture` tries both, but verify it actually loads — if it `fatalError`s, the folder reference in `project.yml` is wrong.

5. **A performance checkpoint the simulator cannot answer.** Task 8 bets a single SwiftUI `Canvas` holds 60fps at 45×18 (810 flaps) with flip animation on. That needs real hardware. If it can't, the documented fallback is a `CALayer` per tile with `CATransform3D` flips. Measure before changing anything; don't preemptively rewrite the renderer.

## Definition of done

1. All 15 tasks complete, full test suite green
2. The app runs on the simulator and reaches the Connect screen scanning for boards
3. An unsigned Release archive succeeds
4. Repo pushed to `Fiestaboard/fiestaboard-tvos` with the CI workflow green on GitHub

On that last point: **the CI job runs on a macOS runner, which `act` cannot emulate.** Verify locally with `xcodebuild` directly, but do not report a local pass as a CI pass — the first push is the real check.

## Scope discipline

The spec's §2 lists what is deliberately out: board editing, pages, schedules, plugins, multi-board switching, an iOS companion, a top-shelf extension. The app is a portal to panels. Resist adding to it. If you think something is missing, raise it rather than building it.
