# FiestaBoard for Apple TV — Design

**Date:** 2026-09-19
**Status:** Approved, in implementation
**Repo:** `Fiestaboard/fiestaboard-tvos`

## 1. Purpose

A FiestaPanel is a virtual board rendered life-size on a TV. Today that
means opening a URL in the TV's web browser. Many TVs have a bad browser,
some have none, and an Apple TV has none at all.

This app is the portal: find your FiestaBoard on the network, pick a
panel, display it. That is the whole value proposition, and the scope
discipline below exists to protect it.

## 2. Scope

### In

- Discover a FiestaBoard via mDNS, or connect by typed address
- Sign in when the instance has auth enabled; stay signed in
- List the instance's panels; pick one
- Render it full-screen at the correct size, updating live
- Reopen the chosen panel directly on launch
- A settings screen: connection, default panel, sizing, about

### Out (v1, deliberately)

Board editing, pages, schedules, plugins, multi-board switching, an iOS
companion, a top-shelf extension. The app displays; the web app configures.

## 3. Server contract

Everything the app needs already exists in FiestaBoard. No server change
is required to ship v1.

| Endpoint | Auth | Use |
|---|---|---|
| `GET /auth/status` | public | Probe a candidate host; decide whether to sign in |
| `POST /auth/login` | public | `{username, password, remember_me}` → session cookie |
| `GET /panels` | session | List panels (name, grid, TV size) |
| `GET /panel/{ref}` | **public** | Viewer config + board geometry |
| `GET /panel/{ref}/frame` | **public** | Current characters grid + `updated_at` |
| `PATCH /panels/{id}` | session | Re-fit the grid to this TV |

`/panel/` (singular) is exempted from auth by
`AuthMiddleware(extra_public_paths=("/panel/",))` precisely so a TV can
render without a session. `{ref}` accepts either the panel id or its
short code, so `/panel/1` works.

### Auth

Sessions are cookie-based. Login with `remember_me: true` yields a 30-day
token (`_DEFAULT_REMEMBER_ME_TTL_SECONDS`); without it, 7 days. A TV that
demands a password on a Siri Remote every month is a TV people unplug, so:

- Always request `remember_me: true`.
- Store **username and password** in the Keychain, not just the cookie.
- On a 401, attempt exactly one silent re-login before surfacing sign-in.
  One attempt, not a loop — a changed password must fail visibly.

The instance is on the user's LAN over plain HTTP; the cookie's `Secure`
flag is correctly off in that case (`_is_secure_request`). We therefore
permit cleartext HTTP to private hosts only, via a scoped ATS exception
(§9), never a blanket `NSAllowsArbitraryLoads`.

## 4. Architecture

An XcodeGen project (`project.yml`), tvOS 18.0, in three layers.

### `Sources/Core` — no UI framework, no Apple-only interfaces

CI enforces the first half by grep; the second half is discipline, and it
exists because this layer is the Android port target (§10). Interfaces use
plain `async`/`await` and value types — no Combine publishers in
signatures.

- **`FiestaClient`** — `URLSession` + cookie storage over the six endpoints
- **`Discovery`** — a protocol; the tvOS implementation is `NWBrowser` on
  `_http._tcp`, filtered on TXT `product=FiestaBoard`, each candidate then
  confirmed with a `GET /auth/status` probe
- **`BoardGeometry`** — the Swift twin of `panel-scale.ts` / `autofit.py`
- **`BoardTables`** — character codes 0–71 and colors 63–71
- **`BoardLayout`** — pure layout: tile rects, colors, glyphs, as data
- **`PanelStore`** — polling engine (frame 2s, config 10s), auto-dim,
  connection state
- **`Credentials`** — Keychain

### `Sources/Render`

`BoardCanvas`, which paints a `BoardLayout`. Nothing else.

### `Sources/UI`

`FiestaTokens` plus the five screens.

## 5. The shared spec file

