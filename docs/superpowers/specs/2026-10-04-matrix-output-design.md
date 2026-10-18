# Matrix output on Apple TV

## Intent and current state

Display FiestaBoard panels as split flaps or LED matrices on Apple TV, following
the panel's saved presentation and retaining discovery, authentication, default
panel launch, Top Shelf links, accessibility, dimming and drift.

The app checkout has extensive uncommitted reliability, accessibility and release
work. Preserve it. GitHub has no open tvOS issues or PRs as of 2026-10-04. Release
signing/submission and real-device performance checks remain pending.

## Upstream research

`next` is at `6cb728812e5a0a97d48a788118ee23f82e1c26bc`; matrix and output
modularization are still an open PR stack, not merged into that branch. Research
uses the stack tip `feat/split-flap-extended-markup`, including
[panel presentation PR #2185](https://github.com/Fiestaboard/FiestaBoard/pull/2185),
[output extraction #2187](https://github.com/Fiestaboard/FiestaBoard/pull/2187), and
[board-aware panel tools #2192](https://github.com/Fiestaboard/FiestaBoard/pull/2192).

[FiestaPanel](https://github.com/Fiestaboard/fiestaboard-output--fiestapanel)
is a pull output: core stores frames; the TV still reads `/api/panel/{ref}` every
10 seconds and `/api/panel/{ref}/frame` every 2 seconds. No output plugin runs on
Apple TV. Output settings, device transport and scheduling belong to the server.
Config adds `render_style`, `device_model`, and `device_model_spec`; frames add
optional `cells` (char/color tokens with color, background and icon). These are
additive. FiestaPanel itself currently projects split-flap codes even in LED
style, while panels viewing rich physical outputs can receive rich cells.

## Approach

Extend the existing pull viewer. A separate native matrix renderer uses the
server's pixel geometry, font and appearance; default FiestaPanel LED geometry
is 192 × 96 with 5 × 7 glyphs. Vendor the upstream bitmap font and icon registry
with provenance and license, without adding dependencies. Matrix rasterization
stays in Core, rendering in Render, and presentation/settings in UI.

Alternative approaches are server-generated images (no current endpoint), or a
web viewer (tvOS has no WebKit). Both would require a different upstream or
platform contract. The pull viewer already exists and supports older servers.

## Behavior

- Missing or unknown style defaults to split-flap. Explicit LED style selects
  matrix rendering even if the model is absent; use the FiestaPanel default.
- Decode model fields needed for pixels/font/appearance. Limit pixel dimensions
  to 1–256 and bound frame traversal to the declared grid.
- Prefer rich cells for LED rendering; fall back to character codes, honoring
  code 62. Clip/pad to the model's glyph grid as upstream does. Black is unlit;
  colored spans, joined block gutters, mixed case and icons retain their meaning.
- Use the same matrix renderer for panel cards and the viewer. Keep the last
  good frame on an outage, clear stale speech, and recover through existing
  authorized polling. Config changes switch style without relaunching.
- Matrix sizing always fits square pixels to available space. Do not offer
  flap resizing or calibration based on a matrix's aspect ratio.
- Settings offers split-flap/LED style only for panels whose response includes
  `render_style`, saving via the existing PATCH endpoint. Old servers do not
  receive an unsupported field. Explain that this preference belongs to the
  panel and therefore applies to its other viewers.
- Continue instant matrix frame changes in this iteration; keep split-flap
  animation behavior. Do not claim parity with upstream LED transition effects.

## Validation and delivery

Test legacy/default config, style PATCH, bounds, codes and rich tokens, glyph
pixels/colors/icons, model geometry, preview/viewer dispatch, style changes,
outages and matrix sizing. Run the complete tvOS test suite and layering/asset
guards. Review the integration separately. Update README and handoff with setup
and limitations. Leave all user changes intact and leave the result uncommitted
for review; do not publish or modify upstream repos.
