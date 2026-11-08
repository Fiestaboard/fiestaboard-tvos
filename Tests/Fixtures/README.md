`tv-sign-in-v1.json` is copied unchanged from FiestaBoard
`tests/fixtures/auth/tv-sign-in-v1.json`, protocol v1, revocable-sign-ins branch,
2026-10-18. All secrets are synthetic test values. Update both native apps from
the canonical server fixture when the contract changes.

`tv-auth-status-v1.json` is byte-identical to the Android TV app's
`core/src/test/resources/tv-auth-status-v1.json` (G3, androidtv #14): `GET
/api/auth/status` as a TV bearer sees it, authored from the hub's
`StatusResponse` until the hub publishes `tests/fixtures/auth/tv-auth-status-v1.json`.
Replace both apps' copies byte for byte then.