`Spec/board-spec.json` holds the constants and test vectors that every
implementation of a FiestaBoard renderer must agree on: tile ratios,
column/row pitch, the character table, the color table, and worked
autofit/scale cases.

This exists because the parity contract is currently prose. `autofit.py`
and `panel-scale.ts` are kept in lockstep by hand-mirrored test cases and
a comment stating they are *"mirrored VERBATIM"* and that *"drift between
the two mirrors must fail one of the suites."* That holds at two twins,
maintained by vigilance. At four — Python, TypeScript, Swift, Kotlin — it
will not.

So the vectors become data, and each language's test suite loads the same
bytes. A drift then fails everywhere at once instead of nowhere.

The file is born here so nothing blocks on review. A follow-up PR to
FiestaBoard `next` offers to move canonical ownership there and point the
two existing twins at it.

### Contents

- `tileRatios`: width `0.70`, gutter `0.145`, radius `0.075` (in tile heights)
- `noteUnitWidthIn`: `24.5`; `noteCols`: 15; `noteRows`: 3; `maxNotesPerAxis`: 8
- `colPitchIn`, `rowPitchIn` derived and asserted
- `characters`: the 72-entry table, with 43/45/51/57/58/61 explicitly blank
- `colors`: codes 63–71 → hex, and the named palette
- `code62`: `degree` | `heart` (note devices get the heart)
- `vectors.autofit`: the cases from both existing suites, verbatim —
  65″→2×4, 43″→1×3, 85″→3×6, 3″→1×1, 55″@21:9→2×3, 55″@9:16→1×7,
  40″@4:3→1×3, clamp at 8
- `vectors.scale`: `panelAutofitScale` cases including the ≤10% stretch
  cap and the shrink-to-fit case

## 6. Rendering

### Why a canvas

An 85″ panel is 45×18 = **810 flaps**. A view per tile is a great deal of
view identity for what is really a grid of rectangles. In a `Canvas`, each
distinct `(character, color)` pair resolves to a `ResolvedText` once —
about 72 of them — and every tile is a rounded rect plus a cached glyph.

Steady state is one redraw per frame change, every ~2 seconds.

### Fidelity

Geometry comes from the constants, not from eyeballing: tile width
`0.70·h`, gutter `0.145·h` on both axes, radius `0.075·h`, board black
`#1a1a1a`, color codes from the table. Glyphs are Spline Sans Mono
Semibold — FiestaUI's mono — so the letterforms match the web viewer.

### Animation

Flip is off by default per panel (`animations_enabled: false`). When on, a
`TimelineView(.animation)` drives one phase value and each tile's flip is
a pure function of `(elapsed, row, col, from, to)` — which makes the
animation math unit-testable, unlike per-view transitions.

**Checkpoint:** measure on real hardware at 45×18 with animation on. If
`Canvas` cannot hold 60fps, fall back to a `CALayer` per tile with
`CATransform3D` — GPU-composited, and CoreAnimation is comfortable with
810 layers. Decide by measuring, not now.

## 7. Sizing

A panel's grid is auto-fit server-side from a diagonal typed into the web
app. An Apple TV cannot know its own physical screen size, so:

**Default — Fit.** Uniform scale so the grid fills the screen, reusing the
viewer's ≤10% stretch rule.

**Offered — Resize for this TV.** When the grid's aspect doesn't suit the
screen, the viewer says so once and offers a re-fit: ask the diagonal
(presets 32–85″ plus custom), preview the result locally via the Swift
`computeAutofitGrid` so the user sees `30×12 → 45×18` before committing,
then `PATCH /panels/{id}`.

That PATCH can return `incompatible_references` — pages authored for the
old grid. The app surfaces it as a plain warning. Silently reshaping
someone's board out from under their pages would be rude.

**Optional — True scale.** Life-size flaps via `panelAutofitScale` with
±15% calibration, accepting black margins.

## 8. Failure behavior

Mirrors the web viewer deliberately:

