# Revocable TV sign-in

This app implements FiestaBoard TV sign-in protocol version 1. The server's
Account → TV sign-in switch defaults on for supporting servers and respects an
administrator's explicit off setting. When enabled, Sign in offers
**Sign in with a phone or computer** as well as username/password fields.
Scan the QR, or open the displayed address on a phone or desktop and enter the
same code. Both devices must reach the selected board. Explicit browser approval
is required; scanning alone grants no access. Codes expire after ten minutes.

All three methods create the same revocable TV credential. Direct password entry
does not retain the password after the credential is stored. Existing saved
passwords migrate at most once automatically when enrollment is enabled. A failed
or lost exchange requires explicit sign-in; revoked tokens never replay passwords.
Older servers and servers with enrollment off retain legacy password sign-in.
Existing device credentials remain usable if enrollment is later disabled.

Credentials belong to the selected server scheme/host/port/base path and live in
device-only Keychain storage. They expire after 365 days. The TV may view panels
and edit screen size, aspect ratio, calibration, animations and render style.
FiestaBot is unavailable with these credentials. This limitation is deliberate in
protocol v1. Settings shows only permitted shared display edits; panel names,
shared matrix sizing/LED spacing, web viewer backdrops and dim schedules are
managed on the board's web page. Local Apple TV preferences remain available.
Credentials are excluded from discovery and Top Shelf. HTTP LAN
connections transmit credentials without encryption; use a trusted network or HTTPS.

Sign out and Forget clear the local credential and attempt to revoke it on the
server. If offline, use Account → Signed-in devices to revoke remotely. A TV
request using a revoked token fails even for otherwise-public panel endpoints.
Existing anonymous panel URLs remain public; this feature does not make them private.

## Verification

Contract/storage/polling/QR tests are in `DeviceAuthorizationTests`,
`DeviceCredentialTests`, `DeviceSignInModelTests` and `QRCodeTests`; the remote
navigation test is `DeviceSignInUITests`. The normal CI also runs the existing
renderer/navigation suites and produces an unsigned Release archive.

Local simulator execution in the agent workspace is restricted by CoreSimulator
permissions. CI is the simulator execution record. Physical QR scanning at 1080p
and 4K, iPhone/Android/desktop approval against the coordinated server, real remote
and VoiceOver checks, and the 24-hour signage soak remain release qualification work.
No TestFlight upload or physical-device result is claimed by this change.

A native macOS harness also executes the platform-independent Core contract and
credential tests against the same production Swift sources. This checks protocol,
Keychain abstraction failures, migration and generation races; it does not exercise
tvOS Keychain entitlement behavior, focus, or actual device rendering.

The sign-in UX regression suite covers denied/expired code cleanup, public-code
announcements, revoked-token recovery from panel lists, previews and Settings, and rejected
FiestaBot navigation. `DeviceSignInUITests` retains simulator screenshots for the
ready QR/manual-code screen and terminal recovery screens. These fixtures verify
remote navigation and layout; they do not replace a browser-to-TV approval test
against a running server or a physical VoiceOver/QR-scanning check.
