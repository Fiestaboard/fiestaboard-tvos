# FiestaBoard for Apple TV

A native tvOS viewer for FiestaBoard panels. It finds your board on the local network, signs in when needed, and shows a panel as a live split-flap display.

## Requirements

- Xcode with the tvOS simulator runtime
- XcodeGen: brew install xcodegen

Run the app with ./build-and-run.sh. Run tests with ./build-and-run.sh --test.

To connect from the simulator, enter the Mac's LAN address and FiestaBoard's
mapped port in the manual address field, for example `192.168.0.50:4420`.
The app adds the public `/api` prefix itself. A FiestaBoard running in Docker
bridge mode may not appear in Bonjour discovery, so use the manual address
field in that setup. Existing FiestaPi images are also checked through their
`fiestapi.local` host name while newer images advertise a Bonjour HTTP service.

The taco icon and static Top Shelf fallback can be regenerated with
`swift scripts/generate-brand-assets.swift`. When the app loads the panel list,
it caches a current image of each available board for the Apple TV Home Top
Shelf carousel. Put FiestaBoard in the Home top row to see it. Release submission steps are in
[docs/PUBLISHING.md](docs/PUBLISHING.md).

Sources/Core holds board and network logic and must stay free of SwiftUI and UIKit imports. The build script and CI enforce this rule.

The approved [design](docs/superpowers/specs/2026-09-19-fiestaboard-tvos-design.md) and [implementation plan](docs/superpowers/plans/2026-09-19-fiestaboard-tvos.md) describe the app's scope and architecture.