- Connection lost → **last frame stays up**, small amber dot in the corner,
  retry at the poll cadence. No inner retry: the cadence *is* the retry
  policy, and on a TV doubly so.
- Panel deleted (404) → "This panel no longer exists", with a way back.
- Board never written → blank board, which is correct, not an error.
- `isIdleTimerDisabled` holds the screen awake while viewing.
- Auto-dim is evaluated against the TV's own clock, matching the web viewer.

## 9. Configuration

- Bundle `com.fiestaboard.tv`, display name per §12
- tvOS 18.0, Swift 5 language mode
- `NSBonjourServices`: `_http._tcp` + `NSLocalNetworkUsageDescription`
  (required for `NWBrowser` and for reaching LAN hosts)
- ATS: `NSAllowsLocalNetworking` only — *not* `NSAllowsArbitraryLoads`.
  Local instances are plain HTTP; the public internet is not.

## 10. Android TV (known future, not built)

Native Compose for TV, not a cross-platform rewrite. The shareable surface
is roughly 15–20% — geometry, tables, and client logic — which does not
justify a KMP toolchain or a community tvOS fork of React Native against
an App Store submission.

What makes that port cheap is built now: `board-spec.json` (§5) settles
correctness, and Core's types map 1:1 — `FiestaClient` → OkHttp,
`Discovery` → `NsdManager`, `BoardGeometry`/`BoardTables` → plain Kotlin,
`PanelStore` → ViewModel + Flow, `Credentials` → EncryptedSharedPreferences.
Splitting `BoardLayout` from the painter means the renderer transcribes
too: SwiftUI `Canvas` and Compose `Canvas` are near-identical shapes.

Repo named `fiestaboard-tvos`, leaving `fiestaboard-androidtv` free.

## 11. Testing

**Pure logic** carries the weight, and it is the majority of what can be
wrong: geometry (against `board-spec.json`), character and color tables,
auto-dim windows, URL construction, and the login / 401 / re-login state
machine against a stubbed `URLProtocol`. Fixtures are real `/panel` and
`/panel/{id}/frame` JSON captured from a local instance.

**Render tests** host real SwiftUI screens off-screen and force a layout
pass so their bodies execute, and draw the board to an image at a known
size so sampled pixels assert tile rects and colors — which catches
geometry drift that no unit test can see.

`./build-and-run.sh` puts it on the simulator.

## 12. Naming

Repo `fiestaboard-tvos`, bundle `com.fiestaboard.tv`.

The App Store name is **FiestaBoard for Apple TV** by the user's choice.
Noting the risk once, at the point where it can be changed cheaply: Apple's
marketing guidelines permit referential names, but review has rejected the
analogous "Mac…" construction under 5.2.5, reasoning that indicating
platform compatibility is unnecessary on that platform's own store. The
fallback if rejected is **FiestaBoard**, subtitle "Your panels, on your
TV" — a one-string change in `project.yml`.

## 13. CI

GitHub Actions on `macos-latest`: `xcodegen generate` → `xcodebuild build
test` against a tvOS simulator, plus the layering guard.

macOS runners cannot be emulated by `act`, so this workflow only ever
proves itself on GitHub. Local verification is `xcodebuild` directly; the
first push is the real check. A local pass must not be reported as CI's.

## 14. Possible PRs to FiestaBoard (branch `next`, optional, non-blocking)

1. **`_fiestaboard._tcp` service type** alongside the existing `_http._tcp`
   registration, with version and name in TXT. Browsing every HTTP service
   on the LAN and filtering by TXT works, but a dedicated type is faster
   and a better Bonjour citizen — and `NsdManager` makes that clunkier than
   `NWBrowser` does, so it pays twice once Android TV exists.
2. **Canonical `board-spec.json`** in FiestaBoard, with `autofit.py` and
   `panel-scale.ts` testing against it (§5).
3. **A long-lived device token** for appliance clients, so a TV stores a
   revocable token rather than a password. The MCP bearer token guards only
   `/mcp` paths, so there is nothing to reuse.
