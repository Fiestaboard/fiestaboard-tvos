`tv-sign-in-v1.json` is copied unchanged from FiestaBoard
`tests/fixtures/auth/tv-sign-in-v1.json`, protocol v1, revocable-sign-ins branch,
2026-10-18. All secrets are synthetic test values. Update both native apps from
the canonical server fixture when the contract changes.

`tv-auth-status-v1.json` is byte-identical to the Android TV app's
`core/src/test/resources/tv-auth-status-v1.json` (G3, androidtv #14): `GET
/api/auth/status` as a TV bearer sees it, authored from the hub's
`StatusResponse` until the hub publishes `tests/fixtures/auth/tv-auth-status-v1.json`.
Replace both apps' copies byte for byte then.

`panel-status-v1.json` is the hub-generated panel-status contract (H2b #2454),
copied byte for byte; `SOURCE.json` records its branch, commit and sha256 and a
test checks the hash. Client-only cases and the expected chip copy live in
`panel-status-v1.tv.json`, keyed by case name.

`figma-content/led-all-layers.json` is byte-identical to the Android TV app's
`app/src/test/resources/figma-content/led-all-layers.json` (androidtv `567e96a`,
G10 review round 1; sha256 `dd5d08b7…ec28`): the hub panel and frame (cells and
three canvas layers) behind 07b `150:7480` "LED pixel canvas 64×36" as redrawn
to the DD24 hub model (nodes `280:*`), plus what the Figma frame draws. tvOS
maps it to A6 `I166:195024;149:182603`. Update both apps' copies together.
