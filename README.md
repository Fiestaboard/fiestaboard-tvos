# FiestaBoard for Apple TV

A native tvOS viewer for FiestaBoard panels. It finds your board on the local network, signs in when needed, and shows a panel as a live split-flap display.

## Requirements

- Xcode with the tvOS simulator runtime
- XcodeGen: brew install xcodegen

Run the app with ./build-and-run.sh. Run tests with ./build-and-run.sh --test.

The tvOS icon and Top Shelf assets can be regenerated with
`swift scripts/generate-brand-assets.swift`. Release submission steps are in
[docs/PUBLISHING.md](docs/PUBLISHING.md).

Sources/Core holds board and network logic and must stay free of SwiftUI and UIKit imports. The build script and CI enforce this rule.

The approved [design](docs/superpowers/specs/2026-09-19-fiestaboard-tvos-design.md) and [implementation plan](docs/superpowers/plans/2026-09-19-fiestaboard-tvos.md) describe the app's scope and architecture.
