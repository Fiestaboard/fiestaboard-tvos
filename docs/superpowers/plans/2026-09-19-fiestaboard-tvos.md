# FiestaBoard for Apple TV Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native tvOS app that finds a FiestaBoard on the local network, signs in, lists its FiestaPanels, and renders a chosen panel full-screen as a live split-flap display.

**Architecture:** Three layers under one XcodeGen project. `Sources/Core` is pure logic with no UI framework and no Apple-only interfaces (it is the future Android port target); `Sources/Render` paints a precomputed layout onto a SwiftUI `Canvas`; `Sources/UI` holds the design tokens and five screens. Board correctness — tile geometry, character and color tables, autofit math — is pinned by `Spec/board-spec.json`, a language-neutral vector file that this app's tests and, later, FiestaBoard's Python and TypeScript twins all assert against.

**Tech Stack:** Swift 5 / SwiftUI / tvOS 18.0, XcodeGen 2.46, XCTest, `Network.framework` (`NWBrowser`) for mDNS, GitHub Actions on `macos-latest`.

**Spec:** `docs/superpowers/specs/2026-09-19-fiestaboard-tvos-design.md`

## Global Constraints

- Platform tvOS 18.0, `SWIFT_VERSION: "5.0"`, bundle id `com.fiestaboard.tv`, display name `FiestaBoard for Apple TV`.
- `Sources/Core` must never `import SwiftUI` or `import UIKit`. CI greps for this and fails the build.
- `Sources/Core` public interfaces use plain `async`/`await` and value types. No Combine publishers, no `@Published`, no `ObservableObject` in Core signatures — those belong to `Sources/UI`.
- Zero third-party dependencies. No SPM packages, no CocoaPods.
- ATS: `NSAllowsLocalNetworking: true` only. Never `NSAllowsArbitraryLoads`.
- Tile geometry is fixed: tile width `0.70·h`, gutter `0.145·h` both axes, corner radius `0.075·h`, where `h` is tile height.
- Note pitch: `NOTE_UNIT_WIDTH_IN = 24.5`, 15 cols × 3 rows per block, `MAX_NOTES_PER_AXIS = 8`.
- Board background black is `#1a1a1a`, never pure `#000000`.
- Brand orange is `#f5a623` in both light and dark. The app is dark-only.
- Never name or reference any other app in this repository, its commits, or its docs.
- Every commit message ends with `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`.
- PRs to the FiestaBoard repository target the `next` branch, never `main`.

---

### Task 1: Project skeleton, build script, CI

**Files:**
- Create: `project.yml`, `Info.plist`, `Sources/UI/FiestaBoardApp.swift`, `Sources/Core/CoreMarker.swift`, `Tests/SmokeTests.swift`, `build-and-run.sh`, `.github/workflows/ci.yml`, `scripts/check-layering.sh`, `README.md`

**Interfaces:**
- Consumes: nothing
- Produces: a buildable `FiestaBoardTV` scheme with a `FiestaBoardTVTests` unit-test bundle; `scripts/check-layering.sh` exits non-zero on a UI import in Core.

- [ ] **Step 1: Write `project.yml`**

```yaml
name: FiestaBoardTV
options:
  bundleIdPrefix: com.fiestaboard
  createIntermediateGroups: true

settings:
  base:
    MARKETING_VERSION: "1.0"
    CURRENT_PROJECT_VERSION: "1"
    SWIFT_VERSION: "5.0"
    CODE_SIGN_STYLE: Automatic

targets:
  FiestaBoardTV:
    type: application
    platform: tvOS
    deploymentTarget: "18.0"
    sources:
      - path: Sources/Core
      - path: Sources/Render
      - path: Sources/UI
      - path: Spec
        type: folder
    info:
      path: Info.plist
      properties:
        CFBundleDisplayName: FiestaBoard for Apple TV
        NSLocalNetworkUsageDescription: FiestaBoard finds your board on this network so your TV can show its panels.
        NSBonjourServices: ["_http._tcp"]
        NSAppTransportSecurity:
          NSAllowsLocalNetworking: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.fiestaboard.tv
        PRODUCT_MODULE_NAME: FiestaBoardTV
        TARGETED_DEVICE_FAMILY: "3"
        GENERATE_INFOPLIST_FILE: NO
        ASSETCATALOG_COMPILER_APPICON_NAME: "App Icon & Top Shelf Image"

  FiestaBoardTVTests:
    type: bundle.unit-test
    platform: tvOS
    deploymentTarget: "18.0"
    sources:
      - path: Tests
    dependencies:
      - target: FiestaBoardTV
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES

schemes:
  FiestaBoardTV:
    build:
      targets:
        FiestaBoardTV: all
        FiestaBoardTVTests: [test]
    test:
      targets: [FiestaBoardTVTests]
      gatherCoverageData: true
    run:
      config: Debug
```

`Spec` is declared `type: folder` so `board-spec.json` is copied into the
bundle as a resource and the tests can load it at runtime.

- [ ] **Step 2: Write `Info.plist`**

An empty-dict plist; XcodeGen merges the `info.properties` above into it.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
```

- [ ] **Step 3: Write the app entry point and a Core marker**

`Sources/UI/FiestaBoardApp.swift`:

```swift
import SwiftUI

@main
struct FiestaBoardApp: App {
    var body: some Scene {
        WindowGroup {
            Text(CoreMarker.greeting)
        }
    }
}
```

`Sources/Core/CoreMarker.swift`:

```swift
import Foundation

/// Placeholder so Sources/Core compiles before Task 2 lands. Deleted in Task 2.
public enum CoreMarker {
    public static let greeting = "FiestaBoard"
}
```

- [ ] **Step 4: Write the smoke test**

`Tests/SmokeTests.swift`:

```swift
import XCTest
@testable import FiestaBoardTV

final class SmokeTests: XCTestCase {
    func testCoreIsLinked() {
        XCTAssertEqual(CoreMarker.greeting, "FiestaBoard")
    }
}
```

- [ ] **Step 5: Write the layering guard**

`scripts/check-layering.sh`:

```bash
#!/usr/bin/env bash
# Sources/Core is the Android port target: it must stay free of UI frameworks.
set -euo pipefail
cd "$(dirname "$0")/.."

if grep -rn "import SwiftUI\|import UIKit" Sources/Core 2>/dev/null; then
  echo "LAYERING VIOLATION: UI framework imported in Sources/Core (see above)." >&2
  exit 1
fi
echo "Layering OK: Sources/Core is UI-framework-free."
```

`chmod +x scripts/check-layering.sh`.

- [ ] **Step 6: Write `build-and-run.sh`**

```bash
#!/usr/bin/env bash
# Build FiestaBoard for Apple TV and launch it on a tvOS simulator.
# Usage: ./build-and-run.sh [--test]
set -euo pipefail
cd "$(dirname "$0")"

./scripts/check-layering.sh

command -v xcodegen >/dev/null 2>&1 && xcodegen generate

DEVICE=$(xcrun simctl list devices available | grep -m1 "Apple TV" | sed -E 's/^ *([^(]+) \(.*/\1/' | xargs)
if [ -z "${DEVICE:-}" ]; then
  echo "No Apple TV simulator found. Xcode > Settings > Components > tvOS Simulator." >&2
  exit 1
fi
echo "Using simulator: $DEVICE"

DEST="platform=tvOS Simulator,name=$DEVICE"

if [ "${1:-}" = "--test" ]; then
  xcodebuild -project FiestaBoardTV.xcodeproj -scheme FiestaBoardTV \
    -destination "$DEST" -derivedDataPath build -quiet test
  exit 0
fi

xcodebuild -project FiestaBoardTV.xcodeproj -scheme FiestaBoardTV \
  -destination "$DEST" -derivedDataPath build -quiet build

APP_PATH=$(find build/Build/Products -name "FiestaBoardTV.app" -type d | head -1)
xcrun simctl boot "$DEVICE" 2>/dev/null || true
open -a Simulator 2>/dev/null || true
xcrun simctl install "$DEVICE" "$APP_PATH"
xcrun simctl launch "$DEVICE" com.fiestaboard.tv
```

`chmod +x build-and-run.sh`.

- [ ] **Step 7: Run the tests to verify the skeleton builds**

Run: `./build-and-run.sh --test`
Expected: PASS — one test, `testCoreIsLinked`.

- [ ] **Step 8: Write the CI workflow**

`.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build-and-test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.app || xcode-select -p

      - name: Layering guard
        run: ./scripts/check-layering.sh

      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Generate project
        run: xcodegen generate

      - name: Resolve a tvOS simulator
        id: sim
        run: |
          NAME=$(xcrun simctl list devices available | grep -m1 "Apple TV" | sed -E 's/^ *([^(]+) \(.*/\1/' | xargs)
          if [ -z "$NAME" ]; then echo "No Apple TV simulator on this runner." >&2; exit 1; fi
          echo "name=$NAME" >> "$GITHUB_OUTPUT"

      - name: Build and test
        run: |
          xcodebuild -project FiestaBoardTV.xcodeproj \
            -scheme FiestaBoardTV \
            -destination "platform=tvOS Simulator,name=${{ steps.sim.outputs.name }}" \
            -derivedDataPath build \
            test
```

- [ ] **Step 9: Write `README.md`**

Cover: what the app is, requirements (Xcode with the tvOS simulator runtime, `brew install xcodegen`), `./build-and-run.sh`, `./build-and-run.sh --test`, the layer rule, and a pointer to the spec and this plan.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "chore: tvOS project skeleton, build script, and CI

XcodeGen project targeting tvOS 18, a unit-test bundle, a simulator
build/run script, and a GitHub Actions job that builds and tests on a
macOS runner.

Adds the layering guard that keeps Sources/Core free of UI frameworks —
that layer is the future Android port target, so the constraint is
enforced rather than documented.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `board-spec.json` and `BoardTables`

**Files:**
- Create: `Spec/board-spec.json`, `Sources/Core/BoardTables.swift`, `Sources/Core/BoardSpec.swift`, `Tests/Support/SpecFixture.swift`, `Tests/BoardTablesTests.swift`
- Delete: `Sources/Core/CoreMarker.swift`
- Modify: `Sources/UI/FiestaBoardApp.swift` (drop the `CoreMarker` reference), `Tests/SmokeTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `BoardCell` — `enum { case blank, character(Character), color(BoardColor) }`
  - `BoardColor` — `enum String { red, orange, yellow, green, blue, violet, white, black }`, `var hex: String`, `init?(code: Int)`
  - `BoardTables.cell(forCode:code62:) -> BoardCell`
  - `Code62Glyph` — `enum String { degree, heart }`, `static func effective(deviceType:configured:) -> Code62Glyph`
  - `BoardSpec.load(from:) throws -> BoardSpec` with `tileRatios`, `characters`, `colors`, `vectors`

- [ ] **Step 1: Write `Spec/board-spec.json`**

The character table is indexed 0–71, taken verbatim from FiestaUI's
`board-characters.ts` and cross-checked against FiestaBoard's
`src/board_chars.py`. Codes 43, 45, 51, 57, 58, 61 are undefined in the
official table and render blank. Index 62 is the device-dependent glyph.

```json
{
  "$comment": "Cross-language contract for rendering a FiestaBoard. Every implementation (Python autofit.py, TypeScript panel-scale.ts, Swift BoardGeometry, future Kotlin) asserts against these bytes so drift fails loudly in every suite at once.",
  "version": 1,
  "tileRatios": { "width": 0.70, "gutter": 0.145, "radius": 0.075 },
  "noteUnitWidthIn": 24.5,
  "noteCols": 15,
  "noteRows": 3,
  "maxNotesPerAxis": 8,
  "derived": {
    "colPitchIn": 1.6333333333333333,
    "rowPitchIn": 2.2132018927444795,
    "blockWidthIn": 24.5,
    "blockHeightIn": 6.639605678233438
  },
  "maxFillStretch": 1.1,
  "physicalWidthIn": { "flagship": 41.2, "note": 24.5 },
  "characters": [
    " ", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
    "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
    "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
    "!", "@", "#", "$", "(", ")", " ", "-", " ", "+", "&", "=", ";", ":",
    " ", "'", "\"", "%", ",", ".", " ", " ", "/", "?", " ", "°"
  ],
  "undefinedCodes": [43, 45, 51, 57, 58, 61],
  "code62": {
    "degree": "°",
    "heart": "♥",
    "heartDeviceTypes": ["note", "note_array"]
  },
  "colors": {
    "63": "#eb4034",
    "64": "#f5a623",
    "65": "#f8e71c",
    "66": "#7ed321",
    "67": "#4a90d9",
    "68": "#9b59b6",
    "69": "#ffffff",
    "70": "#1a1a1a",
    "71": "#1a1a1a"
  },
  "colorNames": {
    "red": "#eb4034",
    "orange": "#f5a623",
    "yellow": "#f8e71c",
    "green": "#7ed321",
    "blue": "#4a90d9",
    "violet": "#9b59b6",
    "white": "#ffffff",
    "black": "#1a1a1a"
  },
  "vectors": {
    "$comment": "autofit cases are mirrored VERBATIM from FiestaBoard tests/test_panels_autofit.py and web/src/__tests__/panel-scale.test.ts.",
    "autofit": [
      { "name": "65in 16:9", "diagonal": 65, "aspectW": 16, "aspectH": 9, "notesWide": 2, "notesTall": 4 },
      { "name": "43in 16:9", "diagonal": 43, "aspectW": 16, "aspectH": 9, "notesWide": 1, "notesTall": 3 },
      { "name": "85in 16:9", "diagonal": 85, "aspectW": 16, "aspectH": 9, "notesWide": 3, "notesTall": 6 },
      { "name": "3in pocket", "diagonal": 3, "aspectW": 16, "aspectH": 9, "notesWide": 1, "notesTall": 1 },
      { "name": "55in ultrawide 21:9", "diagonal": 55, "aspectW": 21, "aspectH": 9, "notesWide": 2, "notesTall": 3 },
      { "name": "55in portrait 9:16", "diagonal": 55, "aspectW": 9, "aspectH": 16, "notesWide": 1, "notesTall": 7 },
      { "name": "40in 4:3 signage", "diagonal": 40, "aspectW": 4, "aspectH": 3, "notesWide": 1, "notesTall": 3 },
      { "name": "clamps a gigantic screen", "diagonal": 2000, "aspectW": 16, "aspectH": 9, "notesWide": 8, "notesTall": 8 }
    ],
    "screenDimensions": [
      { "diagonal": 65, "aspectW": 16, "aspectH": 9, "widthIn": 56.65220536, "heightIn": 31.86686551 }
    ]
  }
}
```

`derived.rowPitchIn` is `colPitchIn × (1.145 / 0.845)`. The implementation
recomputes it and the test asserts agreement — a literal that drifts from
the formula is exactly the bug this file exists to catch.

- [ ] **Step 2: Write the failing tests**

`Tests/Support/SpecFixture.swift`:

```swift
import Foundation
import XCTest
@testable import FiestaBoardTV

enum SpecFixture {
    /// The bundled board-spec.json, loaded once.
    static let spec: BoardSpec = {
        guard let url = Bundle(for: BundleToken.self).url(forResource: "board-spec", withExtension: "json")
            ?? Bundle.main.url(forResource: "board-spec", withExtension: "json") else {
            fatalError("board-spec.json is not in the test bundle — check the Spec folder reference in project.yml")
        }
        return try! BoardSpec.load(from: url)
    }()
}

private final class BundleToken {}
```

`Tests/BoardTablesTests.swift`:

```swift
import XCTest
@testable import FiestaBoardTV

final class BoardTablesTests: XCTestCase {

    func testSpecLoads() {
        XCTAssertEqual(SpecFixture.spec.characters.count, 63)
        XCTAssertEqual(SpecFixture.spec.version, 1)
    }

    func testLettersMapToCodes1Through26() {
        XCTAssertEqual(BoardTables.cell(forCode: 1, code62: .degree), .character("A"))
        XCTAssertEqual(BoardTables.cell(forCode: 26, code62: .degree), .character("Z"))
    }

    /// The digit run is the classic trap: 1-9 are 27-35 and ZERO is 36.
    func testDigitsAreOffsetWithZeroLast() {
        XCTAssertEqual(BoardTables.cell(forCode: 27, code62: .degree), .character("1"))
        XCTAssertEqual(BoardTables.cell(forCode: 35, code62: .degree), .character("9"))
        XCTAssertEqual(BoardTables.cell(forCode: 36, code62: .degree), .character("0"))
    }

    func testCodeZeroIsBlank() {
        XCTAssertEqual(BoardTables.cell(forCode: 0, code62: .degree), .blank)
    }

    func testUndefinedCodesRenderBlank() {
        for code in SpecFixture.spec.undefinedCodes {
            XCTAssertEqual(BoardTables.cell(forCode: code, code62: .degree), .blank,
                           "code \(code) is undefined in the official table and must render blank")
        }
    }

    func testCode62IsDeviceDependent() {
        XCTAssertEqual(BoardTables.cell(forCode: 62, code62: .degree), .character("°"))
        XCTAssertEqual(BoardTables.cell(forCode: 62, code62: .heart), .character("♥"))
    }

    func testNoteDevicesGetTheHeart() {
        XCTAssertEqual(Code62Glyph.effective(deviceType: "note", configured: nil), .heart)
        XCTAssertEqual(Code62Glyph.effective(deviceType: "note_array", configured: nil), .heart)
        XCTAssertEqual(Code62Glyph.effective(deviceType: "note_array", configured: .degree), .heart,
                       "a note device's heart is not overridable — matches FiestaUI")
        XCTAssertEqual(Code62Glyph.effective(deviceType: "flagship", configured: nil), .degree)
        XCTAssertEqual(Code62Glyph.effective(deviceType: "flagship", configured: .heart), .heart)
    }

    func testColorCodesMatchTheSpec() {
        for (codeString, hex) in SpecFixture.spec.colors {
            let code = Int(codeString)!
            guard case .color(let color) = BoardTables.cell(forCode: code, code62: .degree) else {
                return XCTFail("code \(code) should be a color")
            }
            XCTAssertEqual(color.hex.lowercased(), hex.lowercased(), "color code \(code)")
        }
    }

    /// 70 and 71 are both board-black: 71 is the "filled black" variant.
    func testBothBlackCodesResolveToBoardBlack() {
        XCTAssertEqual(BoardColor(code: 70)?.hex, "#1a1a1a")
        XCTAssertEqual(BoardColor(code: 71)?.hex, "#1a1a1a")
    }

    func testOutOfRangeCodesAreBlank() {
        XCTAssertEqual(BoardTables.cell(forCode: -1, code62: .degree), .blank)
        XCTAssertEqual(BoardTables.cell(forCode: 72, code62: .degree), .blank)
        XCTAssertEqual(BoardTables.cell(forCode: 9999, code62: .degree), .blank)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `./build-and-run.sh --test`
Expected: FAIL — `BoardSpec`, `BoardTables`, `BoardColor`, `Code62Glyph` are undefined.

- [ ] **Step 4: Implement `BoardSpec.swift`**

```swift
import Foundation

/// The cross-language rendering contract, decoded from Spec/board-spec.json.
///
/// This type deliberately mirrors the JSON rather than improving on it: the
/// file is the shared artifact, and a Swift-side reinterpretation would
/// defeat the point of having one.
public struct BoardSpec: Decodable, Sendable {

    public struct TileRatios: Decodable, Sendable {
        public let width: Double
        public let gutter: Double
        public let radius: Double
    }

    public struct Derived: Decodable, Sendable {
        public let colPitchIn: Double
        public let rowPitchIn: Double
        public let blockWidthIn: Double
        public let blockHeightIn: Double
    }

    public struct Code62Spec: Decodable, Sendable {
        public let degree: String
        public let heart: String
        public let heartDeviceTypes: [String]
    }

    public struct AutofitVector: Decodable, Sendable {
        public let name: String
        public let diagonal: Double
        public let aspectW: Double
        public let aspectH: Double
        public let notesWide: Int
        public let notesTall: Int
    }

    public struct ScreenDimensionVector: Decodable, Sendable {
        public let diagonal: Double
        public let aspectW: Double
        public let aspectH: Double
        public let widthIn: Double
        public let heightIn: Double
    }

    public struct Vectors: Decodable, Sendable {
        public let autofit: [AutofitVector]
        public let screenDimensions: [ScreenDimensionVector]
    }

    public let version: Int
    public let tileRatios: TileRatios
    public let noteUnitWidthIn: Double
    public let noteCols: Int
    public let noteRows: Int
    public let maxNotesPerAxis: Int
    public let derived: Derived
    public let maxFillStretch: Double
    public let characters: [String]
    public let undefinedCodes: [Int]
    public let code62: Code62Spec
    public let colors: [String: String]
    public let colorNames: [String: String]
    public let vectors: Vectors

    public static func load(from url: URL) throws -> BoardSpec {
        try JSONDecoder().decode(BoardSpec.self, from: Data(contentsOf: url))
    }
}
```

- [ ] **Step 5: Implement `BoardTables.swift`**

```swift
import Foundation

/// One cell of a board frame.
public enum BoardCell: Equatable, Sendable {
    case blank
    case character(Character)
    case color(BoardColor)
}

/// The eight board pigments. Hex values are FiestaUI's `BOARD_COLORS`.
public enum BoardColor: String, CaseIterable, Sendable {
    case red, orange, yellow, green, blue, violet, white, black

    public var hex: String {
        switch self {
        case .red:    return "#eb4034"
        case .orange: return "#f5a623"
        case .yellow: return "#f8e71c"
        case .green:  return "#7ed321"
        case .blue:   return "#4a90d9"
        case .violet: return "#9b59b6"
        case .white:  return "#ffffff"
        // Board black is #1a1a1a, never pure black: a real flap reflects light.
        case .black:  return "#1a1a1a"
        }
    }

    /// Character codes 63-71. 70 and 71 are both black (71 is "filled").
    public init?(code: Int) {
        switch code {
        case 63: self = .red
        case 64: self = .orange
        case 65: self = .yellow
        case 66: self = .green
        case 67: self = .blue
        case 68: self = .violet
        case 69: self = .white
        case 70, 71: self = .black
        default: return nil
        }
    }
}

/// Which glyph character code 62 shows. Note-family devices print a heart
/// where a Flagship prints a degree sign.
public enum Code62Glyph: String, Sendable {
    case degree, heart

    public var character: Character {
        self == .heart ? "♥" : "°"
    }

    /// Mirrors FiestaUI's `effectiveCode62Glyph`: note devices are always
    /// hearts regardless of configuration; everything else honours the
    /// configured value and defaults to degree.
    public static func effective(deviceType: String?, configured: Code62Glyph?) -> Code62Glyph {
        if deviceType == "note" || deviceType == "note_array" { return .heart }
        return configured ?? .degree
    }
}

/// Character-code lookup for board frames.
///
/// Codes 0-71, per https://docs.vestaboard.com/docs/characterCodes. Codes
/// 43, 45, 51, 57, 58 and 61 are not defined in the official table and
/// render blank. Code 62 is device-dependent (see `Code62Glyph`).
public enum BoardTables {

    /// Printable glyphs for codes 0-61. Index 62 is handled separately
    /// because it depends on the device; 63-71 are colors.
    private static let glyphs: [Character?] = {
        var table: [Character?] = [nil]                                  // 0: blank
        table += "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { Optional($0) }       // 1-26
        table += "1234567890".map { Optional($0) }                       // 27-36
        // 37-61, with nil at the officially undefined codes.
        let tail: [Character?] = [
            "!", "@", "#", "$", "(", ")", nil, "-", nil, "+", "&", "=",
            ";", ":", nil, "'", "\"", "%", ",", ".", nil, nil, "/", "?", nil,
        ]
        table += tail
        return table
    }()

    public static func cell(forCode code: Int, code62: Code62Glyph) -> BoardCell {
        if code == 62 { return .character(code62.character) }
        if let color = BoardColor(code: code) { return .color(color) }
        guard code >= 0, code < glyphs.count, let glyph = glyphs[code] else { return .blank }
        return .character(glyph)
    }

    /// Convenience for a whole frame.
    public static func cells(from characters: [[Int]], code62: Code62Glyph) -> [[BoardCell]] {
        characters.map { row in row.map { cell(forCode: $0, code62: code62) } }
    }
}
```

- [ ] **Step 6: Delete the marker and update the app entry**

Delete `Sources/Core/CoreMarker.swift`. In `Sources/UI/FiestaBoardApp.swift`
replace the body with `Text("FiestaBoard")`. In `Tests/SmokeTests.swift`
replace `testCoreIsLinked` with:

```swift
func testBoardTablesAreLinked() {
    XCTAssertEqual(BoardTables.cell(forCode: 1, code62: .degree), .character("A"))
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `./build-and-run.sh --test`
Expected: PASS — all `BoardTablesTests` green.

Note the `glyphs` table length: indices 0…61 is 62 entries. If the test
reports an out-of-range or off-by-one glyph, count the `tail` array — it
must be exactly 25 entries (codes 37–61).

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(core): board character and color tables, pinned by a shared spec file

Adds Spec/board-spec.json: the cross-language contract for rendering a
FiestaBoard — tile ratios, note pitch, the 0-71 character table, the
color table, and worked autofit vectors.

The autofit vectors are mirrored verbatim from FiestaBoard's
test_panels_autofit.py and panel-scale.test.ts, which today keep two
implementations in step by hand. A third implementation is what makes
that prose contract worth turning into data.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `BoardGeometry`

**Files:**
- Create: `Sources/Core/BoardGeometry.swift`, `Tests/BoardGeometryTests.swift`

**Interfaces:**
- Consumes: `BoardSpec` (Task 2) for test vectors
- Produces:
  - `BoardGeometry.colPitchIn: Double`, `.rowPitchIn: Double`, `.blockWidthIn`, `.blockHeightIn`, `.maxFillStretch`, `.maxNotesPerAxis`
  - `BoardGeometry.screenDimensionsIn(diagonal:aspectW:aspectH:) throws -> (width: Double, height: Double)`
  - `BoardGeometry.computeAutofitGrid(diagonal:aspectW:aspectH:) throws -> (notesWide: Int, notesTall: Int)`
  - `BoardGeometry.autofitScale(_: AutofitScaleInput) throws -> Double`
  - `AutofitScaleInput` — struct with `screenWidthPx`, `screenHeightPx`, `diagonalInches`, `cols`, `gridWidthPx`, `gridHeightPx`, `calibration`, `colPitchIn`
  - `BoardGeometry.Error` — `enum { case nonPositive(String) }`

- [ ] **Step 1: Write the failing tests**

`Tests/BoardGeometryTests.swift`:

```swift
import XCTest
@testable import FiestaBoardTV

final class BoardGeometryTests: XCTestCase {

    // MARK: Constants agree with the shared spec

    func testPitchMatchesTheSpec() {
        let spec = SpecFixture.spec
        XCTAssertEqual(BoardGeometry.colPitchIn, spec.derived.colPitchIn, accuracy: 1e-9)
        XCTAssertEqual(BoardGeometry.rowPitchIn, spec.derived.rowPitchIn, accuracy: 1e-9)
        XCTAssertEqual(BoardGeometry.blockWidthIn, spec.derived.blockWidthIn, accuracy: 1e-9)
        XCTAssertEqual(BoardGeometry.blockHeightIn, spec.derived.blockHeightIn, accuracy: 1e-9)
    }

    /// Row pitch is derived from the renderer's tile ratios, not measured off
    /// a Note's bezel-heavy height. Asserting the formula here is what stops a
    /// hand-edited literal in board-spec.json from silently winning.
    func testRowPitchFollowsTheTileRatios() {
        let r = SpecFixture.spec.tileRatios
        let colPitchRatio = r.width + r.gutter      // 0.845
        let rowPitchRatio = 1.0 + r.gutter          // 1.145
        XCTAssertEqual(BoardGeometry.rowPitchIn,
                       BoardGeometry.colPitchIn * (rowPitchRatio / colPitchRatio),
                       accuracy: 1e-9)
    }

    // MARK: Spec vectors

    func testScreenDimensionsMatchEverySpecVector() throws {
        for v in SpecFixture.spec.vectors.screenDimensions {
            let (w, h) = try BoardGeometry.screenDimensionsIn(
                diagonal: v.diagonal, aspectW: v.aspectW, aspectH: v.aspectH)
            XCTAssertEqual(w, v.widthIn, accuracy: 1e-6, "width for \(v.diagonal)\"")
            XCTAssertEqual(h, v.heightIn, accuracy: 1e-6, "height for \(v.diagonal)\"")
            XCTAssertEqual(hypot(w, h), v.diagonal, accuracy: 1e-6, "diagonal round-trip")
        }
    }

    func testAutofitMatchesEverySpecVector() throws {
        for v in SpecFixture.spec.vectors.autofit {
            let grid = try BoardGeometry.computeAutofitGrid(
                diagonal: v.diagonal, aspectW: v.aspectW, aspectH: v.aspectH)
            XCTAssertEqual(grid.notesWide, v.notesWide, "notesWide for \(v.name)")
            XCTAssertEqual(grid.notesTall, v.notesTall, "notesTall for \(v.name)")
        }
    }

    func testDefaultAspectIsSixteenNine() throws {
        let a = try BoardGeometry.computeAutofitGrid(diagonal: 65)
        let b = try BoardGeometry.computeAutofitGrid(diagonal: 65, aspectW: 16, aspectH: 9)
        XCTAssertEqual(a.notesWide, b.notesWide)
        XCTAssertEqual(a.notesTall, b.notesTall)
    }

    func testRejectsNonPositiveInputs() {
        XCTAssertThrowsError(try BoardGeometry.screenDimensionsIn(diagonal: 0))
        XCTAssertThrowsError(try BoardGeometry.screenDimensionsIn(diagonal: -5))
        XCTAssertThrowsError(try BoardGeometry.computeAutofitGrid(diagonal: 55, aspectW: 0, aspectH: 9))
        XCTAssertThrowsError(try BoardGeometry.computeAutofitGrid(diagonal: 55, aspectW: 16, aspectH: -1))
    }

    // MARK: autofitScale

    private func input(cols: Int = 30,
                       gridWidthPx: Double = 1000,
                       gridHeightPx: Double = 500,
                       calibration: Double = 1.0) -> AutofitScaleInput {
        AutofitScaleInput(screenWidthPx: 1920, screenHeightPx: 1080,
                          diagonalInches: 65, cols: cols,
                          gridWidthPx: gridWidthPx, gridHeightPx: gridHeightPx,
                          calibration: calibration,
                          colPitchIn: BoardGeometry.colPitchIn)
    }

    /// True scale anchors flap width to the physical column pitch.
    func testAnchorsFlapWidthToColumnPitch() throws {
        let ppi = hypot(1920.0, 1080.0) / 65.0
        let trueScale = (30.0 * BoardGeometry.colPitchIn * ppi) / 1000.0
        // 30 cols at true scale is well under 1920px here, so the stretch
        // clamps at the 10% cap rather than landing on the edge exactly.
        let scale = try BoardGeometry.autofitScale(input())
        XCTAssertEqual(scale, trueScale * BoardGeometry.maxFillStretch, accuracy: 1e-9)
    }

    func testNeverStretchesBeyondTenPercent() throws {
        let scale = try BoardGeometry.autofitScale(input(gridWidthPx: 100, gridHeightPx: 50))
        let ppi = hypot(1920.0, 1080.0) / 65.0
        let trueScale = (30.0 * BoardGeometry.colPitchIn * ppi) / 100.0
        XCTAssertEqual(scale, trueScale * 1.1, accuracy: 1e-9)
    }

    /// The one case that shrinks below true size: a grid that overflows the
    /// screen at true scale (a pocket display) must fit rather than show a
    /// life-size crop of its top-left corner.
    func testShrinksToFitWhenTrueScaleOverflows() throws {
        let overflowing = AutofitScaleInput(
            screenWidthPx: 320, screenHeightPx: 180, diagonalInches: 3,
            cols: 15, gridWidthPx: 400, gridHeightPx: 200,
            calibration: 1.0, colPitchIn: BoardGeometry.colPitchIn)
        let scale = try BoardGeometry.autofitScale(overflowing)
        XCTAssertLessThan(scale * 400, 320.0 + 0.001, "must fit horizontally")
        XCTAssertLessThan(scale * 200, 180.0 + 0.001, "must fit vertically")
    }

    func testCalibrationMultiplies() throws {
        let base = try BoardGeometry.autofitScale(input())
        let nudged = try BoardGeometry.autofitScale(input(calibration: 1.15))
        XCTAssertEqual(nudged, base * 1.15, accuracy: 1e-9)
    }

    func testRejectsUnmeasurableGrid() {
        XCTAssertThrowsError(try BoardGeometry.autofitScale(input(gridWidthPx: 0)))
        XCTAssertThrowsError(try BoardGeometry.autofitScale(input(gridHeightPx: 0)))
        XCTAssertThrowsError(try BoardGeometry.autofitScale(input(cols: 0)))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./build-and-run.sh --test`
Expected: FAIL — `BoardGeometry` and `AutofitScaleInput` are undefined.

- [ ] **Step 3: Implement `BoardGeometry.swift`**

```swift
import Foundation

/// Inputs to `BoardGeometry.autofitScale`.
public struct AutofitScaleInput: Sendable {
    public let screenWidthPx: Double
    public let screenHeightPx: Double
    public let diagonalInches: Double
    /// Grid columns — the physical width anchor.
    public let cols: Int
    /// Measured unscaled grid size, tiles only, no bezel.
    public let gridWidthPx: Double
    public let gridHeightPx: Double
    /// User fine-tune for screens that misreport resolution or overscan.
    public let calibration: Double
    public let colPitchIn: Double

    public init(screenWidthPx: Double, screenHeightPx: Double, diagonalInches: Double,
                cols: Int, gridWidthPx: Double, gridHeightPx: Double,
                calibration: Double = 1.0, colPitchIn: Double = BoardGeometry.colPitchIn) {
        self.screenWidthPx = screenWidthPx
        self.screenHeightPx = screenHeightPx
        self.diagonalInches = diagonalInches
        self.cols = cols
        self.gridWidthPx = gridWidthPx
        self.gridHeightPx = gridHeightPx
        self.calibration = calibration
        self.colPitchIn = colPitchIn
    }
}

/// Physical-scale math for a FiestaPanel.
///
/// The Swift twin of FiestaBoard's `src/panels/autofit.py` and
/// `web/src/lib/panel-scale.ts`. All three are pinned by the vectors in
/// `Spec/board-spec.json`, so drift fails a suite in every language.
///
/// Anchoring: a frameless Vestaboard Note is 24.5" wide for 15 columns, so
/// the column pitch is fixed. Row pitch follows the renderer's invariant
/// tile geometry (tile width 0.70·h, gutter 0.145·h on both axes → column
/// pitch 0.845·h, row pitch 1.145·h) rather than the Note unit's
/// bezel-heavy height — which is what lets one uniform scale keep both
/// axes physically true on screen.
public enum BoardGeometry {

    public enum Error: Swift.Error, Equatable {
        case nonPositive(String)
    }

    // Tile ratios (FiestaUI board-metrics TILE_RATIOS).
    public static let tileWidthRatio = 0.70
    public static let tileGutterRatio = 0.145
    public static let tileRadiusRatio = 0.075

    private static let colPitchRatio = tileWidthRatio + tileGutterRatio   // 0.845
    private static let rowPitchRatio = 1.0 + tileGutterRatio              // 1.145

    public static let noteUnitWidthIn = 24.5
    public static let noteCols = 15
    public static let noteRows = 3
    public static let maxNotesPerAxis = 8
    public static let maxFillStretch = 1.1

    public static let colPitchIn = noteUnitWidthIn / Double(noteCols)
    public static let rowPitchIn = colPitchIn * (rowPitchRatio / colPitchRatio)

    public static let blockWidthIn = Double(noteCols) * colPitchIn
    public static let blockHeightIn = Double(noteRows) * rowPitchIn

    /// Published Vestaboard unit widths, bezel included.
    public static let flagshipWidthIn = 41.2
    public static let flagshipCols = 22

    /// Physical column pitch for a device family.
    public static func colPitchIn(deviceType: String?) -> Double {
        deviceType == "flagship" ? flagshipWidthIn / Double(flagshipCols) : colPitchIn
    }

    /// (width, height) in inches of a screen with the given diagonal and aspect.
    public static func screenDimensionsIn(diagonal: Double,
                                          aspectW: Double = 16,
                                          aspectH: Double = 9) throws -> (width: Double, height: Double) {
        guard diagonal > 0 else { throw Error.nonPositive("diagonal \(diagonal)") }
        guard aspectW > 0, aspectH > 0 else { throw Error.nonPositive("aspect \(aspectW):\(aspectH)") }
        let hyp = hypot(aspectW, aspectH)
        return (diagonal * aspectW / hyp, diagonal * aspectH / hyp)
    }

    /// The largest true-scale grid of Note blocks that fits the screen.
    ///
    /// Always at least 1×1 — a screen smaller than one block gets a
    /// block-sized grid that the viewer shrinks to fit — and never more
    /// than `maxNotesPerAxis` per axis.
    public static func computeAutofitGrid(diagonal: Double,
                                          aspectW: Double = 16,
                                          aspectH: Double = 9) throws -> (notesWide: Int, notesTall: Int) {
        let (widthIn, heightIn) = try screenDimensionsIn(diagonal: diagonal, aspectW: aspectW, aspectH: aspectH)
        func clamp(_ blocks: Int) -> Int { max(1, min(maxNotesPerAxis, blocks)) }
        return (clamp(Int(floor(widthIn / blockWidthIn))),
                clamp(Int(floor(heightIn / blockHeightIn))))
    }

    /// Scale for a borderless auto-fit grid: flaps at true physical size,
    /// then gently stretched (≤ `maxFillStretch`) toward the nearest screen
    /// edge. Never shrinks below true size to fill — except when the grid
    /// overflows the screen at true size, where fitting beats a life-size
    /// crop of the top-left corner.
    public static func autofitScale(_ input: AutofitScaleInput) throws -> Double {
        guard input.gridWidthPx > 0, input.gridHeightPx > 0 else {
            throw Error.nonPositive("grid \(input.gridWidthPx)×\(input.gridHeightPx)")
        }
        guard input.cols > 0 else { throw Error.nonPositive("cols \(input.cols)") }
        guard input.screenWidthPx > 0, input.screenHeightPx > 0 else {
            throw Error.nonPositive("screen \(input.screenWidthPx)×\(input.screenHeightPx)")
        }
        guard input.diagonalInches > 0 else { throw Error.nonPositive("diagonal \(input.diagonalInches)") }

        let ppi = hypot(input.screenWidthPx, input.screenHeightPx) / input.diagonalInches
        let trueScale = (Double(input.cols) * input.colPitchIn * ppi) / input.gridWidthPx
        let fill = min(input.screenWidthPx / (input.gridWidthPx * trueScale),
                       input.screenHeightPx / (input.gridHeightPx * trueScale))
        let stretch = fill < 1 ? fill : min(maxFillStretch, fill)
        return trueScale * stretch * input.calibration
    }

    /// Scale that simply fits the grid to the screen — the app's default,
    /// used when the panel's grid was auto-fit for a different screen and
    /// physical accuracy would only buy black margins.
    public static func fitScale(gridWidthPx: Double, gridHeightPx: Double,
                                screenWidthPx: Double, screenHeightPx: Double) throws -> Double {
        guard gridWidthPx > 0, gridHeightPx > 0 else {
            throw Error.nonPositive("grid \(gridWidthPx)×\(gridHeightPx)")
        }
        guard screenWidthPx > 0, screenHeightPx > 0 else {
            throw Error.nonPositive("screen \(screenWidthPx)×\(screenHeightPx)")
        }
        return min(screenWidthPx / gridWidthPx, screenHeightPx / gridHeightPx)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./build-and-run.sh --test`
Expected: PASS.

If `testAnchorsFlapWidthToColumnPitch` fails, check whether the fill
factor at those numbers actually exceeds 1.1 — recompute
`1920 / (1000 × trueScale)` by hand before changing the implementation.
The assertion, not the code, is the likelier error.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(core): physical-scale geometry for panels

Swift twin of autofit.py and panel-scale.ts: screen dimensions, the
auto-fit Note-block grid, and the true-scale-plus-gentle-stretch factor
the viewer paints with.

Every case is asserted against Spec/board-spec.json rather than against
locally chosen numbers, so this implementation and FiestaBoard's two
cannot drift quietly.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Models and `FiestaClient`

**Files:**
- Create: `Sources/Core/Models.swift`, `Sources/Core/FiestaClient.swift`, `Tests/Support/StubURLProtocol.swift`, `Tests/Support/Fixtures.swift`, `Tests/FiestaClientTests.swift`

**Interfaces:**
- Consumes: `Code62Glyph` (Task 2)
- Produces:
  - `Panel` — `id`, `shortCode`, `name`, `boardId`, `screenDiagonalInches`, `screenAspectW`, `screenAspectH`, `calibrationScale`, `animationsEnabled`, `backdrop`, `autoDim`, `deviceType`, `boardMissing`, `rows`, `cols`, `boardColor`, `code62Glyph`
  - `AutoDim` — `enabled: Bool`, `start: String`, `end: String`
  - `PanelFrame` — `characters: [[Int]]?`, `rows: Int`, `cols: Int`, `updatedAt: Date?`
  - `AuthStatus` — `enabled`, `setupRequired`, `authenticated`, `username`, `mode`, `firstRun`
  - `PanelUpdateResult` — `panel: Panel`, `incompatibleReferences: [IncompatibleReference]`
  - `FiestaClient` — `init(baseURL:session:)`, `authStatus()`, `login(username:password:)`, `panels()`, `panel(ref:)`, `frame(ref:)`, `updatePanel(id:diagonal:aspectW:aspectH:calibration:)`
  - `FiestaError` — `enum { case unauthorized, notFound(String), setupRequired, http(Int), transport(Error), decoding(Error) }`

- [ ] **Step 1: Write the stub URL protocol and fixtures**

`Tests/Support/StubURLProtocol.swift`:

```swift
import Foundation

/// Intercepts URLSession traffic so client tests never touch the network.
///
/// Responses are queued per path prefix. `requests` records what was sent,
/// including bodies, so tests can assert on the request as well as the reply.
final class StubURLProtocol: URLProtocol {

    struct Stub {
        let status: Int
        let body: Data
        let headers: [String: String]

        init(status: Int = 200, body: Data = Data(), headers: [String: String] = [:]) {
            self.status = status
            self.body = body
            self.headers = headers
        }

        static func json(_ string: String, status: Int = 200) -> Stub {
            Stub(status: status, body: Data(string.utf8),
                 headers: ["Content-Type": "application/json"])
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var queues: [String: [Stub]] = [:]
    nonisolated(unsafe) private static var recorded: [(url: URL, method: String, body: Data?)] = []

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        queues = [:]
        recorded = []
    }

    /// Queue a response for the next request whose path contains `pathFragment`.
    static func enqueue(_ stub: Stub, for pathFragment: String) {
        lock.lock(); defer { lock.unlock() }
        queues[pathFragment, default: []].append(stub)
    }

    static var requests: [(url: URL, method: String, body: Data?)] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    // Longest matching fragment wins, so "/panels" and "/panel/" can coexist.
    private static func dequeue(for url: URL) -> Stub? {
        lock.lock(); defer { lock.unlock() }
        let path = url.path
        let key = queues.keys
            .filter { path.contains($0) && !(queues[$0]?.isEmpty ?? true) }
            .max(by: { $0.count < $1.count })
        guard let key, var queue = queues[key], !queue.isEmpty else { return nil }
        let stub = queue.removeFirst()
        queues[key] = queue
        return stub
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        // httpBody is nil for stream-backed bodies; read the stream instead.
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let size = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: size)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            buffer.deallocate()
            stream.close()
            body = data
        }

        StubURLProtocol.lock.lock()
        StubURLProtocol.recorded.append((url, request.httpMethod ?? "GET", body))
        StubURLProtocol.lock.unlock()

        guard let stub = StubURLProtocol.dequeue(for: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: stub.status,
                                       httpVersion: "HTTP/1.1", headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
```

`Tests/Support/Fixtures.swift` — real payload shapes from a running instance:

```swift
import Foundation

enum Fixtures {

    static let authStatusDisabled = """
    {"enabled":false,"setup_required":false,"authenticated":false,
     "username":null,"mode":"disabled","first_run":false}
    """

    static let authStatusEnabled = """
    {"enabled":true,"setup_required":false,"authenticated":false,
     "username":null,"mode":"enabled","first_run":false}
    """

    static let loginOK = #"{"status":"ok","username":"jeffre"}"#

    static let panelJSON = """
    {"id":"abc123def456","short_code":1,"name":"Living Room",
     "board_id":"11111111-2222-3333-4444-555555555555",
     "screen_diagonal_inches":65.0,"screen_aspect_w":16.0,"screen_aspect_h":9.0,
     "calibration_scale":1.0,"animations_enabled":false,"is_display":false,
     "backdrop":"wall","auto_dim":{"enabled":true,"start":"22:00","end":"07:00"},
     "created_at":"2026-09-01T12:00:00Z","updated_at":"2026-09-02T12:00:00Z",
     "device_type":"note_array","board_missing":false,"rows":12,"cols":30,
     "board_color":"black","code62_glyph":"heart"}
    """

    static var panelsList: String { #"{"panels":[\#(panelJSON)],"total":1}"# }

    /// A 2x3 frame: "HI" on the first row, a red tile on the second.
    static let frameJSON = """
    {"characters":[[8,9,0],[63,0,0]],"message":"HI",
     "rows":2,"cols":3,"updated_at":"2026-09-19T10:30:00Z"}
    """

    static let emptyFrameJSON = """
    {"characters":null,"message":null,"rows":12,"cols":30,"updated_at":null}
    """

    static let panelNotFound = #"{"detail":"Panel not found"}"#
}
```

- [ ] **Step 2: Write the failing client tests**

`Tests/FiestaClientTests.swift`:

```swift
import XCTest
@testable import FiestaBoardTV

final class FiestaClientTests: XCTestCase {

    private var client: FiestaClient!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        client = FiestaClient(baseURL: URL(string: "http://192.168.1.50:4420")!,
                              session: StubURLProtocol.makeSession())
    }

    override func tearDown() {
        StubURLProtocol.reset()
        client = nil
        super.tearDown()
    }

    func testAuthStatusDecodesSnakeCase() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/auth/status")
        let status = try await client.authStatus()
        XCTAssertTrue(status.enabled)
        XCTAssertFalse(status.authenticated)
        XCTAssertEqual(status.mode, "enabled")
        XCTAssertFalse(status.setupRequired)
    }

    func testLoginPostsCredentialsAndAlwaysAsksToBeRemembered() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.loginOK), for: "/auth/login")
        try await client.login(username: "jeffre", password: "hunter2")

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.path, "/auth/login")

        let body = try XCTUnwrap(request.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["username"] as? String, "jeffre")
        XCTAssertEqual(json["password"] as? String, "hunter2")
        // A TV that re-prompts for a password every week gets unplugged.
        XCTAssertEqual(json["remember_me"] as? Bool, true)
    }

    func testLoginMapsA401ToUnauthorized() async {
        StubURLProtocol.enqueue(.json(#"{"detail":"Invalid username or password"}"#, status: 401),
                                for: "/auth/login")
        do {
            try await client.login(username: "jeffre", password: "wrong")
            XCTFail("expected unauthorized")
        } catch FiestaError.unauthorized {
            // expected
        } catch {
            XCTFail("expected .unauthorized, got \(error)")
        }
    }

    /// A 409 from any endpoint means no user exists yet — the app must send
    /// the user to the web UI rather than offer a sign-in form that cannot work.
    func testSetupRequiredIsItsOwnError() async {
        StubURLProtocol.enqueue(.json(#"{"detail":"Setup required","setup_required":true}"#, status: 409),
                                for: "/panels")
        do {
            _ = try await client.panels()
            XCTFail("expected setupRequired")
        } catch FiestaError.setupRequired {
            // expected
        } catch {
            XCTFail("expected .setupRequired, got \(error)")
        }
    }

    func testPanelsDecodesTheListEnvelope() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/panels")
        let panels = try await client.panels()
        XCTAssertEqual(panels.count, 1)
        let panel = try XCTUnwrap(panels.first)
        XCTAssertEqual(panel.id, "abc123def456")
        XCTAssertEqual(panel.shortCode, 1)
        XCTAssertEqual(panel.name, "Living Room")
        XCTAssertEqual(panel.rows, 12)
        XCTAssertEqual(panel.cols, 30)
        XCTAssertEqual(panel.deviceType, "note_array")
        XCTAssertEqual(panel.code62Glyph, .heart)
        XCTAssertEqual(panel.autoDim.start, "22:00")
        XCTAssertTrue(panel.autoDim.enabled)
        XCTAssertFalse(panel.animationsEnabled)
    }

    func testPanelsMapsA401ToUnauthorized() async {
        StubURLProtocol.enqueue(.json(#"{"detail":"Not authenticated"}"#, status: 401), for: "/panels")
        do {
            _ = try await client.panels()
            XCTFail("expected unauthorized")
        } catch FiestaError.unauthorized {
        } catch {
            XCTFail("expected .unauthorized, got \(error)")
        }
    }

    /// The viewer surface takes an id OR a short code, so /panel/1 must work.
    func testPanelAcceptsAShortCodeRef() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/panel/")
        _ = try await client.panel(ref: "1")
        XCTAssertEqual(StubURLProtocol.requests.first?.url.path, "/panel/1")
    }

    func testFrameDecodesCharactersAndTimestamp() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.frameJSON), for: "/frame")
        let frame = try await client.frame(ref: "abc123def456")
        XCTAssertEqual(frame.characters?.count, 2)
        XCTAssertEqual(frame.characters?[0], [8, 9, 0])
        XCTAssertEqual(frame.rows, 2)
        XCTAssertEqual(frame.cols, 3)
        XCTAssertNotNil(frame.updatedAt)
    }

    /// A board nothing has been sent to yet is blank, not broken.
    func testFrameToleratesNullCharacters() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.emptyFrameJSON), for: "/frame")
        let frame = try await client.frame(ref: "abc123def456")
        XCTAssertNil(frame.characters)
        XCTAssertNil(frame.updatedAt)
        XCTAssertEqual(frame.cols, 30)
    }

    func testDeletedPanelIsNotFound() async {
        StubURLProtocol.enqueue(.json(Fixtures.panelNotFound, status: 404), for: "/panel/")
        do {
            _ = try await client.panel(ref: "gone")
            XCTFail("expected notFound")
        } catch FiestaError.notFound {
        } catch {
            XCTFail("expected .notFound, got \(error)")
        }
    }

    func testUpdatePanelPatchesOnlyTheFieldsGiven() async throws {
        let response = #"{"status":"success","panel":\#(Fixtures.panelJSON)}"#
        StubURLProtocol.enqueue(.json(response), for: "/panels/")
        _ = try await client.updatePanel(id: "abc123def456", diagonal: 55, aspectW: 16, aspectH: 9)

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.method, "PATCH")
        XCTAssertEqual(request.url.path, "/panels/abc123def456")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body!) as? [String: Any])
        XCTAssertEqual(json["screen_diagonal_inches"] as? Double, 55)
        XCTAssertEqual(json["screen_aspect_w"] as? Double, 16)
        XCTAssertNil(json["name"], "an unset field must not be sent")
        XCTAssertNil(json["calibration_scale"], "an unset field must not be sent")
    }

    /// Reshaping a grid can strand pages authored for the old one. The server
    /// warns; the app must carry that warning rather than swallow it.
    func testUpdatePanelSurfacesIncompatibleReferences() async throws {
        let response = """
        {"status":"success","panel":\(Fixtures.panelJSON),
         "incompatible_references":[{"type":"page","id":"p1","name":"Welcome"}]}
        """
        StubURLProtocol.enqueue(.json(response), for: "/panels/")
        let result = try await client.updatePanel(id: "abc123def456", diagonal: 85)
        XCTAssertEqual(result.incompatibleReferences.count, 1)
        XCTAssertEqual(result.incompatibleReferences.first?.name, "Welcome")
    }

    func testTransportFailuresAreWrapped() async {
        // Nothing enqueued: the stub fails the request.
        do {
            _ = try await client.authStatus()
            XCTFail("expected transport error")
        } catch FiestaError.transport {
        } catch {
            XCTFail("expected .transport, got \(error)")
        }
    }

    func testBaseURLPathsAreJoinedWithoutDoubleSlashes() async throws {
        let trailing = FiestaClient(baseURL: URL(string: "http://host:4420/")!,
                                    session: StubURLProtocol.makeSession())
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/auth/status")
        _ = try await trailing.authStatus()
        XCTAssertEqual(StubURLProtocol.requests.first?.url.absoluteString,
                       "http://host:4420/auth/status")
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `./build-and-run.sh --test`
Expected: FAIL — `FiestaClient`, `FiestaError`, `Panel` are undefined.

- [ ] **Step 4: Implement `Models.swift`**

```swift
import Foundation

/// Night-time dimming window, evaluated against the TV's own clock.
public struct AutoDim: Codable, Equatable, Sendable {
    public let enabled: Bool
    public let start: String   // "HH:MM", 24h
    public let end: String

    public init(enabled: Bool = false, start: String = "22:00", end: String = "07:00") {
        self.enabled = enabled
        self.start = start
        self.end = end
    }
}

/// A FiestaPanel: display configuration plus the geometry of its virtual board.
///
/// Field names follow the server's snake_case payload via CodingKeys rather
/// than a global key-decoding strategy, because `code62_glyph` does not
/// round-trip through automatic conversion.
public struct Panel: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let shortCode: Int
    public let name: String
    public let boardId: String
    public let screenDiagonalInches: Double
    public let screenAspectW: Double
    public let screenAspectH: Double
    public let calibrationScale: Double
    public let animationsEnabled: Bool
    public let backdrop: String
    public let autoDim: AutoDim
    public let deviceType: String?
    public let boardMissing: Bool
    public let rows: Int?
    public let cols: Int?
    public let boardColor: String?
    public let code62Glyph: Code62Glyph?

    enum CodingKeys: String, CodingKey {
        case id
        case shortCode = "short_code"
        case name
        case boardId = "board_id"
        case screenDiagonalInches = "screen_diagonal_inches"
        case screenAspectW = "screen_aspect_w"
        case screenAspectH = "screen_aspect_h"
        case calibrationScale = "calibration_scale"
        case animationsEnabled = "animations_enabled"
        case backdrop
        case autoDim = "auto_dim"
        case deviceType = "device_type"
        case boardMissing = "board_missing"
        case rows, cols
        case boardColor = "board_color"
        case code62Glyph = "code62_glyph"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        shortCode = try c.decodeIfPresent(Int.self, forKey: .shortCode) ?? 0
        name = try c.decode(String.self, forKey: .name)
        boardId = try c.decode(String.self, forKey: .boardId)
        screenDiagonalInches = try c.decodeIfPresent(Double.self, forKey: .screenDiagonalInches) ?? 55
        screenAspectW = try c.decodeIfPresent(Double.self, forKey: .screenAspectW) ?? 16
        screenAspectH = try c.decodeIfPresent(Double.self, forKey: .screenAspectH) ?? 9
        calibrationScale = try c.decodeIfPresent(Double.self, forKey: .calibrationScale) ?? 1
        animationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .animationsEnabled) ?? false
        backdrop = try c.decodeIfPresent(String.self, forKey: .backdrop) ?? "wall"
        autoDim = try c.decodeIfPresent(AutoDim.self, forKey: .autoDim) ?? AutoDim()
        deviceType = try c.decodeIfPresent(String.self, forKey: .deviceType)
        boardMissing = try c.decodeIfPresent(Bool.self, forKey: .boardMissing) ?? false
        rows = try c.decodeIfPresent(Int.self, forKey: .rows)
        cols = try c.decodeIfPresent(Int.self, forKey: .cols)
        boardColor = try c.decodeIfPresent(String.self, forKey: .boardColor)
        code62Glyph = try c.decodeIfPresent(Code62Glyph.self, forKey: .code62Glyph)
    }

    /// The glyph this panel's device actually prints for code 62.
    public var effectiveCode62: Code62Glyph {
        Code62Glyph.effective(deviceType: deviceType, configured: code62Glyph)
    }

    /// Board pigment behind the flaps. Anything unrecognised is black.
    public var backgroundColor: BoardColor {
        boardColor.flatMap { BoardColor(rawValue: $0) } ?? .black
    }
}

/// The virtual board's current content.
public struct PanelFrame: Decodable, Equatable, Sendable {
    public let characters: [[Int]]?
    public let message: String?
    public let rows: Int
    public let cols: Int
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case characters, message, rows, cols
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        characters = try c.decodeIfPresent([[Int]].self, forKey: .characters)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        rows = try c.decodeIfPresent(Int.self, forKey: .rows) ?? 0
        cols = try c.decodeIfPresent(Int.self, forKey: .cols) ?? 0
        if let raw = try c.decodeIfPresent(String.self, forKey: .updatedAt) {
            updatedAt = ISO8601DateFormatter.fiesta.date(from: raw)
        } else {
            updatedAt = nil
        }
    }

    public init(characters: [[Int]]?, message: String?, rows: Int, cols: Int, updatedAt: Date?) {
        self.characters = characters
        self.message = message
        self.rows = rows
        self.cols = cols
        self.updatedAt = updatedAt
    }
}

extension ISO8601DateFormatter {
    /// The server emits fractional seconds on some paths and not others.
    static let fiesta: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

public struct AuthStatus: Decodable, Equatable, Sendable {
    public let enabled: Bool
    public let setupRequired: Bool
    public let authenticated: Bool
    public let username: String?
    public let mode: String
    public let firstRun: Bool

    enum CodingKeys: String, CodingKey {
        case enabled, authenticated, username, mode
        case setupRequired = "setup_required"
        case firstRun = "first_run"
    }
}

/// A page or schedule that no longer fits a reshaped grid.
public struct IncompatibleReference: Decodable, Equatable, Sendable {
    public let type: String?
    public let id: String?
    public let name: String?
}

public struct PanelUpdateResult: Sendable {
    public let panel: Panel
    public let incompatibleReferences: [IncompatibleReference]
}

public enum FiestaError: Error, Equatable {
    case unauthorized
    case setupRequired
    case notFound(String)
    case http(Int)
    case transport(String)
    case decoding(String)

    public var isRecoverableBySigningIn: Bool {
        self == .unauthorized
    }
}
```

Note `PanelFrame.updatedAt` parsing: the formatter above requires
fractional seconds, which `2026-09-19T10:30:00Z` lacks. Step 6 fixes this
with a two-formatter fallback — leave it as written for now so the test
that catches it is a real test.

- [ ] **Step 5: Implement `FiestaClient.swift`**

```swift
import Foundation

/// HTTP client for a FiestaBoard instance.
///
/// Deliberately thin: no retry, no caching, no request coalescing. The
/// polling cadence in `PanelStore` is the retry policy, and layering a
/// second one underneath it only multiplies requests during an outage.
public final class FiestaClient: @unchecked Sendable {

    public let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()

    public init(baseURL: URL, session: URLSession? = nil) {
        // Normalising here means every caller can pass whatever the user typed.
        var normalized = baseURL.absoluteString
        while normalized.hasSuffix("/") { normalized.removeLast() }
        self.baseURL = URL(string: normalized) ?? baseURL

        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.httpCookieStorage = HTTPCookieStorage.shared
            config.httpShouldSetCookies = true
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.timeoutIntervalForRequest = 10
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: Endpoints

    public func authStatus() async throws -> AuthStatus {
        try await get("/auth/status")
    }

    public func login(username: String, password: String) async throws {
        // remember_me is always true: a 7-day session on a wall-mounted TV
        // means a password prompt on a Siri Remote every week.
        let body: [String: Any] = ["username": username,
                                   "password": password,
                                   "remember_me": true]
        _ = try await send(method: "POST", path: "/auth/login", body: body)
    }

    public func panels() async throws -> [Panel] {
        struct Envelope: Decodable { let panels: [Panel] }
        let envelope: Envelope = try await get("/panels")
        return envelope.panels
    }

    /// `ref` is a panel id or its short code, so "1" is valid.
    public func panel(ref: String) async throws -> Panel {
        try await get("/panel/\(ref)")
    }

    public func frame(ref: String) async throws -> PanelFrame {
        try await get("/panel/\(ref)/frame")
    }

    public func updatePanel(id: String,
                            diagonal: Double? = nil,
                            aspectW: Double? = nil,
                            aspectH: Double? = nil,
                            calibration: Double? = nil,
                            animationsEnabled: Bool? = nil) async throws -> PanelUpdateResult {
        var body: [String: Any] = [:]
        // Only send what was asked for: PanelUpdate treats every field as
        // optional, and sending nulls would clear settings we never touched.
        if let diagonal { body["screen_diagonal_inches"] = diagonal }
        if let aspectW { body["screen_aspect_w"] = aspectW }
        if let aspectH { body["screen_aspect_h"] = aspectH }
        if let calibration { body["calibration_scale"] = calibration }
        if let animationsEnabled { body["animations_enabled"] = animationsEnabled }

        let data = try await send(method: "PATCH", path: "/panels/\(id)", body: body)
        struct Envelope: Decodable {
            let panel: Panel
            let incompatibleReferences: [IncompatibleReference]?
            enum CodingKeys: String, CodingKey {
                case panel
                case incompatibleReferences = "incompatible_references"
            }
        }
        do {
            let envelope = try decoder.decode(Envelope.self, from: data)
            return PanelUpdateResult(panel: envelope.panel,
                                     incompatibleReferences: envelope.incompatibleReferences ?? [])
        } catch {
            throw FiestaError.decoding("\(error)")
        }
    }

    // MARK: Plumbing

    private func url(for path: String) -> URL {
        URL(string: baseURL.absoluteString + path) ?? baseURL
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await send(method: "GET", path: path, body: nil)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw FiestaError.decoding("\(error)")
        }
    }

    @discardableResult
    private func send(method: String, path: String, body: [String: Any]?) async throws -> Data {
        var request = URLRequest(url: url(for: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FiestaError.transport("\(error)")
        }

        guard let http = response as? HTTPURLResponse else {
            throw FiestaError.transport("non-HTTP response")
        }

        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            throw FiestaError.unauthorized
        case 404:
            throw FiestaError.notFound(Self.detail(from: data) ?? "Not found")
        case 409:
            // The middleware answers 409 for "no user provisioned yet".
            throw FiestaError.setupRequired
        default:
            throw FiestaError.http(http.statusCode)
        }
    }

    private static func detail(from data: Data) -> String? {
        struct Detail: Decodable { let detail: String? }
        return try? JSONDecoder().decode(Detail.self, from: data).detail
    }
}
```

- [ ] **Step 6: Run tests, then fix the date parsing the failure exposes**

Run: `./build-and-run.sh --test`
Expected: `testFrameDecodesCharactersAndTimestamp` FAILS — the fixture's
`2026-09-19T10:30:00Z` has no fractional seconds, and the formatter
demands them. Both shapes occur in the wild, so parse both:

```swift
extension ISO8601DateFormatter {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// The server emits fractional seconds on some paths and not others.
    static func fiestaDate(from string: String) -> Date? {
        withFraction.date(from: string) ?? plain.date(from: string)
    }
}
```

Replace the `updatedAt` line in `PanelFrame.init(from:)` with
`updatedAt = ISO8601DateFormatter.fiestaDate(from: raw)` and delete the
old `static let fiesta`.

- [ ] **Step 7: Run tests to verify they pass**

Run: `./build-and-run.sh --test`
Expected: PASS — all `FiestaClientTests` green.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(core): typed models and a FiestaBoard HTTP client

Covers the six endpoints the TV needs: auth status and login, the
authenticated panel list and PATCH, and the two public viewer endpoints
a TV can read with no session.

The client is deliberately retry-free — the viewer's poll cadence is the
retry policy, and a second one underneath it would only multiply
requests during an outage.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: `Credentials` and the session state machine

**Files:**
- Create: `Sources/Core/Credentials.swift`, `Sources/Core/ConnectionStore.swift`, `Tests/CredentialsTests.swift`, `Tests/ConnectionStoreTests.swift`

**Interfaces:**
- Consumes: `FiestaClient`, `FiestaError`, `AuthStatus`, `Panel` (Task 4)
- Produces:
  - `CredentialStore` — protocol: `save(_:for:) throws`, `load(for:) -> StoredCredential?`, `delete(for:) throws`
  - `KeychainCredentialStore: CredentialStore` — `init(service:)`
  - `InMemoryCredentialStore: CredentialStore` — test double
  - `StoredCredential` — `username: String`, `password: String`
  - `SavedConnection` — `host: URL`, `displayName: String`, `defaultPanelRef: String?`
  - `ConnectionStore` — `init(defaults:credentials:clientFactory:)`, `connect(to:displayName:) async throws -> ConnectResult`, `signIn(username:password:) async throws`, `authorized<T>(_ operation:) async throws -> T`, `signOut()`, `forget()`, `saved: SavedConnection?`, `client: FiestaClient?`
  - `ConnectResult` — `enum { case ready, needsSignIn, needsSetup }`

- [ ] **Step 1: Write the failing credential tests**

`Tests/CredentialsTests.swift`:

```swift
import XCTest
@testable import FiestaBoardTV

final class CredentialsTests: XCTestCase {

    private var service: String!
    private var store: KeychainCredentialStore!

    override func setUp() {
        super.setUp()
        // Never touch the developer's real keychain.
        service = "com.fiestaboard.tv.tests.\(UUID().uuidString)"
        store = KeychainCredentialStore(service: service)
    }

    override func tearDown() {
        try? store.delete(for: "host")
        super.tearDown()
    }

    func testRoundTripsACredential() throws {
        try store.save(StoredCredential(username: "jeffre", password: "hunter2"), for: "host")
        let loaded = store.load(for: "host")
        XCTAssertEqual(loaded?.username, "jeffre")
        XCTAssertEqual(loaded?.password, "hunter2")
    }

    func testMissingCredentialIsNil() {
        XCTAssertNil(store.load(for: "never-saved"))
    }

    /// Saving twice must update rather than throw a duplicate-item error.
    func testSaveOverwrites() throws {
        try store.save(StoredCredential(username: "a", password: "1"), for: "host")
        try store.save(StoredCredential(username: "b", password: "2"), for: "host")
        XCTAssertEqual(store.load(for: "host")?.username, "b")
        XCTAssertEqual(store.load(for: "host")?.password, "2")
    }

    func testDeleteRemoves() throws {
        try store.save(StoredCredential(username: "a", password: "1"), for: "host")
        try store.delete(for: "host")
        XCTAssertNil(store.load(for: "host"))
    }

    func testDeletingSomethingAbsentIsNotAnError() {
        XCTAssertNoThrow(try store.delete(for: "never-saved"))
    }

    func testPasswordsWithNonASCIISurvive() throws {
        try store.save(StoredCredential(username: "jeffre", password: "pä§§wörd✓"), for: "host")
        XCTAssertEqual(store.load(for: "host")?.password, "pä§§wörd✓")
    }

    func testInMemoryStoreMatchesTheProtocol() throws {
        let mem = InMemoryCredentialStore()
        try mem.save(StoredCredential(username: "a", password: "1"), for: "h")
        XCTAssertEqual(mem.load(for: "h")?.username, "a")
        try mem.delete(for: "h")
        XCTAssertNil(mem.load(for: "h"))
    }
}
```

- [ ] **Step 2: Write the failing connection-store tests**

`Tests/ConnectionStoreTests.swift`:

```swift
import XCTest
@testable import FiestaBoardTV

@MainActor
final class ConnectionStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var credentials: InMemoryCredentialStore!
    private var store: ConnectionStore!
    private let host = URL(string: "http://192.168.1.50:4420")!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        defaults = UserDefaults(suiteName: "tv.connection.\(UUID().uuidString)")!
        credentials = InMemoryCredentialStore()
        store = ConnectionStore(defaults: defaults,
                                credentials: credentials,
                                clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    func testConnectingToAnOpenInstanceIsImmediatelyReady() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/auth/status")
        let result = try await store.connect(to: host, displayName: "FiestaBoard")
        XCTAssertEqual(result, .ready)
        XCTAssertEqual(store.saved?.host, host)
        XCTAssertNotNil(store.client)
    }

    func testConnectingToALockedInstanceAsksForSignIn() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/auth/status")
        let result = try await store.connect(to: host, displayName: "FiestaBoard")
        XCTAssertEqual(result, .needsSignIn)
    }

    /// An instance with auth on and no account yet cannot be signed into from
    /// a TV — the first user must be created in the web app.
    func testInstanceAwaitingSetupIsCalledOut() async throws {
        let json = """
        {"enabled":true,"setup_required":true,"authenticated":false,
         "username":null,"mode":"undecided","first_run":true}
        """
        StubURLProtocol.enqueue(.json(json), for: "/auth/status")
        let result = try await store.connect(to: host, displayName: "FiestaBoard")
        XCTAssertEqual(result, .needsSetup)
    }

    func testAnAlreadyAuthenticatedSessionIsReady() async throws {
        let json = """
        {"enabled":true,"setup_required":false,"authenticated":true,
         "username":"jeffre","mode":"enabled","first_run":false}
        """
        StubURLProtocol.enqueue(.json(json), for: "/auth/status")
        XCTAssertEqual(try await store.connect(to: host, displayName: "FiestaBoard"), .ready)
    }

    func testSignInStoresTheCredential() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/auth/status")
        _ = try await store.connect(to: host, displayName: "FiestaBoard")

        StubURLProtocol.enqueue(.json(Fixtures.loginOK), for: "/auth/login")
        try await store.signIn(username: "jeffre", password: "hunter2")

        let saved = credentials.load(for: host.absoluteString)
        XCTAssertEqual(saved?.username, "jeffre")
        XCTAssertEqual(saved?.password, "hunter2")
    }

    func testFailedSignInStoresNothing() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/auth/status")
        _ = try await store.connect(to: host, displayName: "FiestaBoard")

        StubURLProtocol.enqueue(.json(#"{"detail":"bad"}"#, status: 401), for: "/auth/login")
        do {
            try await store.signIn(username: "jeffre", password: "wrong")
            XCTFail("expected unauthorized")
        } catch FiestaError.unauthorized {}

        XCTAssertNil(credentials.load(for: host.absoluteString))
    }

    /// The core recovery behaviour: an expired cookie re-logs in silently.
    func testA401TriggersOneSilentReLoginAndRetriesTheOperation() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/auth/status")
        _ = try await store.connect(to: host, displayName: "FiestaBoard")
        try credentials.save(StoredCredential(username: "jeffre", password: "hunter2"),
                             for: host.absoluteString)

        StubURLProtocol.enqueue(.json(#"{"detail":"Not authenticated"}"#, status: 401), for: "/panels")
        StubURLProtocol.enqueue(.json(Fixtures.loginOK), for: "/auth/login")
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/panels")

        let panels = try await store.authorized { try await $0.panels() }
        XCTAssertEqual(panels.count, 1)

        let paths = StubURLProtocol.requests.map(\.url.path)
        XCTAssertEqual(paths, ["/auth/status", "/panels", "/auth/login", "/panels"])
    }

    /// One attempt, not a loop: a changed password must surface, not spin.
    func testASecond401AfterReLoginSurfaces() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/auth/status")
        _ = try await store.connect(to: host, displayName: "FiestaBoard")
        try credentials.save(StoredCredential(username: "jeffre", password: "stale"),
                             for: host.absoluteString)

        StubURLProtocol.enqueue(.json(#"{"detail":"no"}"#, status: 401), for: "/panels")
        StubURLProtocol.enqueue(.json(Fixtures.loginOK), for: "/auth/login")
        StubURLProtocol.enqueue(.json(#"{"detail":"no"}"#, status: 401), for: "/panels")

        do {
            _ = try await store.authorized { try await $0.panels() }
            XCTFail("expected unauthorized")
        } catch FiestaError.unauthorized {}

        XCTAssertEqual(StubURLProtocol.requests.filter { $0.url.path == "/auth/login" }.count, 1,
                       "exactly one re-login attempt")
    }

    func testA401WithNoStoredCredentialSurfacesImmediately() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/auth/status")
        _ = try await store.connect(to: host, displayName: "FiestaBoard")

        StubURLProtocol.enqueue(.json(#"{"detail":"no"}"#, status: 401), for: "/panels")
        do {
            _ = try await store.authorized { try await $0.panels() }
            XCTFail("expected unauthorized")
        } catch FiestaError.unauthorized {}

        XCTAssertFalse(StubURLProtocol.requests.contains { $0.url.path == "/auth/login" })
    }

    func testTheConnectionAndDefaultPanelSurviveARestart() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/auth/status")
        _ = try await store.connect(to: host, displayName: "Kitchen Board")
        store.setDefaultPanel(ref: "abc123def456")

        let reloaded = ConnectionStore(defaults: defaults,
                                       credentials: credentials,
                                       clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        XCTAssertEqual(reloaded.saved?.host, host)
        XCTAssertEqual(reloaded.saved?.displayName, "Kitchen Board")
        XCTAssertEqual(reloaded.saved?.defaultPanelRef, "abc123def456")
        XCTAssertNotNil(reloaded.client, "a restored connection must have a usable client")
    }

    func testSignOutClearsTheCredentialButKeepsTheHost() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/auth/status")
        _ = try await store.connect(to: host, displayName: "FiestaBoard")
        try credentials.save(StoredCredential(username: "a", password: "1"), for: host.absoluteString)

        store.signOut()
        XCTAssertNil(credentials.load(for: host.absoluteString))
        XCTAssertEqual(store.saved?.host, host)
    }

    func testForgetClearsEverything() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/auth/status")
        _ = try await store.connect(to: host, displayName: "FiestaBoard")
        try credentials.save(StoredCredential(username: "a", password: "1"), for: host.absoluteString)

        store.forget()
        XCTAssertNil(store.saved)
        XCTAssertNil(store.client)
        XCTAssertNil(credentials.load(for: host.absoluteString))
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `./build-and-run.sh --test`
Expected: FAIL — `KeychainCredentialStore`, `ConnectionStore` undefined.

- [ ] **Step 4: Implement `Credentials.swift`**

```swift
import Foundation
import Security

public struct StoredCredential: Equatable, Sendable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

/// Where the app keeps the credential it re-logs in with.
///
/// A protocol so tests never touch a real keychain, and so the Android port
/// has an obvious seam (EncryptedSharedPreferences).
public protocol CredentialStore: AnyObject {
    func save(_ credential: StoredCredential, for account: String) throws
    func load(for account: String) -> StoredCredential?
    func delete(for account: String) throws
}

public enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
}

/// Keychain-backed store.
///
/// The username is the keychain account and the password is the secret, so
/// one host maps to one item. Items are `WhenUnlockedThisDeviceOnly`: a TV
/// credential has no business syncing to a phone.
public final class KeychainCredentialStore: CredentialStore {

    private let service: String

    public init(service: String = "com.fiestaboard.tv.credentials") {
        self.service = service
    }

    private func query(for account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func save(_ credential: StoredCredential, for account: String) throws {
        // The stored blob is "username\npassword" so one item carries both.
        let blob = Data("\(credential.username)\n\(credential.password)".utf8)

        let update: [String: Any] = [kSecValueData as String: blob]
        let status = SecItemUpdate(query(for: account) as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }

        guard status == errSecItemNotFound else { throw KeychainError.unexpectedStatus(status) }

        var insert = query(for: account)
        insert[kSecValueData as String] = blob
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
    }

    public func load(for account: String) -> StoredCredential? {
        var q = query(for: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let blob = String(data: data, encoding: .utf8) else { return nil }

        // Split on the FIRST newline only: a password may contain more.
        guard let separator = blob.firstIndex(of: "\n") else { return nil }
        return StoredCredential(username: String(blob[blob.startIndex..<separator]),
                                password: String(blob[blob.index(after: separator)...]))
    }

    public func delete(for account: String) throws {
        let status = SecItemDelete(query(for: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

/// Test double.
public final class InMemoryCredentialStore: CredentialStore {
    private var items: [String: StoredCredential] = [:]

    public init() {}

    public func save(_ credential: StoredCredential, for account: String) throws {
        items[account] = credential
    }

    public func load(for account: String) -> StoredCredential? { items[account] }

    public func delete(for account: String) throws { items[account] = nil }
}
```

- [ ] **Step 5: Implement `ConnectionStore.swift`**

```swift
import Foundation

/// The FiestaBoard this TV is paired with.
public struct SavedConnection: Codable, Equatable, Sendable {
    public var host: URL
    public var displayName: String
    /// Panel to open straight into at launch, if the user chose one.
    public var defaultPanelRef: String?
}

public enum ConnectResult: Equatable, Sendable {
    case ready
    case needsSignIn
    /// Auth is on but no account exists — only the web app can create one.
    case needsSetup
}

/// Owns which board we are talking to and whether we are allowed to.
///
/// Deliberately not an ObservableObject: Core stays free of Combine so the
/// Android port maps onto a ViewModel without unpicking Apple types. The UI
/// layer wraps this in an observable of its own.
public final class ConnectionStore: @unchecked Sendable {

    private enum Keys {
        static let connection = "fiestaboard.connection"
    }

    private let defaults: UserDefaults
    private let credentials: CredentialStore
    private let clientFactory: (URL) -> FiestaClient

    public private(set) var saved: SavedConnection?
    public private(set) var client: FiestaClient?

    public init(defaults: UserDefaults = .standard,
                credentials: CredentialStore = KeychainCredentialStore(),
                clientFactory: @escaping (URL) -> FiestaClient = { FiestaClient(baseURL: $0) }) {
        self.defaults = defaults
        self.credentials = credentials
        self.clientFactory = clientFactory

        if let data = defaults.data(forKey: Keys.connection),
           let connection = try? JSONDecoder().decode(SavedConnection.self, from: data) {
            self.saved = connection
            // Restore the client too: a TV that reboots must come straight
            // back up on its panel without a round trip through Connect.
            self.client = clientFactory(connection.host)
        }
    }

    // MARK: Connecting

    public func connect(to host: URL, displayName: String) async throws -> ConnectResult {
        let client = clientFactory(host)
        let status = try await client.authStatus()

        self.client = client
        let connection = SavedConnection(host: host,
                                         displayName: displayName,
                                         defaultPanelRef: saved?.host == host ? saved?.defaultPanelRef : nil)
        persist(connection)

        if status.setupRequired { return .needsSetup }
        if !status.enabled || status.authenticated { return .ready }

        // Auth is on and we are not authenticated. If we already hold a
        // credential for this host, spend it now rather than making someone
        // retype a password on a remote.
        if let stored = credentials.load(for: host.absoluteString) {
            do {
                try await client.login(username: stored.username, password: stored.password)
                return .ready
            } catch {
                return .needsSignIn
            }
        }
        return .needsSignIn
    }

    public func signIn(username: String, password: String) async throws {
        guard let client, let saved else { throw FiestaError.transport("not connected") }
        try await client.login(username: username, password: password)
        // Only persist a credential the server just accepted.
        try? credentials.save(StoredCredential(username: username, password: password),
                              for: saved.host.absoluteString)
    }

    // MARK: Authorized operations

    /// Run an authenticated request, recovering once from an expired session.
    ///
    /// Exactly one silent re-login: a stale cookie is routine and should be
    /// invisible, but a changed password must surface rather than spin.
    public func authorized<T>(_ operation: (FiestaClient) async throws -> T) async throws -> T {
        guard let client, let saved else { throw FiestaError.transport("not connected") }
        do {
            return try await operation(client)
        } catch FiestaError.unauthorized {
            guard let stored = credentials.load(for: saved.host.absoluteString) else {
                throw FiestaError.unauthorized
            }
            try await client.login(username: stored.username, password: stored.password)
            return try await operation(client)
        }
    }

    // MARK: Preferences

    public func setDefaultPanel(ref: String?) {
        guard var connection = saved else { return }
        connection.defaultPanelRef = ref
        persist(connection)
    }

    public func signOut() {
        guard let saved else { return }
        try? credentials.delete(for: saved.host.absoluteString)
    }

    public func forget() {
        if let saved { try? credentials.delete(for: saved.host.absoluteString) }
        defaults.removeObject(forKey: Keys.connection)
        self.saved = nil
        self.client = nil
    }

    private func persist(_ connection: SavedConnection) {
        saved = connection
        if let data = try? JSONEncoder().encode(connection) {
            defaults.set(data, forKey: Keys.connection)
        }
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `./build-and-run.sh --test`
Expected: PASS.

`testA401TriggersOneSilentReLoginAndRetriesTheOperation` asserts the exact
request sequence. If it fails on ordering, print
`StubURLProtocol.requests.map(\.url.path)` — the sequence, not the count,
is what proves the recovery works.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(core): keychain credentials and the connection state machine

Stores the credential rather than only the cookie, because a TV whose
30-day session lapses should come back on its own instead of asking for
a password on a Siri Remote.

An expired session re-logs in silently exactly once: routine expiry is
invisible, a changed password surfaces.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: `Discovery`

**Files:**
- Create: `Sources/Core/Discovery.swift`, `Sources/Core/BonjourDiscovery.swift`, `Tests/DiscoveryTests.swift`

**Interfaces:**
- Consumes: `FiestaClient` (Task 4)
- Produces:
  - `DiscoveredBoard` — `id: String`, `name: String`, `host: URL`, `Equatable`, `Identifiable`
  - `BoardDiscovering` — protocol: `func boards() -> AsyncStream<[DiscoveredBoard]>`, `func stop()`
  - `BonjourDiscovery: BoardDiscovering` — `init(probe:)`
  - `DiscoveryCandidate` — `name: String`, `host: String`, `port: Int`, `txt: [String: String]`
  - `DiscoveryFilter.isFiestaBoard(_:) -> Bool`
  - `DiscoveryFilter.url(for:) -> URL?`
  - `ManualAddress.parse(_:) -> URL?`

- [ ] **Step 1: Write the failing tests**

Discovery's testable core is the filter and the address parser — the
`NWBrowser` plumbing around them is Apple's and is exercised by running
the app, not by unit tests.

`Tests/DiscoveryTests.swift`:

```swift
import XCTest
@testable import FiestaBoardTV

final class DiscoveryTests: XCTestCase {

    private func candidate(name: String = "FiestaBoard",
                           host: String = "fiestaboard.local",
                           port: Int = 4420,
                           txt: [String: String] = ["product": "FiestaBoard", "path": "/"]) -> DiscoveryCandidate {
        DiscoveryCandidate(name: name, host: host, port: port, txt: txt)
    }

    // MARK: Filtering

    /// The instance advertises _http._tcp with product=FiestaBoard in TXT,
    /// so that record is what separates it from every printer on the LAN.
    func testAcceptsAServiceAdvertisingTheProductRecord() {
        XCTAssertTrue(DiscoveryFilter.isFiestaBoard(candidate()))
    }

    func testTxtMatchIsCaseInsensitive() {
        XCTAssertTrue(DiscoveryFilter.isFiestaBoard(candidate(txt: ["product": "fiestaboard"])))
        XCTAssertTrue(DiscoveryFilter.isFiestaBoard(candidate(txt: ["Product": "FiestaBoard"])))
    }

    func testRejectsUnrelatedHTTPServices() {
        XCTAssertFalse(DiscoveryFilter.isFiestaBoard(candidate(name: "Brother HL-2270DW", txt: [:])))
        XCTAssertFalse(DiscoveryFilter.isFiestaBoard(candidate(name: "Living Room TV", txt: ["product": "Roku"])))
    }

    /// Fallback for instances too old to publish the TXT record: the service
    /// name itself is "FiestaBoard._http._tcp.local."
    func testFallsBackToTheServiceName() {
        XCTAssertTrue(DiscoveryFilter.isFiestaBoard(candidate(name: "FiestaBoard", txt: [:])))
        XCTAssertTrue(DiscoveryFilter.isFiestaBoard(candidate(name: "fiestaboard", txt: [:])))
    }

    // MARK: URL construction

    func testBuildsAnHTTPURLFromHostAndPort() {
        let url = DiscoveryFilter.url(for: candidate())
        XCTAssertEqual(url?.absoluteString, "http://fiestaboard.local:4420")
    }

    func testAppendsDotLocalWhenBonjourOmitsIt() {
        XCTAssertEqual(DiscoveryFilter.url(for: candidate(host: "fiestaboard"))?.absoluteString,
                       "http://fiestaboard.local:4420")
    }

    /// Bonjour hostnames arrive with a trailing dot; URL(string:) chokes on it.
    func testStripsTheTrailingDot() {
        XCTAssertEqual(DiscoveryFilter.url(for: candidate(host: "fiestaboard.local."))?.absoluteString,
                       "http://fiestaboard.local:4420")
    }

    func testPortEightyIsImplicit() {
        XCTAssertEqual(DiscoveryFilter.url(for: candidate(host: "board.local", port: 80))?.absoluteString,
                       "http://board.local")
    }

    func testIPv6LiteralsAreBracketed() {
        XCTAssertEqual(DiscoveryFilter.url(for: candidate(host: "fe80::1"))?.absoluteString,
                       "http://[fe80::1]:4420")
    }

    // MARK: Manual entry

    /// Typing on a Siri Remote is miserable, so accept the least possible.
    func testBareIPGetsSchemeAndDefaultPort() {
        XCTAssertEqual(ManualAddress.parse("192.168.1.50")?.absoluteString,
                       "http://192.168.1.50:4420")
    }

    func testBareHostnameGetsSchemeAndDefaultPort() {
        XCTAssertEqual(ManualAddress.parse("fiestaboard.local")?.absoluteString,
                       "http://fiestaboard.local:4420")
    }

    func testExplicitPortIsHonoured() {
        XCTAssertEqual(ManualAddress.parse("192.168.1.50:8080")?.absoluteString,
                       "http://192.168.1.50:8080")
    }

    func testFullURLPassesThrough() {
        XCTAssertEqual(ManualAddress.parse("http://192.168.1.50:4420")?.absoluteString,
                       "http://192.168.1.50:4420")
    }

    func testHTTPSIsPreserved() {
        XCTAssertEqual(ManualAddress.parse("https://board.example.com")?.absoluteString,
                       "https://board.example.com")
    }

    func testWhitespaceAndTrailingSlashesAreTrimmed() {
        XCTAssertEqual(ManualAddress.parse("  192.168.1.50/  ")?.absoluteString,
                       "http://192.168.1.50:4420")
    }

    func testBlankInputIsRejected() {
        XCTAssertNil(ManualAddress.parse(""))
        XCTAssertNil(ManualAddress.parse("   "))
    }

    func testTrailingPathIsPreserved() {
        // Reverse-proxied installs live under a subpath.
        XCTAssertEqual(ManualAddress.parse("http://nas.local/fiestaboard")?.absoluteString,
                       "http://nas.local/fiestaboard")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./build-and-run.sh --test`
Expected: FAIL — `DiscoveryCandidate`, `DiscoveryFilter`, `ManualAddress` undefined.

- [ ] **Step 3: Implement `Discovery.swift`**

```swift
import Foundation

/// A FiestaBoard found on the network, ready to connect to.
public struct DiscoveredBoard: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let host: URL

    public init(id: String, name: String, host: URL) {
        self.id = id
        self.name = name
        self.host = host
    }
}

/// A Bonjour service before we have decided whether it is ours.
public struct DiscoveryCandidate: Equatable, Sendable {
    public let name: String
    public let host: String
    public let port: Int
    public let txt: [String: String]

    public init(name: String, host: String, port: Int, txt: [String: String]) {
        self.name = name
        self.host = host
        self.port = port
        self.txt = txt
    }
}

/// Source of discovered boards. A protocol so the UI can be driven by a
/// fixed list in tests and previews, and so the Android port has an obvious
/// seam (`NsdManager`).
public protocol BoardDiscovering: AnyObject {
    func boards() -> AsyncStream<[DiscoveredBoard]>
    func stop()
}

public enum DiscoveryFilter {

    public static let defaultPort = 4420
    private static let productKey = "product"
    private static let productValue = "fiestaboard"

    /// FiestaBoard advertises `_http._tcp` with `product=FiestaBoard` in TXT.
    /// Until a dedicated `_fiestaboard._tcp` type exists, that record is what
    /// separates it from every other HTTP service on the network; the service
    /// name is a fallback for instances too old to publish TXT.
    public static func isFiestaBoard(_ candidate: DiscoveryCandidate) -> Bool {
        for (key, value) in candidate.txt where key.lowercased() == productKey {
            if value.lowercased() == productValue { return true }
        }
        return candidate.name.lowercased().hasPrefix(productValue)
    }

    public static func url(for candidate: DiscoveryCandidate) -> URL? {
        var host = candidate.host
        while host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty else { return nil }

        // A bare Bonjour hostname resolves only with the .local suffix.
        let isIPv4 = host.allSatisfy { $0.isNumber || $0 == "." }
        let isIPv6 = host.contains(":")
        if !host.contains("."), !isIPv6 {
            host += ".local"
        }
        if isIPv6 { host = "[\(host)]" }
        _ = isIPv4

        let authority = candidate.port == 80 ? host : "\(host):\(candidate.port)"
        return URL(string: "http://\(authority)")
    }
}

/// Parses whatever someone managed to type on a Siri Remote.
public enum ManualAddress {

    public static func parse(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty else { return nil }

        if text.lowercased().hasPrefix("http://") || text.lowercased().hasPrefix("https://") {
            return URL(string: text)
        }

        // No scheme. Add the default port unless one was typed, so the
        // common case is four numbers and nothing else.
        let hasPort = text.split(separator: "/").first.map { $0.contains(":") } ?? false
        let hasPath = text.contains("/")
        if hasPort || hasPath {
            return URL(string: "http://\(text)")
        }
        return URL(string: "http://\(text):\(DiscoveryFilter.defaultPort)")
    }
}
```

- [ ] **Step 4: Implement `BonjourDiscovery.swift`**

```swift
import Foundation
import Network

/// Browses `_http._tcp` and keeps the services that look like a FiestaBoard,
/// confirming each with a real request before offering it.
///
/// The confirmation matters: TXT records are advertised, not proven, and a
/// list that offers an unreachable board is worse than a short list.
public final class BonjourDiscovery: BoardDiscovering, @unchecked Sendable {

    private let queue = DispatchQueue(label: "com.fiestaboard.tv.discovery")
    private var browser: NWBrowser?
    private var connections: [NWConnection] = []
    private var found: [String: DiscoveredBoard] = [:]
    private var continuation: AsyncStream<[DiscoveredBoard]>.Continuation?

    /// Confirms a candidate host is really a FiestaBoard. Injectable so tests
    /// and previews can skip the network.
    private let probe: @Sendable (URL) async -> Bool

    public init(probe: (@Sendable (URL) async -> Bool)? = nil) {
        self.probe = probe ?? { url in
            // /auth/status is public on every instance and cheap.
            (try? await FiestaClient(baseURL: url).authStatus()) != nil
        }
    }

    public func boards() -> AsyncStream<[DiscoveredBoard]> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in self?.stop() }
            self.startBrowsing()
        }
    }

    private func startBrowsing() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_http._tcp", domain: nil),
                                using: parameters)
        self.browser = browser

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            for result in results {
                guard case let .service(name, _, _, _) = result.endpoint else { continue }
                var txt: [String: String] = [:]
                if case let .bonjour(record) = result.metadata {
                    for (key, value) in record.dictionary { txt[key] = value }
                }
                let candidate = DiscoveryCandidate(name: name,
                                                   host: name,
                                                   port: DiscoveryFilter.defaultPort,
                                                   txt: txt)
                guard DiscoveryFilter.isFiestaBoard(candidate) else { continue }
                self.resolve(result.endpoint, name: name, txt: txt)
            }
        }

        browser.start(queue: queue)
    }

    /// Bonjour gives a service endpoint; a URL needs a hostname and port, so
    /// open a connection far enough to read the resolved path, then drop it.
    private func resolve(_ endpoint: NWEndpoint, name: String, txt: [String: String]) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        queue.async { self.connections.append(connection) }

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                guard let path = connection.currentPath,
                      let remote = path.remoteEndpoint,
                      case let .hostPort(host, port) = remote else {
                    connection.cancel()
                    return
                }
                let hostString: String
                switch host {
                case .name(let n, _): hostString = n
                case .ipv4(let address): hostString = "\(address)".components(separatedBy: "%").first ?? "\(address)"
                case .ipv6(let address): hostString = "\(address)".components(separatedBy: "%").first ?? "\(address)"
                @unknown default: hostString = name
                }
                connection.cancel()

                let candidate = DiscoveryCandidate(name: name,
                                                   host: hostString,
                                                   port: Int(port.rawValue),
                                                   txt: txt)
                guard let url = DiscoveryFilter.url(for: candidate) else { return }
                Task { await self.confirm(url: url, name: name) }

            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func confirm(url: URL, name: String) async {
        guard await probe(url) else { return }
        queue.async {
            let board = DiscoveredBoard(id: url.absoluteString, name: name, host: url)
            guard self.found[board.id] != board else { return }
            self.found[board.id] = board
            let sorted = self.found.values.sorted { $0.name < $1.name }
            self.continuation?.yield(sorted)
        }
    }

    public func stop() {
        queue.async {
            self.browser?.cancel()
            self.browser = nil
            self.connections.forEach { $0.cancel() }
            self.connections = []
            self.continuation?.finish()
            self.continuation = nil
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `./build-and-run.sh --test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(core): mDNS discovery and manual address entry

Browses _http._tcp and keeps services advertising product=FiestaBoard,
falling back to the service name for instances too old to publish the
TXT record. Every candidate is confirmed with a real /auth/status
request before it is offered — a TXT record is advertised, not proven,
and a list containing an unreachable board is worse than a short list.

Manual entry accepts the least someone could reasonably type: a bare IP
becomes http://<ip>:4420.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: `BoardLayout`

**Files:**
- Create: `Sources/Core/BoardLayout.swift`, `Tests/BoardLayoutTests.swift`

**Interfaces:**
- Consumes: `BoardGeometry` (Task 3), `BoardCell`, `BoardColor`, `Code62Glyph` (Task 2)
- Produces:
  - `TileRect` — `x`, `y`, `width`, `height`, `radius`, `cell: BoardCell`, `row: Int`, `col: Int`
  - `BoardLayout` — `tiles: [TileRect]`, `width: Double`, `height: Double`, `tileHeight: Double`, `fontSize: Double`
  - `BoardLayout.make(rows:cols:cells:tileHeight:) -> BoardLayout`
  - `BoardLayout.fitting(rows:cols:cells:in:mode:diagonalInches:calibration:colPitchIn:) throws -> BoardLayout`
  - `BoardSizing` — `enum { case fit, trueScale }`

**Why this is its own file:** splitting the pure layout from the painting is
what lets the renderer be tested by arithmetic instead of by screenshots,
and it is the half that transcribes directly to Compose later.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import FiestaBoardTV

final class BoardLayoutTests: XCTestCase {

    private func cells(rows: Int, cols: Int, code: Int = 1) -> [[BoardCell]] {
        Array(repeating: Array(repeating: BoardTables.cell(forCode: code, code62: .degree), count: cols),
              count: rows)
    }

    func testTileCountMatchesTheGrid() {
        let layout = BoardLayout.make(rows: 6, cols: 22, cells: cells(rows: 6, cols: 22), tileHeight: 20)
        XCTAssertEqual(layout.tiles.count, 132)
    }

    /// Tile geometry is the whole fidelity story: width 0.70·h, gutter
    /// 0.145·h on both axes, radius 0.075·h.
    func testTileDimensionsFollowTheRatios() {
        let layout = BoardLayout.make(rows: 1, cols: 1, cells: cells(rows: 1, cols: 1), tileHeight: 100)
        let tile = layout.tiles[0]
        XCTAssertEqual(tile.height, 100, accuracy: 1e-9)
        XCTAssertEqual(tile.width, 70, accuracy: 1e-9)
        XCTAssertEqual(tile.radius, 7.5, accuracy: 1e-9)
    }

    func testTilesArePitchedByWidthPlusGutter() {
        let layout = BoardLayout.make(rows: 2, cols: 2, cells: cells(rows: 2, cols: 2), tileHeight: 100)
        let colPitch = 70.0 + 14.5
        let rowPitch = 100.0 + 14.5
        XCTAssertEqual(layout.tiles[0].x, 0, accuracy: 1e-9)
        XCTAssertEqual(layout.tiles[1].x, colPitch, accuracy: 1e-9)
        XCTAssertEqual(layout.tiles[0].y, 0, accuracy: 1e-9)
        XCTAssertEqual(layout.tiles[2].y, rowPitch, accuracy: 1e-9)
    }

    /// The grid is borderless: no outer gutter, so the board can run to the
    /// screen edge the way the web viewer does.
    func testOverallSizeExcludesTheOuterGutter() {
        let layout = BoardLayout.make(rows: 3, cols: 15, cells: cells(rows: 3, cols: 15), tileHeight: 100)
        XCTAssertEqual(layout.width, 15 * 84.5 - 14.5, accuracy: 1e-9)
        XCTAssertEqual(layout.height, 3 * 114.5 - 14.5, accuracy: 1e-9)
    }

    func testTilesCarryTheirCellAndCoordinates() {
        var grid = cells(rows: 2, cols: 2)
        grid[1][0] = .color(.red)
        let layout = BoardLayout.make(rows: 2, cols: 2, cells: grid, tileHeight: 10)
        let tile = layout.tiles.first { $0.row == 1 && $0.col == 0 }
        XCTAssertEqual(tile?.cell, .color(.red))
    }

    /// A frame whose shape disagrees with the panel config must not crash —
    /// a reshape in flight is a normal, transient state.
    func testRaggedOrShortFramesPadWithBlanks() {
        let ragged: [[BoardCell]] = [[.character("A")]]
        let layout = BoardLayout.make(rows: 2, cols: 3, cells: ragged, tileHeight: 10)
        XCTAssertEqual(layout.tiles.count, 6)
        XCTAssertEqual(layout.tiles.first { $0.row == 0 && $0.col == 0 }?.cell, .character("A"))
        XCTAssertEqual(layout.tiles.first { $0.row == 0 && $0.col == 2 }?.cell, .blank)
        XCTAssertEqual(layout.tiles.first { $0.row == 1 && $0.col == 0 }?.cell, .blank)
    }

    func testOversizedFramesAreCroppedNotCrashed() {
        let layout = BoardLayout.make(rows: 1, cols: 1, cells: cells(rows: 4, cols: 4), tileHeight: 10)
        XCTAssertEqual(layout.tiles.count, 1)
    }

    func testEmptyGridsProduceNoTiles() {
        let layout = BoardLayout.make(rows: 0, cols: 0, cells: [], tileHeight: 10)
        XCTAssertTrue(layout.tiles.isEmpty)
        XCTAssertEqual(layout.width, 0)
    }

    // MARK: Fitting to a screen

    func testFitModeFillsTheScreenWithoutOverflowing() throws {
        let screen = CGSize(width: 1920, height: 1080)
        let layout = try BoardLayout.fitting(rows: 12, cols: 30, cells: cells(rows: 12, cols: 30),
                                             in: screen, mode: .fit,
                                             diagonalInches: 65, calibration: 1.0,
                                             colPitchIn: BoardGeometry.colPitchIn)
        XCTAssertLessThanOrEqual(layout.width, 1920.001)
        XCTAssertLessThanOrEqual(layout.height, 1080.001)
        // It must actually fill one axis, not sit small in the middle.
        let fillsWidth = abs(layout.width - 1920) < 1
        let fillsHeight = abs(layout.height - 1080) < 1
        XCTAssertTrue(fillsWidth || fillsHeight, "fit must touch one axis")
    }

    func testFitModePreservesAspect() throws {
        let unscaled = BoardLayout.make(rows: 12, cols: 30, cells: cells(rows: 12, cols: 30), tileHeight: 100)
        let fitted = try BoardLayout.fitting(rows: 12, cols: 30, cells: cells(rows: 12, cols: 30),
                                             in: CGSize(width: 1920, height: 1080), mode: .fit,
                                             diagonalInches: 65, calibration: 1.0,
                                             colPitchIn: BoardGeometry.colPitchIn)
        XCTAssertEqual(fitted.width / fitted.height,
                       unscaled.width / unscaled.height, accuracy: 1e-6)
    }

    /// True scale is allowed to leave margins — that is the point of it.
    func testTrueScaleMatchesTheGeometryHelper() throws {
        let rows = 12, cols = 30
        let base = BoardLayout.make(rows: rows, cols: cols, cells: cells(rows: rows, cols: cols), tileHeight: 100)
        let expected = try BoardGeometry.autofitScale(
            AutofitScaleInput(screenWidthPx: 1920, screenHeightPx: 1080, diagonalInches: 65,
                              cols: cols, gridWidthPx: base.width, gridHeightPx: base.height,
                              calibration: 1.0, colPitchIn: BoardGeometry.colPitchIn))
        let layout = try BoardLayout.fitting(rows: rows, cols: cols, cells: cells(rows: rows, cols: cols),
                                             in: CGSize(width: 1920, height: 1080), mode: .trueScale,
                                             diagonalInches: 65, calibration: 1.0,
                                             colPitchIn: BoardGeometry.colPitchIn)
        XCTAssertEqual(layout.width, base.width * expected, accuracy: 1e-6)
    }

    /// Font size is a fixed fraction of tile height so glyphs scale with the
    /// board instead of being chosen per screen.
    func testFontSizeTracksTileHeight() {
        let small = BoardLayout.make(rows: 1, cols: 1, cells: cells(rows: 1, cols: 1), tileHeight: 20)
        let large = BoardLayout.make(rows: 1, cols: 1, cells: cells(rows: 1, cols: 1), tileHeight: 40)
        XCTAssertEqual(large.fontSize, small.fontSize * 2, accuracy: 1e-9)
        XCTAssertGreaterThan(small.fontSize, 0)
    }

    func testZeroSizedScreensAreRejected() {
        XCTAssertThrowsError(try BoardLayout.fitting(rows: 1, cols: 1, cells: cells(rows: 1, cols: 1),
                                                     in: .zero, mode: .fit, diagonalInches: 65,
                                                     calibration: 1.0, colPitchIn: BoardGeometry.colPitchIn))
    }
}
```

`CGSize` comes from CoreGraphics, which is not a UI framework — the
layering guard greps only for SwiftUI and UIKit, and CoreGraphics has a
Foundation-level equivalent on any platform. Import `CoreGraphics` in
`BoardLayout.swift`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `./build-and-run.sh --test`
Expected: FAIL — `BoardLayout`, `TileRect`, `BoardSizing` undefined.

- [ ] **Step 3: Implement `BoardLayout.swift`**

```swift
import CoreGraphics
import Foundation

/// How the board is sized against the screen.
public enum BoardSizing: String, Codable, CaseIterable, Sendable {
    /// Fill the screen, preserving aspect. The default: a panel's grid was
    /// auto-fit for whatever TV its owner typed in, which is rarely this one.
    case fit
    /// Flaps at real Vestaboard size, accepting margins.
    case trueScale
}

/// One flap, positioned.
public struct TileRect: Equatable, Sendable {
    public let row: Int
    public let col: Int
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let radius: Double
    public let cell: BoardCell
}

/// A board reduced to rectangles.
///
/// Pure geometry with no drawing: the renderer paints this, the tests do
/// arithmetic on it, and the future Compose implementation reuses the shape
/// of it verbatim.
public struct BoardLayout: Sendable {

    public let tiles: [TileRect]
    public let width: Double
    public let height: Double
    public let tileHeight: Double

    /// Glyph size as a fraction of tile height, matching FiestaUI's board
    /// steps (28px tile → 16px text at the lg breakpoint).
    public static let fontSizeRatio = 0.40

    public var fontSize: Double { tileHeight * Self.fontSizeRatio }

    public static func make(rows: Int, cols: Int, cells: [[BoardCell]], tileHeight: Double) -> BoardLayout {
        guard rows > 0, cols > 0, tileHeight > 0 else {
            return BoardLayout(tiles: [], width: 0, height: 0, tileHeight: max(tileHeight, 0))
        }

        let h = tileHeight
        let tileWidth = h * BoardGeometry.tileWidthRatio
        let gutter = h * BoardGeometry.tileGutterRatio
        let radius = h * BoardGeometry.tileRadiusRatio
        let colPitch = tileWidth + gutter
        let rowPitch = h + gutter

        var tiles: [TileRect] = []
        tiles.reserveCapacity(rows * cols)
        for row in 0..<rows {
            for col in 0..<cols {
                // Short or ragged frames pad with blanks: a reshape in flight
                // is a normal transient state, not a crash.
                let cell: BoardCell = (row < cells.count && col < cells[row].count)
                    ? cells[row][col] : .blank
                tiles.append(TileRect(row: row, col: col,
                                      x: Double(col) * colPitch,
                                      y: Double(row) * rowPitch,
                                      width: tileWidth, height: h, radius: radius,
                                      cell: cell))
            }
        }

        // Borderless: the trailing gutter is not part of the board.
        return BoardLayout(tiles: tiles,
                           width: Double(cols) * colPitch - gutter,
                           height: Double(rows) * rowPitch - gutter,
                           tileHeight: h)
    }

    /// Lay the board out at whatever tile height makes it meet the screen
    /// the way `mode` asks for.
    public static func fitting(rows: Int, cols: Int, cells: [[BoardCell]],
                               in screen: CGSize, mode: BoardSizing,
                               diagonalInches: Double, calibration: Double,
                               colPitchIn: Double) throws -> BoardLayout {
        guard screen.width > 0, screen.height > 0 else {
            throw BoardGeometry.Error.nonPositive("screen \(screen.width)×\(screen.height)")
        }
        guard rows > 0, cols > 0 else {
            return BoardLayout(tiles: [], width: 0, height: 0, tileHeight: 0)
        }

        // Lay out once at a reference height, measure, then rescale. This is
        // the same two-pass shape the web viewer uses (render, measure the
        // grid, apply a transform) without needing a real measurement.
        let reference = 100.0
        let base = make(rows: rows, cols: cols, cells: cells, tileHeight: reference)

        let scale: Double
        switch mode {
        case .fit:
            scale = try BoardGeometry.fitScale(gridWidthPx: base.width, gridHeightPx: base.height,
                                               screenWidthPx: Double(screen.width),
                                               screenHeightPx: Double(screen.height))
        case .trueScale:
            scale = try BoardGeometry.autofitScale(
                AutofitScaleInput(screenWidthPx: Double(screen.width),
                                  screenHeightPx: Double(screen.height),
                                  diagonalInches: diagonalInches,
                                  cols: cols,
                                  gridWidthPx: base.width, gridHeightPx: base.height,
                                  calibration: calibration, colPitchIn: colPitchIn))
        }

        return make(rows: rows, cols: cols, cells: cells, tileHeight: reference * scale)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./build-and-run.sh --test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(core): pure board layout

Reduces a board frame to positioned rectangles at FiestaUI's tile
ratios, with no drawing involved. Splitting layout from painting is what
lets the renderer be verified by arithmetic rather than screenshots.

Short, ragged and oversized frames pad or crop rather than crash: a grid
reshape in flight is a normal transient state.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: `BoardCanvas`

**Files:**
- Create: `Sources/Render/BoardCanvas.swift`, `Sources/Render/BoardFont.swift`, `Tests/Support/RenderHarness.swift`, `Tests/BoardCanvasTests.swift`

**Interfaces:**
- Consumes: `BoardLayout`, `TileRect`, `BoardCell`, `BoardColor` (Tasks 2, 7)
- Produces:
  - `BoardCanvas` — `View`, `init(layout:background:animated:)`
  - `BoardFont.glyph(size:) -> Font`
  - `BoardColor.swiftUI: Color`
  - `RenderHarness.render(_:size:)`, `RenderHarness.image(_:size:) -> UIImage`

- [ ] **Step 1: Write the render harness**

`Tests/Support/RenderHarness.swift`:

```swift
import SwiftUI
import UIKit
import XCTest
@testable import FiestaBoardTV

/// Hosts a SwiftUI view off-screen and forces a layout pass so its `body`
/// actually executes — line coverage on view code without UI automation —
/// and can snapshot it so geometry can be asserted by sampling pixels.
@MainActor
enum RenderHarness {

    static let tvSize = CGSize(width: 1920, height: 1080)

    static func render<V: View>(_ view: V, size: CGSize = tvSize) {
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(origin: .zero, size: size)
        let window = UIWindow(frame: host.view.frame)
        window.rootViewController = host
        window.isHidden = false
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        window.isHidden = true
        window.rootViewController = nil
    }

    /// Draw `view` into an image so a test can sample what was painted.
    static func image<V: View>(_ view: V, size: CGSize = tvSize) -> UIImage {
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.backgroundColor = .clear
        let window = UIWindow(frame: host.view.frame)
        window.rootViewController = host
        window.isHidden = false
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        window.rootViewController = nil
        return image
    }
}

extension UIImage {
    /// sRGB components at a point, for geometry assertions.
    func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        guard let cg = cgImage, x >= 0, y >= 0, x < cg.width, y < cg.height else { return nil }
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &pixel, width: 1, height: 1,
                                      bitsPerComponent: 8, bytesPerRow: 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cg, in: CGRect(x: -CGFloat(x), y: -CGFloat(cg.height - y - 1),
                                    width: CGFloat(cg.width), height: CGFloat(cg.height)))
        return (pixel[0], pixel[1], pixel[2], pixel[3])
    }
}
```

- [ ] **Step 2: Write the failing canvas tests**

`Tests/BoardCanvasTests.swift`:

```swift
import SwiftUI
import XCTest
@testable import FiestaBoardTV

@MainActor
final class BoardCanvasTests: XCTestCase {

    private func layout(cells: [[BoardCell]], tileHeight: Double = 100) -> BoardLayout {
        BoardLayout.make(rows: cells.count, cols: cells.first?.count ?? 0,
                         cells: cells, tileHeight: tileHeight)
    }

    func testRendersWithoutCrashing() {
        let grid = [[BoardCell.character("A"), .color(.red)], [.blank, .character("9")]]
        RenderHarness.render(BoardCanvas(layout: layout(cells: grid), background: .black))
    }

    /// The largest grid a panel can have — the case the Canvas approach
    /// exists for. 45x18 is an 85" auto-fit board.
    func testRendersTheLargestSupportedGrid() {
        let grid = Array(repeating: Array(repeating: BoardCell.character("W"), count: 45), count: 18)
        RenderHarness.render(BoardCanvas(layout: layout(cells: grid, tileHeight: 55), background: .black))
    }

    func testRendersAnEmptyBoard() {
        RenderHarness.render(BoardCanvas(layout: layout(cells: []), background: .black))
    }

    func testRendersWithAnimationEnabled() {
        let grid = [[BoardCell.character("A")]]
        RenderHarness.render(BoardCanvas(layout: layout(cells: grid), background: .black, animated: true))
    }

    /// A color tile must paint its pigment across the whole flap. Sampling
    /// the tile centre is what catches a geometry regression that no unit
    /// test on BoardLayout can see.
    func testAColorTilePaintsItsPigment() throws {
        let grid = [[BoardCell.color(.red)]]
        let board = layout(cells: grid, tileHeight: 200)
        let view = BoardCanvas(layout: board, background: .black)
            .frame(width: board.width, height: board.height)

        let image = RenderHarness.image(view, size: CGSize(width: board.width, height: board.height))
        let centre = try XCTUnwrap(image.pixel(x: Int(board.width / 2), y: Int(board.height / 2)))

        // #eb4034
        XCTAssertEqual(Int(centre.r), 0xeb, accuracy: 12, "red channel")
        XCTAssertEqual(Int(centre.g), 0x40, accuracy: 12, "green channel")
        XCTAssertEqual(Int(centre.b), 0x34, accuracy: 12, "blue channel")
    }

    /// The gutter between two tiles must show the board behind them, which
    /// is what proves the pitch is being honoured rather than the tiles
    /// being drawn edge to edge.
    func testTheGutterShowsTheBoardBehind() throws {
        let grid = [[BoardCell.color(.white), BoardCell.color(.white)]]
        let board = layout(cells: grid, tileHeight: 200)
        let view = BoardCanvas(layout: board, background: .black)
            .frame(width: board.width, height: board.height)

        let image = RenderHarness.image(view, size: CGSize(width: board.width, height: board.height))

        // Tile 0 spans 0..140; the gutter runs 140..169; tile 1 starts at 169.
        let gutterX = Int(board.tiles[0].width + board.tileHeight * BoardGeometry.tileGutterRatio / 2)
        let gutter = try XCTUnwrap(image.pixel(x: gutterX, y: Int(board.height / 2)))
        XCTAssertLessThan(Int(gutter.r), 0x60, "the gutter must not be a lit flap")

        let tile = try XCTUnwrap(image.pixel(x: Int(board.tiles[0].width / 2), y: Int(board.height / 2)))
        XCTAssertGreaterThan(Int(tile.r), 0xc0, "a white flap must be lit")
    }

    func testBoardColorsBridgeToSwiftUI() {
        // Guards against a typo silently turning into black.
        XCTAssertNotEqual(BoardColor.red.swiftUI.description, BoardColor.blue.swiftUI.description)
        for color in BoardColor.allCases {
            XCTAssertFalse(color.hex.isEmpty)
        }
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `./build-and-run.sh --test`
Expected: FAIL — `BoardCanvas`, `BoardFont`, `BoardColor.swiftUI` undefined.

- [ ] **Step 4: Implement `BoardFont.swift`**

```swift
import SwiftUI

/// The glyph face for board flaps.
///
/// Spline Sans Mono is FiestaUI's `--font-mono`, so using it here is what
/// makes the letterforms on the TV the same shapes as in the web viewer.
/// The face is registered from the bundle at launch; if registration fails
/// the monospaced system face stands in rather than the board going blank.
public enum BoardFont {

    public static let familyName = "Spline Sans Mono"

    private static var registered = false

    /// Register the bundled face. Idempotent; safe to call repeatedly.
    public static func registerIfNeeded() {
        guard !registered else { return }
        registered = true
        guard let url = Bundle.main.url(forResource: "SplineSansMono", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    public static func glyph(size: Double) -> Font {
        registerIfNeeded()
        if UIFont(name: familyName, size: size) != nil {
            return .custom(familyName, fixedSize: size).weight(.semibold)
        }
        return .system(size: size, weight: .semibold, design: .monospaced)
    }
}

extension BoardColor {
    public var swiftUI: Color { Color(hex: hex) }
}

extension Color {
    /// `#rrggbb`. Board pigments are the only source, so the parse is strict
    /// and falls back to board black.
    init(hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            self = Color(red: 0x1a / 255, green: 0x1a / 255, blue: 0x1a / 255)
            return
        }
        self = Color(red: Double((value >> 16) & 0xff) / 255,
                     green: Double((value >> 8) & 0xff) / 255,
                     blue: Double(value & 0xff) / 255)
    }
}
```

- [ ] **Step 5: Implement `BoardCanvas.swift`**

```swift
import SwiftUI

/// Paints a `BoardLayout`.
///
/// One `Canvas` rather than a view per flap: an 85" panel is 45×18 = 810
/// tiles, which is a great deal of view identity for what is really a grid
/// of rounded rectangles. Each distinct (character, color) pair resolves to
/// a `GraphicsContext.ResolvedText` once — about 72 of them — and every tile
/// is then a rect fill plus a cached glyph draw. Steady state is one redraw
/// per frame change, roughly every two seconds.
public struct BoardCanvas: View {

    private let layout: BoardLayout
    private let background: BoardColor
    private let animated: Bool

    public init(layout: BoardLayout, background: BoardColor = .black, animated: Bool = false) {
        self.layout = layout
        self.background = background
        self.animated = animated
    }

    public var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
            draw(in: &context)
        }
        .frame(width: layout.width, height: layout.height)
        .background(background.swiftUI)
        // The flip is announced to VoiceOver by the viewer, not per tile:
        // 810 accessibility elements would make the board unusable to browse.
        .accessibilityHidden(true)
        .animation(animated ? .easeInOut(duration: 0.18) : nil, value: layout.tiles.count)
    }

    private func draw(in context: inout GraphicsContext) {
        let font = BoardFont.glyph(size: layout.fontSize)
        let unlit = BoardColor.black.swiftUI
        let ink = Color.white

        // Resolve each distinct glyph once, then stamp it.
        var resolved: [Character: GraphicsContext.ResolvedText] = [:]

        for tile in layout.tiles {
            let rect = CGRect(x: tile.x, y: tile.y, width: tile.width, height: tile.height)
            let shape = Path(roundedRect: rect, cornerRadius: tile.radius)

            switch tile.cell {
            case .blank:
                context.fill(shape, with: .color(unlit))

            case .color(let color):
                context.fill(shape, with: .color(color.swiftUI))

            case .character(let character):
                context.fill(shape, with: .color(unlit))
                let text: GraphicsContext.ResolvedText
                if let cached = resolved[character] {
                    text = cached
                } else {
                    text = context.resolve(Text(String(character)).font(font).foregroundColor(ink))
                    resolved[character] = text
                }
                let size = text.measure(in: rect.size)
                context.draw(text, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
                _ = size
            }
        }
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `./build-and-run.sh --test`
Expected: PASS.

If the pixel assertions fail with fully transparent samples, the snapshot
did not capture — check that `RenderHarness.image` is called with a view
that has an explicit `.frame`, and that the window is visible (`isHidden
= false`) at draw time. Do not relax the colour tolerance to make it pass;
an all-zero pixel means nothing rendered, which is the bug.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(render): split-flap board on a single Canvas

One Canvas rather than a view per flap: an 85-inch panel is 45x18 = 810
tiles, and a view apiece is a lot of identity for a grid of rounded
rectangles. Distinct glyphs resolve once and are stamped.

Tests sample painted pixels at tile centres and in a gutter, which is
what catches geometry drift that arithmetic on the layout cannot see.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: `PanelStore` — polling, auto-dim, connection state

**Files:**
- Create: `Sources/Core/AutoDimWindow.swift`, `Sources/Core/PanelStore.swift`, `Tests/AutoDimWindowTests.swift`, `Tests/PanelStoreTests.swift`

**Interfaces:**
- Consumes: `FiestaClient`, `Panel`, `PanelFrame`, `FiestaError` (Task 4), `BoardTables` (Task 2)
- Produces:
  - `AutoDimWindow.isDimmed(_:at:calendar:) -> Bool`
  - `PanelSnapshot` — `panel: Panel?`, `cells: [[BoardCell]]`, `rows: Int`, `cols: Int`, `connection: ConnectionState`, `dimmed: Bool`, `deleted: Bool`
  - `ConnectionState` — `enum { case connecting, live, stale }`
  - `PanelStore` — `init(client:ref:frameInterval:configInterval:clock:)`, `snapshots() -> AsyncStream<PanelSnapshot>`, `stop()`
  - `PanelStore.frameIntervalDefault = 2.0`, `.configIntervalDefault = 10.0`

- [ ] **Step 1: Write the failing auto-dim tests**

Auto-dim is pure and easy to get wrong at midnight, so it gets its own file.

```swift
import XCTest
@testable import FiestaBoardTV

final class AutoDimWindowTests: XCTestCase {

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 19
        components.hour = hour; components.minute = minute
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private let overnight = AutoDim(enabled: true, start: "22:00", end: "07:00")
    private let daytime = AutoDim(enabled: true, start: "09:00", end: "17:00")

    func testDisabledIsNeverDimmed() {
        let off = AutoDim(enabled: false, start: "00:00", end: "23:59")
        XCTAssertFalse(AutoDimWindow.isDimmed(off, at: at(12)))
    }

    /// The window that wraps midnight is the whole reason this is tested.
    func testOvernightWindowWrapsMidnight() {
        XCTAssertTrue(AutoDimWindow.isDimmed(overnight, at: at(23)))
        XCTAssertTrue(AutoDimWindow.isDimmed(overnight, at: at(2)))
        XCTAssertTrue(AutoDimWindow.isDimmed(overnight, at: at(6, 59)))
        XCTAssertFalse(AutoDimWindow.isDimmed(overnight, at: at(7)))
        XCTAssertFalse(AutoDimWindow.isDimmed(overnight, at: at(12)))
        XCTAssertFalse(AutoDimWindow.isDimmed(overnight, at: at(21, 59)))
    }

    func testStartIsInclusiveAndEndExclusive() {
        XCTAssertTrue(AutoDimWindow.isDimmed(overnight, at: at(22, 0)))
        XCTAssertFalse(AutoDimWindow.isDimmed(overnight, at: at(7, 0)))
    }

    func testSameDayWindowDoesNotWrap() {
        XCTAssertFalse(AutoDimWindow.isDimmed(daytime, at: at(8, 59)))
        XCTAssertTrue(AutoDimWindow.isDimmed(daytime, at: at(9)))
        XCTAssertTrue(AutoDimWindow.isDimmed(daytime, at: at(16, 59)))
        XCTAssertFalse(AutoDimWindow.isDimmed(daytime, at: at(17)))
    }

    func testAnEmptyWindowNeverDims() {
        let empty = AutoDim(enabled: true, start: "08:00", end: "08:00")
        XCTAssertFalse(AutoDimWindow.isDimmed(empty, at: at(8)))
        XCTAssertFalse(AutoDimWindow.isDimmed(empty, at: at(20)))
    }

    func testMalformedTimesNeverDim() {
        XCTAssertFalse(AutoDimWindow.isDimmed(AutoDim(enabled: true, start: "nonsense", end: "07:00"),
                                              at: at(23)))
        XCTAssertFalse(AutoDimWindow.isDimmed(AutoDim(enabled: true, start: "25:00", end: "07:00"),
                                              at: at(23)))
    }
}
```

- [ ] **Step 2: Write the failing store tests**

```swift
import XCTest
@testable import FiestaBoardTV

final class PanelStoreTests: XCTestCase {

    private func makeStore(ref: String = "1") -> PanelStore {
        PanelStore(client: FiestaClient(baseURL: URL(string: "http://host:4420")!,
                                        session: StubURLProtocol.makeSession()),
                   ref: ref,
                   frameInterval: 0.02,
                   configInterval: 0.05)
    }

    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    /// Wait for the first snapshot matching `predicate`, or fail.
    private func firstSnapshot(from store: PanelStore,
                               timeout: TimeInterval = 3,
                               where predicate: @escaping (PanelSnapshot) -> Bool) async -> PanelSnapshot? {
        let deadline = Date().addingTimeInterval(timeout)
        for await snapshot in store.snapshots() {
            if predicate(snapshot) { store.stop(); return snapshot }
            if Date() > deadline { store.stop(); return nil }
        }
        return nil
    }

    func testPublishesDecodedCellsFromTheFrame() async {
        StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/panel/1")
        for _ in 0..<6 { StubURLProtocol.enqueue(.json(Fixtures.frameJSON), for: "/frame") }

        let store = makeStore()
        let snapshot = await firstSnapshot(from: store) { !$0.cells.isEmpty }
        XCTAssertEqual(snapshot?.cells.first?.first, .character("H"))
        XCTAssertEqual(snapshot?.cells.first?[1], .character("I"))
        XCTAssertEqual(snapshot?.cells[1].first, .color(.red))
        XCTAssertEqual(snapshot?.connection, .live)
    }

    /// The panel's device decides code 62, so the store must apply the
    /// panel's glyph rather than a default.
    func testAppliesThePanelsCode62Glyph() async {
        StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/panel/1")
        let heartFrame = #"{"characters":[[62]],"message":null,"rows":1,"cols":1,"updated_at":null}"#
        for _ in 0..<6 { StubURLProtocol.enqueue(.json(heartFrame), for: "/frame") }

        let store = makeStore()
        let snapshot = await firstSnapshot(from: store) { !$0.cells.isEmpty }
        // The fixture panel is a note_array, so code 62 is a heart.
        XCTAssertEqual(snapshot?.cells.first?.first, .character("♥"))
    }

    /// The contract that matters most on a wall: a dropped connection keeps
    /// the last frame on screen and only flags itself.
    func testALostConnectionKeepsTheLastFrameAndGoesStale() async {
        StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/panel/1")
        StubURLProtocol.enqueue(.json(Fixtures.frameJSON), for: "/frame")
        // Nothing more enqueued: subsequent polls fail at the transport.

        let store = makeStore()
        let snapshot = await firstSnapshot(from: store, timeout: 4) { $0.connection == .stale }
        XCTAssertEqual(snapshot?.connection, .stale)
        XCTAssertEqual(snapshot?.cells.first?.first, .character("H"),
                       "the last good frame must stay up")
    }

    func testADeletedPanelIsReportedNotRetriedForever() async {
        StubURLProtocol.enqueue(.json(Fixtures.panelNotFound, status: 404), for: "/panel/1")
        for _ in 0..<6 { StubURLProtocol.enqueue(.json(Fixtures.panelNotFound, status: 404), for: "/frame") }

        let store = makeStore()
        let snapshot = await firstSnapshot(from: store, timeout: 4) { $0.deleted }
        XCTAssertEqual(snapshot?.deleted, true)
    }

    func testABlankBoardIsNotAnError() async {
        StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/panel/1")
        for _ in 0..<6 { StubURLProtocol.enqueue(.json(Fixtures.emptyFrameJSON), for: "/frame") }

        let store = makeStore()
        let snapshot = await firstSnapshot(from: store) { $0.panel != nil }
        XCTAssertEqual(snapshot?.connection, .live)
        XCTAssertFalse(snapshot?.deleted ?? true)
        XCTAssertTrue(snapshot?.cells.allSatisfy { $0.allSatisfy { $0 == .blank } } ?? false)
    }

    func testStopEndsTheStream() async {
        StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/panel/1")
        for _ in 0..<10 { StubURLProtocol.enqueue(.json(Fixtures.frameJSON), for: "/frame") }

        let store = makeStore()
        var count = 0
        for await _ in store.snapshots() {
            count += 1
            if count == 2 { store.stop() }
            if count > 50 { XCTFail("stream did not end"); break }
        }
        XCTAssertGreaterThanOrEqual(count, 2)
    }

    func testDefaultCadencesMatchTheWebViewer() {
        XCTAssertEqual(PanelStore.frameIntervalDefault, 2.0)
        XCTAssertEqual(PanelStore.configIntervalDefault, 10.0)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `./build-and-run.sh --test`
Expected: FAIL — `AutoDimWindow`, `PanelStore`, `PanelSnapshot` undefined.

- [ ] **Step 4: Implement `AutoDimWindow.swift`**

```swift
import Foundation

/// Evaluates a panel's nightly dimming window.
///
/// Against the TV's own clock, matching the web viewer: the window is what
/// the room is doing, not what the server's timezone thinks.
public enum AutoDimWindow {

    /// Minutes since midnight for "HH:MM", or nil if malformed.
    static func minutes(from text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    public static func isDimmed(_ autoDim: AutoDim,
                                at date: Date,
                                calendar: Calendar = .current) -> Bool {
        guard autoDim.enabled,
              let start = minutes(from: autoDim.start),
              let end = minutes(from: autoDim.end),
              start != end else { return false }

        let components = calendar.dateComponents([.hour, .minute], from: date)
        let now = (components.hour ?? 0) * 60 + (components.minute ?? 0)

        // Start inclusive, end exclusive, wrapping past midnight when the
        // window's end is earlier in the day than its start.
        return start < end ? (now >= start && now < end)
                           : (now >= start || now < end)
    }
}
```

- [ ] **Step 5: Implement `PanelStore.swift`**

```swift
import Foundation

public enum ConnectionState: Equatable, Sendable {
    case connecting
    case live
    /// The board is unreachable. The last frame stays up; only the corner
    /// indicator changes.
    case stale
}

/// Everything the viewer needs to draw, in one value.
public struct PanelSnapshot: Sendable {
    public let panel: Panel?
    public let cells: [[BoardCell]]
    public let rows: Int
    public let cols: Int
    public let connection: ConnectionState
    public let dimmed: Bool
    /// The panel was deleted in the app; there is nothing to come back to.
    public let deleted: Bool

    public static let empty = PanelSnapshot(panel: nil, cells: [], rows: 0, cols: 0,
                                            connection: .connecting, dimmed: false, deleted: false)
}

/// Polls a panel and publishes snapshots.
///
/// Two cadences, matching the web viewer: frames every 2s because they are
/// the display, config every 10s because edits made in the app should reach
/// a wall-mounted TV without anyone walking over to it.
///
/// There is no retry inside a tick. The cadence IS the retry policy —
/// retrying inside a 2-second loop only multiplies requests during an
/// outage, which is exactly when the board is least able to answer.
public final class PanelStore: @unchecked Sendable {

    public static let frameIntervalDefault: TimeInterval = 2.0
    public static let configIntervalDefault: TimeInterval = 10.0

    private let client: FiestaClient
    private let ref: String
    private let frameInterval: TimeInterval
    private let configInterval: TimeInterval
    private let clock: () -> Date

    private var task: Task<Void, Never>?
    private var continuation: AsyncStream<PanelSnapshot>.Continuation?

    // Last good state — kept so an outage changes the indicator, not the board.
    private var panel: Panel?
    private var cells: [[BoardCell]] = []
    private var rows = 0
    private var cols = 0

    public init(client: FiestaClient,
                ref: String,
                frameInterval: TimeInterval = PanelStore.frameIntervalDefault,
                configInterval: TimeInterval = PanelStore.configIntervalDefault,
                clock: @escaping () -> Date = Date.init) {
        self.client = client
        self.ref = ref
        self.frameInterval = frameInterval
        self.configInterval = configInterval
        self.clock = clock
    }

    public func snapshots() -> AsyncStream<PanelSnapshot> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in self?.stop() }
            self.task = Task { await self.run() }
        }
    }

    private func run() async {
        var sinceConfig = configInterval  // fetch config on the first tick
        var connection = ConnectionState.connecting
        var deleted = false

        while !Task.isCancelled {
            if sinceConfig >= configInterval {
                sinceConfig = 0
                do {
                    panel = try await client.panel(ref: ref)
                    deleted = false
                } catch FiestaError.notFound {
                    deleted = true
                } catch {
                    // A config miss is not fatal: the last one still describes
                    // the board well enough to keep drawing it.
                }
            }

            if !deleted {
                do {
                    let frame = try await client.frame(ref: ref)
                    let glyph = panel?.effectiveCode62 ?? .degree
                    rows = frame.rows
                    cols = frame.cols
                    if let characters = frame.characters {
                        cells = BoardTables.cells(from: characters, code62: glyph)
                    } else {
                        cells = Array(repeating: Array(repeating: BoardCell.blank, count: max(cols, 0)),
                                      count: max(rows, 0))
                    }
                    connection = .live
                } catch FiestaError.notFound {
                    deleted = true
                } catch {
                    connection = .stale
                }
            }

            let dimmed = panel.map { AutoDimWindow.isDimmed($0.autoDim, at: clock()) } ?? false
            continuation?.yield(PanelSnapshot(panel: panel, cells: cells, rows: rows, cols: cols,
                                              connection: connection, dimmed: dimmed, deleted: deleted))

            try? await Task.sleep(nanoseconds: UInt64(frameInterval * 1_000_000_000))
            sinceConfig += frameInterval
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        continuation?.finish()
        continuation = nil
    }

    deinit { task?.cancel() }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `./build-and-run.sh --test`
Expected: PASS.

`testALostConnectionKeepsTheLastFrameAndGoesStale` is the important one —
it encodes the behaviour a wall-mounted TV lives or dies by. If it hangs,
check that `firstSnapshot` calls `store.stop()` on the timeout path.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(core): panel polling, auto-dim, and connection state

Two cadences matching the web viewer: frames at 2s because they are the
display, config at 10s so edits reach a wall-mounted TV without anyone
walking over to it.

No retry inside a tick — the cadence is the retry policy. A dropped
connection keeps the last frame on screen and only flags itself, which
is what a board on a wall should do.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Design tokens and the app shell

**Files:**
- Create: `Sources/UI/FiestaTokens.swift`, `Sources/UI/AppModel.swift`, `Sources/UI/RootView.swift`
- Modify: `Sources/UI/FiestaBoardApp.swift`
- Test: `Tests/AppModelTests.swift`, `Tests/FiestaTokensTests.swift`

**Interfaces:**
- Consumes: `ConnectionStore`, `ConnectResult` (Task 5), `BonjourDiscovery` (Task 6)
- Produces:
  - `Fiesta.Colors` — `background`, `surface`, `surfaceRaised`, `foreground`, `mutedForeground`, `brand`, `border`, `destructive`
  - `Fiesta.Metrics` — `gutter`, `cornerRadius`, `safeInset`
  - `Fiesta.Text` — `title`, `heading`, `body`, `caption`
  - `AppModel` — `@MainActor @Observable`, `route: Route`, `connection: ConnectionStore`, `start()`, `finishConnect(_:)`, `openPanel(ref:)`, `showPanels()`, `showSettings()`
  - `Route` — `enum { case connecting, connect, signIn, panels, viewer(String), settings }`

- [ ] **Step 1: Write the failing tests**

```swift
import SwiftUI
import XCTest
@testable import FiestaBoardTV

final class FiestaTokensTests: XCTestCase {

    /// Brand orange is the one value shared verbatim with FiestaUI's
    /// theme.css, where it is --primary in both light and dark.
    func testBrandIsFiestaOrange() {
        XCTAssertEqual(Fiesta.Colors.brandHex.lowercased(), "#f5a623")
    }

    /// The board background is #1a1a1a, never pure black: a real flap
    /// reflects light, and pure black reads as a dead panel.
    func testBoardBackgroundIsNotPureBlack() {
        XCTAssertNotEqual(BoardColor.black.hex.lowercased(), "#000000")
    }

    func testEveryTokenResolves() {
        // Cheap guard against a token being added without a value.
        _ = Fiesta.Colors.background
        _ = Fiesta.Colors.surface
        _ = Fiesta.Colors.surfaceRaised
        _ = Fiesta.Colors.foreground
        _ = Fiesta.Colors.mutedForeground
        _ = Fiesta.Colors.brand
        _ = Fiesta.Colors.border
        _ = Fiesta.Colors.destructive
    }
}

@MainActor
final class AppModelTests: XCTestCase {

    private func makeModel(defaults: UserDefaults? = nil) -> AppModel {
        let suite = defaults ?? UserDefaults(suiteName: "tv.app.\(UUID().uuidString)")!
        let connection = ConnectionStore(
            defaults: suite,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        return AppModel(connection: connection)
    }

    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    func testWithNoSavedBoardItAsksToConnect() {
        let model = makeModel()
        model.start()
        XCTAssertEqual(model.route, .connect)
    }

    /// The payoff of the whole app: a configured TV powers on into its board.
    func testWithADefaultPanelItOpensStraightIntoTheViewer() async throws {
        let defaults = UserDefaults(suiteName: "tv.app.\(UUID().uuidString)")!
        let credentials = InMemoryCredentialStore()
        let connection = ConnectionStore(
            defaults: defaults, credentials: credentials,
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })

        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/auth/status")
        _ = try await connection.connect(to: URL(string: "http://host:4420")!, displayName: "Board")
        connection.setDefaultPanel(ref: "1")

        let model = AppModel(connection: connection)
        model.start()
        XCTAssertEqual(model.route, .viewer("1"))
    }

    func testASavedBoardWithNoDefaultPanelLandsOnTheList() async throws {
        let defaults = UserDefaults(suiteName: "tv.app.\(UUID().uuidString)")!
        let connection = ConnectionStore(
            defaults: defaults, credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/auth/status")
        _ = try await connection.connect(to: URL(string: "http://host:4420")!, displayName: "Board")

        let model = AppModel(connection: connection)
        model.start()
        XCTAssertEqual(model.route, .panels)
    }

    func testConnectResultsRouteCorrectly() {
        let model = makeModel()
        model.finishConnect(.ready)
        XCTAssertEqual(model.route, .panels)

        model.finishConnect(.needsSignIn)
        XCTAssertEqual(model.route, .signIn)

        model.finishConnect(.needsSetup)
        XCTAssertEqual(model.route, .connect)
        XCTAssertNotNil(model.errorMessage, "setup-required must explain itself")
    }

    func testNavigationBetweenScreens() {
        let model = makeModel()
        model.openPanel(ref: "abc")
        XCTAssertEqual(model.route, .viewer("abc"))
        model.showPanels()
        XCTAssertEqual(model.route, .panels)
        model.showSettings()
        XCTAssertEqual(model.route, .settings)
    }

    func testRootViewRendersEveryRoute() {
        for route in [Route.connecting, .connect, .signIn, .panels, .viewer("1"), .settings] {
            let model = makeModel()
            model.route = route
            RenderHarness.render(RootView().environment(model))
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./build-and-run.sh --test`
Expected: FAIL — `Fiesta`, `AppModel`, `Route`, `RootView` undefined.

- [ ] **Step 3: Implement `FiestaTokens.swift`**

```swift
import SwiftUI

/// FiestaUI's design tokens, transcribed for tvOS.
///
/// `@fiestaboard/ui` is a React package and tvOS ships no WebKit, so the
/// package cannot run here — but its token VALUES can, and this file is the
/// compatibility seam. Values come from theme.css, converted from oklch to
/// sRGB. When FiestaUI moves a token, this file is the one that changes.
///
/// Dark only: a TV lives in a dark room, an Apple TV app is conventionally
/// dark, and the viewer is pure board-black regardless. A light palette
/// would be a theme switcher nobody would ever touch.
public enum Fiesta {

    public enum Colors {
        /// --primary / --brand, identical in both FiestaUI themes.
        public static let brandHex = "#f5a623"

        public static let brand = Color(hex: brandHex)
        /// --background (dark): oklch(0.145 0.004 73)
        public static let background = Color(hex: "#1c1a18")
        /// --card (dark): oklch(0.195 0.004 73)
        public static let surface = Color(hex: "#262320")
        /// --accent (dark): oklch(0.225 0.004 73)
        public static let surfaceRaised = Color(hex: "#2d2a26")
        /// --foreground (dark): oklch(0.965 0.003 73)
        public static let foreground = Color(hex: "#f5f3f1")
        /// --muted-foreground (dark): oklch(0.725 0.004 73)
        public static let mutedForeground = Color(hex: "#aba7a2")
        /// --border (dark): foreground at 12%
        public static let border = Color.white.opacity(0.12)
        /// --destructive (dark): oklch(0.7 0.17 29)
        public static let destructive = Color(hex: "#f2705c")
        /// The amber "lost the board" dot, matching the web viewer.
        public static let offline = Color(hex: "#f5a623")
    }

    public enum Metrics {
        public static let gutter: CGFloat = 24
        public static let cornerRadius: CGFloat = 16
        /// tvOS title-safe inset. Overscan is still real on many sets.
        public static let safeInset: CGFloat = 60
    }

    public enum Text {
        public static let title = Font.system(size: 64, weight: .bold)
        public static let heading = Font.system(size: 38, weight: .semibold)
        public static let body = Font.system(size: 29, weight: .regular)
        public static let caption = Font.system(size: 24, weight: .regular)
    }
}
```

- [ ] **Step 4: Implement `AppModel.swift`**

```swift
import Foundation
import Observation

public enum Route: Equatable, Hashable {
    case connecting
    case connect
    case signIn
    case panels
    case viewer(String)
    case settings
}

/// Navigation and app-wide state.
///
/// The observable wrapper around Core, which is deliberately free of
/// Combine and Observation so it can be transcribed to Kotlin later.
@MainActor
@Observable
public final class AppModel {

    public var route: Route = .connecting
    public var errorMessage: String?

    public let connection: ConnectionStore

    public init(connection: ConnectionStore) {
        self.connection = connection
    }

    /// Decide the opening screen. A configured TV should power on into its
    /// board — that is the whole point of the app.
    public func start() {
        guard let saved = connection.saved, connection.client != nil else {
            route = .connect
            return
        }
        if let ref = saved.defaultPanelRef {
            route = .viewer(ref)
        } else {
            route = .panels
        }
    }

    public func finishConnect(_ result: ConnectResult) {
        switch result {
        case .ready:
            errorMessage = nil
            route = .panels
        case .needsSignIn:
            errorMessage = nil
            route = .signIn
        case .needsSetup:
            // Only the web app can create the first account, so sending
            // someone to a sign-in form here would waste their time.
            errorMessage = "This FiestaBoard has no account yet. Finish setup in the FiestaBoard app, then connect again."
            route = .connect
        }
    }

    public func openPanel(ref: String) {
        errorMessage = nil
        route = .viewer(ref)
    }

    public func showPanels() {
        errorMessage = nil
        route = .panels
    }

    public func showSettings() {
        route = .settings
    }

    public func disconnect() {
        connection.forget()
        route = .connect
    }
}
```

- [ ] **Step 5: Implement `RootView.swift` and update the app entry**

`RootView` switches on `route`. The screens land in Tasks 11–14; until
then each unimplemented case renders a placeholder so this task's tests
pass on their own.

```swift
import SwiftUI

public struct RootView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        ZStack {
            Fiesta.Colors.background.ignoresSafeArea()
            content
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        switch model.route {
        case .connecting:
            ProgressView().tint(Fiesta.Colors.brand)
        case .connect:
            ConnectScreen()
        case .signIn:
            SignInScreen()
        case .panels:
            PanelsScreen()
        case .viewer(let ref):
            ViewerScreen(ref: ref)
        case .settings:
            SettingsScreen()
        }
    }
}
```

Create each of `ConnectScreen`, `SignInScreen`, `PanelsScreen`,
`ViewerScreen`, `SettingsScreen` now as a one-line placeholder in its own
file (`Sources/UI/<Name>.swift`), e.g.:

```swift
import SwiftUI

struct ConnectScreen: View {
    var body: some View { Text("Connect").font(Fiesta.Text.heading) }
}
```

`ViewerScreen` takes `let ref: String`. Later tasks replace each body;
creating the files now keeps `RootView` compiling and gives every
subsequent task a file to modify rather than invent.

`Sources/UI/FiestaBoardApp.swift`:

```swift
import SwiftUI

@main
struct FiestaBoardApp: App {
    @State private var model = AppModel(connection: ConnectionStore())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onAppear {
                    BoardFont.registerIfNeeded()
                    model.start()
                }
        }
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `./build-and-run.sh --test`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(ui): FiestaUI design tokens and the app shell

The @fiestaboard/ui package cannot run on tvOS — there is no WebKit — so
its token values are transcribed instead, converted from theme.css's
oklch to sRGB. That file is the compatibility seam when FiestaUI moves a
token.

Dark only: a TV lives in a dark room and the viewer is board-black
regardless, so a light palette would be a switcher nobody would touch.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: Connect and Sign-in screens

**Files:**
- Modify: `Sources/UI/ConnectScreen.swift`, `Sources/UI/SignInScreen.swift`
- Create: `Sources/UI/ConnectModel.swift`, `Sources/UI/FiestaButton.swift`, `Tests/ConnectScreenTests.swift`

**Interfaces:**
- Consumes: `AppModel`, `Fiesta` (Task 10), `BoardDiscovering`, `DiscoveredBoard`, `ManualAddress` (Task 6)
- Produces:
  - `ConnectModel` — `@MainActor @Observable`, `boards: [DiscoveredBoard]`, `isScanning: Bool`, `manualAddress: String`, `errorMessage: String?`, `startScan(using:)`, `stopScan()`, `connect(to:name:) async`, `connectManually() async`
  - `FiestaButton` — `init(_ title:action:)`, brand-filled, focus-aware
  - `StubDiscovery: BoardDiscovering` (in Tests) — yields a fixed list

- [ ] **Step 1: Write the failing tests**

```swift
import SwiftUI
import XCTest
@testable import FiestaBoardTV

/// Yields a fixed list so screen tests never touch the network.
final class StubDiscovery: BoardDiscovering {
    private let boards: [DiscoveredBoard]
    private(set) var stopped = false

    init(boards: [DiscoveredBoard]) { self.boards = boards }

    func boards() -> AsyncStream<[DiscoveredBoard]> {
        AsyncStream { continuation in
            continuation.yield(boards)
            continuation.finish()
        }
    }

    func stop() { stopped = true }
}

@MainActor
final class ConnectScreenTests: XCTestCase {

    private let board = DiscoveredBoard(id: "http://192.168.1.50:4420",
                                        name: "FiestaBoard",
                                        host: URL(string: "http://192.168.1.50:4420")!)

    private func makeApp() -> AppModel {
        AppModel(connection: ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.connect.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) }))
    }

    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    func testScanningPublishesDiscoveredBoards() async {
        let model = ConnectModel(app: makeApp())
        let discovery = StubDiscovery(boards: [board])
        await model.startScan(using: discovery)
        XCTAssertEqual(model.boards, [board])
    }

    func testConnectingToAnOpenBoardRoutesToPanels() async {
        let app = makeApp()
        let model = ConnectModel(app: app)
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/auth/status")
        await model.connect(to: board.host, name: board.name)
        XCTAssertEqual(app.route, .panels)
    }

    func testConnectingToALockedBoardRoutesToSignIn() async {
        let app = makeApp()
        let model = ConnectModel(app: app)
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/auth/status")
        await model.connect(to: board.host, name: board.name)
        XCTAssertEqual(app.route, .signIn)
    }

    /// An unreachable address must say so rather than silently do nothing.
    func testAnUnreachableAddressReportsAnError() async {
        let app = makeApp()
        let model = ConnectModel(app: app)
        // Nothing enqueued: the request fails at the transport.
        await model.connect(to: board.host, name: board.name)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(app.route, .connecting, "a failed connect must not navigate")
    }

    func testManualEntryNormalisesABareIP() async {
        let app = makeApp()
        let model = ConnectModel(app: app)
        model.manualAddress = "192.168.1.50"
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/auth/status")
        await model.connectManually()
        XCTAssertEqual(app.connection.saved?.host.absoluteString, "http://192.168.1.50:4420")
    }

    func testBlankManualEntryIsRejectedWithoutARequest() async {
        let model = ConnectModel(app: makeApp())
        model.manualAddress = "   "
        await model.connectManually()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testStopScanStopsDiscovery() async {
        let model = ConnectModel(app: makeApp())
        let discovery = StubDiscovery(boards: [board])
        await model.startScan(using: discovery)
        model.stopScan()
        XCTAssertTrue(discovery.stopped)
    }

    // MARK: Rendering

    func testConnectScreenRendersInEveryState() {
        let app = makeApp()
        RenderHarness.render(ConnectScreen().environment(app))

        let withError = makeApp()
        withError.errorMessage = "This FiestaBoard has no account yet."
        RenderHarness.render(ConnectScreen().environment(withError))
    }

    func testSignInScreenRenders() {
        RenderHarness.render(SignInScreen().environment(makeApp()))
    }

    func testSignInWithBadCredentialsShowsAnErrorAndStays() async {
        let app = makeApp()
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/auth/status")
        _ = try? await app.connection.connect(to: board.host, displayName: "Board")
        app.route = .signIn

        StubURLProtocol.enqueue(.json(#"{"detail":"Invalid username or password"}"#, status: 401),
                                for: "/auth/login")
        let model = SignInModel(app: app)
        model.username = "jeffre"
        model.password = "wrong"
        await model.submit()

        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(app.route, .signIn)
    }

    func testSuccessfulSignInRoutesToPanels() async {
        let app = makeApp()
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/auth/status")
        _ = try? await app.connection.connect(to: board.host, displayName: "Board")

        StubURLProtocol.enqueue(.json(Fixtures.loginOK), for: "/auth/login")
        let model = SignInModel(app: app)
        model.username = "jeffre"
        model.password = "hunter2"
        await model.submit()

        XCTAssertEqual(app.route, .panels)
        XCTAssertNil(model.errorMessage)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./build-and-run.sh --test`
Expected: FAIL — `ConnectModel`, `SignInModel` undefined.

- [ ] **Step 3: Implement `FiestaButton.swift`**

```swift
import SwiftUI

/// Brand-filled button with a visible focus state.
///
/// tvOS navigation is focus, not a pointer, so the focused state has to be
/// unmistakable from across a room — scale alone is not enough.
struct FiestaButton: View {
    private let title: String
    private let action: () -> Void
    @FocusState private var focused: Bool

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Fiesta.Text.body.weight(.semibold))
                .padding(.horizontal, 40)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .background(focused ? Fiesta.Colors.brand : Fiesta.Colors.surfaceRaised)
        .foregroundStyle(focused ? Color.black : Fiesta.Colors.foreground)
        .clipShape(RoundedRectangle(cornerRadius: Fiesta.Metrics.cornerRadius))
        .focused($focused)
        .scaleEffect(focused ? 1.04 : 1.0)
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}
```

- [ ] **Step 4: Implement `ConnectModel.swift`**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class ConnectModel {

    var boards: [DiscoveredBoard] = []
    var isScanning = false
    var manualAddress = ""
    var errorMessage: String?
    var isConnecting = false

    private let app: AppModel
    private var discovery: BoardDiscovering?

    init(app: AppModel) { self.app = app }

    func startScan(using discovery: BoardDiscovering = BonjourDiscovery()) async {
        self.discovery = discovery
        isScanning = true
        for await found in discovery.boards() {
            boards = found
        }
        isScanning = false
    }

    func stopScan() {
        discovery?.stop()
        discovery = nil
        isScanning = false
    }

    func connect(to host: URL, name: String) async {
        guard !isConnecting else { return }
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }
        do {
            let result = try await app.connection.connect(to: host, displayName: name)
            stopScan()
            app.finishConnect(result)
        } catch {
            errorMessage = "Couldn't reach \(host.host() ?? host.absoluteString). Check it's on and on this network."
        }
    }

    func connectManually() async {
        guard let url = ManualAddress.parse(manualAddress) else {
            errorMessage = "Enter an address like 192.168.1.50"
            return
        }
        await connect(to: url, name: url.host() ?? "FiestaBoard")
    }
}
```

- [ ] **Step 5: Implement `ConnectScreen.swift`**

```swift
import SwiftUI

struct ConnectScreen: View {
    @Environment(AppModel.self) private var app
    @State private var model: ConnectModel?

    var body: some View {
        VStack(alignment: .leading, spacing: Fiesta.Metrics.gutter) {
            Text("Find your FiestaBoard")
                .font(Fiesta.Text.title)
                .foregroundStyle(Fiesta.Colors.foreground)

            Text("Looking on this network…")
                .font(Fiesta.Text.body)
                .foregroundStyle(Fiesta.Colors.mutedForeground)

            if let message = app.errorMessage ?? model?.errorMessage {
                Text(message)
                    .font(Fiesta.Text.caption)
                    .foregroundStyle(Fiesta.Colors.destructive)
            }

            ScrollView {
                VStack(spacing: 16) {
                    ForEach(model?.boards ?? []) { board in
                        FiestaButton("\(board.name)  ·  \(board.host.host() ?? "")") {
                            Task { await model?.connect(to: board.host, name: board.name) }
                        }
                    }

                    if model?.boards.isEmpty ?? true {
                        ProgressView().tint(Fiesta.Colors.brand).padding(.vertical, 24)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Or enter the address").font(Fiesta.Text.caption)
                    .foregroundStyle(Fiesta.Colors.mutedForeground)
                TextField("192.168.1.50", text: Binding(
                    get: { model?.manualAddress ?? "" },
                    set: { model?.manualAddress = $0 }))
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                FiestaButton("Connect") { Task { await model?.connectManually() } }
            }
        }
        .padding(Fiesta.Metrics.safeInset)
        .onAppear {
            if model == nil { model = ConnectModel(app: app) }
            Task { await model?.startScan() }
        }
        .onDisappear { model?.stopScan() }
    }
}
```

- [ ] **Step 6: Implement `SignInScreen.swift` with its model**

```swift
import SwiftUI
import Observation

@MainActor
@Observable
final class SignInModel {
    var username = ""
    var password = ""
    var errorMessage: String?
    var isSubmitting = false

    private let app: AppModel

    init(app: AppModel) { self.app = app }

    func submit() async {
        guard !isSubmitting else { return }
        guard !username.isEmpty, !password.isEmpty else {
            errorMessage = "Enter your username and password."
            return
        }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await app.connection.signIn(username: username, password: password)
            app.route = .panels
        } catch FiestaError.unauthorized {
            errorMessage = "That username or password didn't work."
        } catch {
            errorMessage = "Couldn't reach your FiestaBoard. Check it's still on."
        }
    }
}

struct SignInScreen: View {
    @Environment(AppModel.self) private var app
    @State private var model: SignInModel?

    var body: some View {
        VStack(alignment: .leading, spacing: Fiesta.Metrics.gutter) {
            Text("Sign in").font(Fiesta.Text.title)
                .foregroundStyle(Fiesta.Colors.foreground)

            Text(app.connection.saved?.displayName ?? "FiestaBoard")
                .font(Fiesta.Text.body)
                .foregroundStyle(Fiesta.Colors.mutedForeground)

            TextField("Username", text: Binding(
                get: { model?.username ?? "" }, set: { model?.username = $0 }))
                .textContentType(.username)
                .autocorrectionDisabled()

            SecureField("Password", text: Binding(
                get: { model?.password ?? "" }, set: { model?.password = $0 }))
                .textContentType(.password)

            if let message = model?.errorMessage {
                Text(message).font(Fiesta.Text.caption)
                    .foregroundStyle(Fiesta.Colors.destructive)
            }

            // Said plainly because it is a real commitment: the credential is
            // kept so a lapsed session never sends anyone back to a remote.
            Text("Your sign-in is stored on this Apple TV so it stays connected.")
                .font(Fiesta.Text.caption)
                .foregroundStyle(Fiesta.Colors.mutedForeground)

            FiestaButton("Sign in") { Task { await model?.submit() } }
        }
        .padding(Fiesta.Metrics.safeInset)
        .frame(maxWidth: 900, alignment: .leading)
        .onAppear { if model == nil { model = SignInModel(app: app) } }
    }
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `./build-and-run.sh --test`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(ui): connect and sign-in screens

Discovery fills the list as boards answer, with manual entry for the
networks mDNS cannot cross — Docker bridge setups, VLANs, a reverse
proxy. A bare IP is enough to type.

Sign-in says plainly that the credential is kept on the device, because
storing a password deserves to be stated rather than discovered.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 12: Panels list

**Files:**
- Modify: `Sources/UI/PanelsScreen.swift`
- Create: `Sources/UI/PanelsModel.swift`, `Sources/UI/PanelCard.swift`, `Tests/PanelsScreenTests.swift`

**Interfaces:**
- Consumes: `AppModel`, `ConnectionStore.authorized`, `Panel`, `Fiesta`
- Produces:
  - `PanelsModel` — `panels: [Panel]`, `isLoading: Bool`, `errorMessage: String?`, `load() async`
  - `PanelCard` — `init(panel:action:)`
  - `Panel.gridDescription: String`, `Panel.screenDescription: String`

- [ ] **Step 1: Write the failing tests**

```swift
import SwiftUI
import XCTest
@testable import FiestaBoardTV

@MainActor
final class PanelsScreenTests: XCTestCase {

    private func makeApp() async -> AppModel {
        let app = AppModel(connection: ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.panels.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) }))
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/auth/status")
        _ = try? await app.connection.connect(to: URL(string: "http://host:4420")!, displayName: "Board")
        return app
    }

    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    func testLoadsThePanelList() async {
        let app = await makeApp()
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/panels")
        let model = PanelsModel(app: app)
        await model.load()
        XCTAssertEqual(model.panels.count, 1)
        XCTAssertEqual(model.panels.first?.name, "Living Room")
        XCTAssertNil(model.errorMessage)
    }

    /// An instance with auth on that we cannot satisfy must offer sign-in,
    /// not a dead-end error.
    func testA401RoutesToSignIn() async {
        let app = await makeApp()
        StubURLProtocol.enqueue(.json(#"{"detail":"Not authenticated"}"#, status: 401), for: "/panels")
        let model = PanelsModel(app: app)
        await model.load()
        XCTAssertEqual(app.route, .signIn)
    }

    func testAnUnreachableBoardShowsAnError() async {
        let app = await makeApp()
        let model = PanelsModel(app: app)
        await model.load()   // nothing enqueued
        XCTAssertNotNil(model.errorMessage)
    }

    func testAnEmptyListIsNotAnError() async {
        let app = await makeApp()
        StubURLProtocol.enqueue(.json(#"{"panels":[],"total":0}"#), for: "/panels")
        let model = PanelsModel(app: app)
        await model.load()
        XCTAssertTrue(model.panels.isEmpty)
        XCTAssertNil(model.errorMessage)
    }

    func testPanelDescribesItsGridAndScreen() throws {
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        XCTAssertEqual(panel.gridDescription, "30 × 12")
        XCTAssertTrue(panel.screenDescription.contains("65"))
    }

    /// An orphaned panel must say so rather than offering a board that
    /// cannot render.
    func testAPanelWithAMissingBoardDescribesItself() throws {
        let orphan = Fixtures.panelJSON
            .replacingOccurrences(of: "\"board_missing\":false", with: "\"board_missing\":true")
            .replacingOccurrences(of: "\"rows\":12", with: "\"rows\":null")
            .replacingOccurrences(of: "\"cols\":30", with: "\"cols\":null")
        let panel = try JSONDecoder().decode(Panel.self, from: Data(orphan.utf8))
        XCTAssertTrue(panel.boardMissing)
        XCTAssertEqual(panel.gridDescription, "No board")
    }

    func testScreenRendersLoadedEmptyAndErrorStates() async {
        let app = await makeApp()
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/panels")
        RenderHarness.render(PanelsScreen().environment(app))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./build-and-run.sh --test`
Expected: FAIL — `PanelsModel`, `gridDescription` undefined.

- [ ] **Step 3: Implement the descriptions on `Panel`**

Add to `Sources/Core/Models.swift`:

```swift
extension Panel {
    /// "30 × 12", or a plain statement when the virtual board is gone.
    public var gridDescription: String {
        guard !boardMissing, let rows, let cols else { return "No board" }
        return "\(cols) × \(rows)"
    }

    /// The screen this panel's grid was auto-fit for — which is not
    /// necessarily the screen it is about to be shown on.
    public var screenDescription: String {
        let inches = screenDiagonalInches
        let rounded = inches.rounded()
        let text = abs(inches - rounded) < 0.05 ? String(Int(rounded)) : String(format: "%.1f", inches)
        return "Built for a \(text)\" screen"
    }
}
```

- [ ] **Step 4: Implement `PanelsModel.swift`**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class PanelsModel {
    var panels: [Panel] = []
    var isLoading = false
    var errorMessage: String?

    private let app: AppModel

    init(app: AppModel) { self.app = app }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            panels = try await app.connection.authorized { try await $0.panels() }
        } catch FiestaError.unauthorized {
            // The stored credential could not recover the session — the only
            // useful next step is asking for one.
            app.route = .signIn
        } catch FiestaError.setupRequired {
            errorMessage = "This FiestaBoard has no account yet. Finish setup in the FiestaBoard app."
        } catch {
            errorMessage = "Couldn't reach your FiestaBoard. Check it's still on."
        }
    }
}
```

- [ ] **Step 5: Implement `PanelCard.swift` and `PanelsScreen.swift`**

```swift
import SwiftUI

struct PanelCard: View {
    let panel: Panel
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(panel.name)
                    .font(Fiesta.Text.heading)
                    .lineLimit(1)
                HStack(spacing: 16) {
                    Text(panel.gridDescription)
                    Text("·")
                    Text(panel.screenDescription)
                }
                .font(Fiesta.Text.caption)
                .foregroundStyle(Fiesta.Colors.mutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
        .buttonStyle(.plain)
        .background(focused ? Fiesta.Colors.surfaceRaised : Fiesta.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Fiesta.Metrics.cornerRadius)
                .stroke(focused ? Fiesta.Colors.brand : Fiesta.Colors.border, lineWidth: focused ? 4 : 1))
        .clipShape(RoundedRectangle(cornerRadius: Fiesta.Metrics.cornerRadius))
        .focused($focused)
        .scaleEffect(focused ? 1.03 : 1.0)
        .animation(.easeOut(duration: 0.15), value: focused)
        .disabled(panel.boardMissing)
        .opacity(panel.boardMissing ? 0.5 : 1)
    }
}

struct PanelsScreen: View {
    @Environment(AppModel.self) private var app
    @State private var model: PanelsModel?

    var body: some View {
        VStack(alignment: .leading, spacing: Fiesta.Metrics.gutter) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Panels").font(Fiesta.Text.title)
                        .foregroundStyle(Fiesta.Colors.foreground)
                    Text(app.connection.saved?.displayName ?? "")
                        .font(Fiesta.Text.caption)
                        .foregroundStyle(Fiesta.Colors.mutedForeground)
                }
                Spacer()
                Button("Settings") { app.showSettings() }
                    .font(Fiesta.Text.body)
            }

            if let message = model?.errorMessage {
                Text(message).font(Fiesta.Text.body)
                    .foregroundStyle(Fiesta.Colors.destructive)
            }

            if model?.isLoading ?? true {
                ProgressView().tint(Fiesta.Colors.brand)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if (model?.panels.isEmpty ?? true) && model?.errorMessage == nil {
                VStack(spacing: 12) {
                    Text("No panels yet").font(Fiesta.Text.heading)
                        .foregroundStyle(Fiesta.Colors.foreground)
                    Text("Create one in the FiestaBoard app under Settings → Hardware → FiestaPanel.")
                        .font(Fiesta.Text.body)
                        .foregroundStyle(Fiesta.Colors.mutedForeground)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(model?.panels ?? []) { panel in
                            PanelCard(panel: panel) { app.openPanel(ref: panel.id) }
                        }
                    }
                }
            }
        }
        .padding(Fiesta.Metrics.safeInset)
        .task {
            if model == nil { model = PanelsModel(app: app) }
            await model?.load()
        }
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `./build-and-run.sh --test`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(ui): panel list

Each row names the panel and the grid and screen size it was built for,
because that is what tells someone whether it will suit the TV in front
of them.

An orphaned panel is shown disabled rather than hidden: the panel still
exists in the app, and silently omitting it would be confusing.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 13: The viewer

**Files:**
- Modify: `Sources/UI/ViewerScreen.swift`
- Create: `Sources/UI/ViewerModel.swift`, `Sources/UI/ViewerOverlay.swift`, `Tests/ViewerScreenTests.swift`

**Interfaces:**
- Consumes: `PanelStore`, `PanelSnapshot`, `ConnectionState` (Task 9), `BoardLayout`, `BoardSizing` (Task 7), `BoardCanvas` (Task 8)
- Produces:
  - `ViewerModel` — `snapshot: PanelSnapshot`, `overlayVisible: Bool`, `sizing: BoardSizing`, `start(client:)`, `stop()`, `showOverlay()`, `layout(for:) throws -> BoardLayout`, `gridSuitsScreen(_:) -> Bool`
  - `ViewerOverlay` — transient chrome over the board

- [ ] **Step 1: Write the failing tests**

```swift
import SwiftUI
import XCTest
@testable import FiestaBoardTV

@MainActor
final class ViewerScreenTests: XCTestCase {

    private let screen = CGSize(width: 1920, height: 1080)

    private func snapshot(rows: Int = 12, cols: Int = 30,
                          connection: ConnectionState = .live,
                          dimmed: Bool = false,
                          deleted: Bool = false) -> PanelSnapshot {
        let panel = try! JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        let cells = Array(repeating: Array(repeating: BoardCell.character("A"), count: cols), count: rows)
        return PanelSnapshot(panel: panel, cells: cells, rows: rows, cols: cols,
                             connection: connection, dimmed: dimmed, deleted: deleted)
    }

    private func makeApp() -> AppModel {
        AppModel(connection: ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.viewer.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) }))
    }

    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    func testLayoutFillsTheScreenInFitMode() throws {
        let model = ViewerModel(app: makeApp(), ref: "1")
        model.snapshot = snapshot()
        model.sizing = .fit
        let layout = try model.layout(for: screen)
        XCTAssertLessThanOrEqual(layout.width, screen.width + 0.001)
        XCTAssertLessThanOrEqual(layout.height, screen.height + 0.001)
        XCTAssertEqual(layout.tiles.count, 12 * 30)
    }

    /// The offer to re-fit must appear only when it would actually help.
    func testGridSuitabilityComparesAspectNotSize() {
        let model = ViewerModel(app: makeApp(), ref: "1")

        // 30x12 note-array on a 16:9 screen: close enough to leave alone.
        model.snapshot = snapshot(rows: 12, cols: 30)
        XCTAssertTrue(model.gridSuitsScreen(screen))

        // 15x21 (a portrait panel) on a landscape TV: badly mismatched.
        model.snapshot = snapshot(rows: 21, cols: 15)
        XCTAssertFalse(model.gridSuitsScreen(screen))
    }

    func testNoPanelYetProducesNoLayout() {
        let model = ViewerModel(app: makeApp(), ref: "1")
        model.snapshot = .empty
        XCTAssertThrowsError(try model.layout(for: screen))
    }

    func testOverlayStartsHiddenAndShowsOnDemand() {
        let model = ViewerModel(app: makeApp(), ref: "1")
        XCTAssertFalse(model.overlayVisible)
        model.showOverlay()
        XCTAssertTrue(model.overlayVisible)
    }

    // MARK: Rendering

    func testRendersALiveBoard() {
        let app = makeApp()
        let model = ViewerModel(app: app, ref: "1")
        model.snapshot = snapshot()
        RenderHarness.render(ViewerScreen(ref: "1", model: model).environment(app))
    }

    /// A dropped connection keeps the board and adds only an indicator.
    func testRendersStaleWithTheBoardStillUp() {
        let app = makeApp()
        let model = ViewerModel(app: app, ref: "1")
        model.snapshot = snapshot(connection: .stale)
        RenderHarness.render(ViewerScreen(ref: "1", model: model).environment(app))
    }

    func testRendersTheDeletedPanelState() {
        let app = makeApp()
        let model = ViewerModel(app: app, ref: "1")
        model.snapshot = PanelSnapshot(panel: nil, cells: [], rows: 0, cols: 0,
                                       connection: .live, dimmed: false, deleted: true)
        RenderHarness.render(ViewerScreen(ref: "1", model: model).environment(app))
    }

    func testRendersDimmed() {
        let app = makeApp()
        let model = ViewerModel(app: app, ref: "1")
        model.snapshot = snapshot(dimmed: true)
        RenderHarness.render(ViewerScreen(ref: "1", model: model).environment(app))
    }

    func testRendersTheOverlay() {
        let app = makeApp()
        let model = ViewerModel(app: app, ref: "1")
        model.snapshot = snapshot()
        model.showOverlay()
        RenderHarness.render(ViewerScreen(ref: "1", model: model).environment(app))
    }

    func testRendersTheLargestGrid() throws {
        let app = makeApp()
        let model = ViewerModel(app: app, ref: "1")
        model.snapshot = snapshot(rows: 18, cols: 45)
        let layout = try model.layout(for: screen)
        XCTAssertEqual(layout.tiles.count, 810)
        RenderHarness.render(ViewerScreen(ref: "1", model: model).environment(app))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./build-and-run.sh --test`
Expected: FAIL — `ViewerModel` undefined.

- [ ] **Step 3: Implement `ViewerModel.swift`**

```swift
import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class ViewerModel {

    var snapshot: PanelSnapshot = .empty
    var overlayVisible = false
    var sizing: BoardSizing = .fit

    private let app: AppModel
    private let ref: String
    private var store: PanelStore?
    private var pump: Task<Void, Never>?
    private var overlayTimer: Task<Void, Never>?

    /// How long the overlay stays up after a button press.
    static let overlayTimeout: TimeInterval = 4

    init(app: AppModel, ref: String) {
        self.app = app
        self.ref = ref
        if let raw = UserDefaults.standard.string(forKey: "fiestaboard.sizing"),
           let stored = BoardSizing(rawValue: raw) {
            sizing = stored
        }
    }

    func start() {
        guard let client = app.connection.client, store == nil else { return }
        let store = PanelStore(client: client, ref: ref)
        self.store = store
        pump = Task { [weak self] in
            for await snapshot in store.snapshots() {
                self?.snapshot = snapshot
            }
        }
    }

    func stop() {
        pump?.cancel(); pump = nil
        overlayTimer?.cancel(); overlayTimer = nil
        store?.stop(); store = nil
    }

    /// tvOS has focus, not a pointer, so the way "move the cursor to get
    /// back" translates is: any button wakes transient chrome, which fades.
    func showOverlay() {
        overlayVisible = true
        overlayTimer?.cancel()
        overlayTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.overlayTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.overlayVisible = false
        }
    }

    func setSizing(_ sizing: BoardSizing) {
        self.sizing = sizing
        UserDefaults.standard.set(sizing.rawValue, forKey: "fiestaboard.sizing")
    }

    func layout(for screen: CGSize) throws -> BoardLayout {
        guard let panel = snapshot.panel, snapshot.rows > 0, snapshot.cols > 0 else {
            throw BoardGeometry.Error.nonPositive("no panel yet")
        }
        return try BoardLayout.fitting(
            rows: snapshot.rows, cols: snapshot.cols, cells: snapshot.cells,
            in: screen, mode: sizing,
            diagonalInches: panel.screenDiagonalInches,
            calibration: panel.calibrationScale,
            colPitchIn: BoardGeometry.colPitchIn(deviceType: panel.deviceType))
    }

    /// Whether the panel's grid shape suits this screen closely enough that
    /// offering to re-fit it would be noise. Compares aspect, because size is
    /// what `fit` already absorbs and shape is what it cannot.
    func gridSuitsScreen(_ screen: CGSize) -> Bool {
        guard snapshot.rows > 0, snapshot.cols > 0, screen.height > 0 else { return true }
        let base = BoardLayout.make(rows: snapshot.rows, cols: snapshot.cols,
                                    cells: snapshot.cells, tileHeight: 100)
        guard base.height > 0 else { return true }
        let boardAspect = base.width / base.height
        let screenAspect = Double(screen.width / screen.height)
        // Within 25% is close enough that fit leaves no distracting margin.
        return abs(boardAspect - screenAspect) / screenAspect < 0.25
    }
}
```

- [ ] **Step 4: Implement `ViewerOverlay.swift`**

```swift
import SwiftUI

/// Transient chrome over the board.
struct ViewerOverlay: View {
    let panelName: String
    let onPanels: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack {
            HStack(spacing: 20) {
                Text(panelName)
                    .font(Fiesta.Text.heading)
                    .foregroundStyle(Fiesta.Colors.foreground)
                Spacer()
                Button("Panels", action: onPanels).font(Fiesta.Text.body)
                Button("Settings", action: onSettings).font(Fiesta.Text.body)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Fiesta.Metrics.cornerRadius))
            .padding(Fiesta.Metrics.safeInset)
            Spacer()
        }
        .transition(.opacity)
    }
}

/// The amber dot from the web viewer: the board is unreachable, the last
/// frame is still true, and the app is still trying.
struct OfflineDot: View {
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Circle()
                    .fill(Fiesta.Colors.offline)
                    .frame(width: 16, height: 16)
                    .padding(Fiesta.Metrics.safeInset)
                    .accessibilityLabel("Disconnected from FiestaBoard. Showing the last message.")
            }
        }
    }
}
```

- [ ] **Step 5: Implement `ViewerScreen.swift`**

```swift
import SwiftUI

struct ViewerScreen: View {
    let ref: String
    @Environment(AppModel.self) private var app
    @State private var model: ViewerModel?

    /// Injectable so render tests can drive a fixed snapshot.
    init(ref: String, model: ViewerModel? = nil) {
        self.ref = ref
        _model = State(initialValue: model)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Board black, not pure black: matches the flaps behind it.
                BoardColor.black.swiftUI.ignoresSafeArea()

                if model?.snapshot.deleted == true {
                    deletedState
                } else if let layout = try? model?.layout(for: proxy.size) {
                    BoardCanvas(layout: layout,
                                background: model?.snapshot.panel?.backgroundColor ?? .black,
                                animated: model?.snapshot.panel?.animationsEnabled ?? false)
                        .frame(width: layout.width, height: layout.height)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView().tint(Fiesta.Colors.brand)
                }

                if model?.snapshot.connection == .stale { OfflineDot() }

                if model?.overlayVisible == true {
                    ViewerOverlay(panelName: model?.snapshot.panel?.name ?? "Panel",
                                  onPanels: { model?.stop(); app.showPanels() },
                                  onSettings: { model?.stop(); app.showSettings() })
                }
            }
            // Auto-dim uses the TV's own clock, matching the web viewer.
            .opacity(model?.snapshot.dimmed == true ? 0.35 : 1.0)
            .animation(.easeInOut(duration: 1.0), value: model?.snapshot.dimmed)
        }
        .ignoresSafeArea()
        .onAppear {
            if model == nil { model = ViewerModel(app: app, ref: ref) }
            model?.start()
            // A board on a wall must not be put to sleep by the TV.
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            model?.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onMoveCommand { _ in model?.showOverlay() }
        .onPlayPauseCommand { model?.showOverlay() }
        .onExitCommand { model?.stop(); app.showPanels() }
    }

    private var deletedState: some View {
        VStack(spacing: 16) {
            Text("This panel no longer exists")
                .font(Fiesta.Text.heading)
                .foregroundStyle(Fiesta.Colors.foreground)
            Text("It was deleted in the FiestaBoard app.")
                .font(Fiesta.Text.body)
                .foregroundStyle(Fiesta.Colors.mutedForeground)
            FiestaButton("Back to panels") { model?.stop(); app.showPanels() }
                .frame(width: 420)
        }
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `./build-and-run.sh --test`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(ui): the panel viewer

Full-screen board with no chrome. Any button wakes a transient overlay
that fades — tvOS has focus rather than a pointer, so that is what
'move the cursor to get back' becomes here.

A lost connection keeps the last frame up and adds only the amber dot,
matching the web viewer: a board on a wall showing a stale message is
far better than one showing an error.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 14: Settings and the re-fit flow

**Files:**
- Modify: `Sources/UI/SettingsScreen.swift`
- Create: `Sources/UI/SettingsModel.swift`, `Tests/SettingsScreenTests.swift`

**Interfaces:**
- Consumes: `AppModel`, `ConnectionStore`, `BoardGeometry.computeAutofitGrid`, `FiestaClient.updatePanel`
- Produces:
  - `SettingsModel` — `panels: [Panel]`, `defaultPanelRef: String?`, `sizing: BoardSizing`, `resizeDiagonal: Double`, `previewGrid: String`, `load() async`, `setDefaultPanel(_:)`, `setSizing(_:)`, `resize(panel:) async`, `signOut()`, `forget()`
  - `SettingsModel.presetDiagonals: [Double]`

- [ ] **Step 1: Write the failing tests**

```swift
import SwiftUI
import XCTest
@testable import FiestaBoardTV

@MainActor
final class SettingsScreenTests: XCTestCase {

    private func makeApp() async -> AppModel {
        let app = AppModel(connection: ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.settings.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) }))
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/auth/status")
        _ = try? await app.connection.connect(to: URL(string: "http://host:4420")!, displayName: "Board")
        return app
    }

    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    func testSettingADefaultPanelPersists() async {
        let app = await makeApp()
        let model = SettingsModel(app: app)
        model.setDefaultPanel("abc123def456")
        XCTAssertEqual(app.connection.saved?.defaultPanelRef, "abc123def456")
    }

    func testClearingTheDefaultPanelPersists() async {
        let app = await makeApp()
        let model = SettingsModel(app: app)
        model.setDefaultPanel("abc123def456")
        model.setDefaultPanel(nil)
        XCTAssertNil(app.connection.saved?.defaultPanelRef)
    }

    /// The preview is what makes the re-fit safe to accept: you see the new
    /// grid before the server reshapes anything.
    func testPreviewShowsTheGridADiagonalWouldProduce() async {
        let app = await makeApp()
        let model = SettingsModel(app: app)
        model.resizeDiagonal = 65
        XCTAssertEqual(model.previewGrid, "30 × 12", "65\" 16:9 is a 2x4 block grid")
        model.resizeDiagonal = 85
        XCTAssertEqual(model.previewGrid, "45 × 18", "85\" 16:9 is a 3x6 block grid")
    }

    func testResizePatchesTheDiagonal() async throws {
        let app = await makeApp()
        let model = SettingsModel(app: app)
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))

        StubURLProtocol.enqueue(.json(#"{"status":"success","panel":\#(Fixtures.panelJSON)}"#),
                                for: "/panels/")
        model.resizeDiagonal = 85
        await model.resize(panel: panel)

        let patch = StubURLProtocol.requests.first { $0.method == "PATCH" }
        let body = try XCTUnwrap(patch?.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["screen_diagonal_inches"] as? Double, 85)
    }

    /// Reshaping can strand pages authored for the old grid. The server
    /// warns; swallowing that would be rude.
    func testResizeSurfacesStrandedPages() async throws {
        let app = await makeApp()
        let model = SettingsModel(app: app)
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))

        let response = """
        {"status":"success","panel":\(Fixtures.panelJSON),
         "incompatible_references":[{"type":"page","id":"p1","name":"Welcome"},
                                    {"type":"page","id":"p2","name":"Hours"}]}
        """
        StubURLProtocol.enqueue(.json(response), for: "/panels/")
        await model.resize(panel: panel)

        let warning = try XCTUnwrap(model.warningMessage)
        XCTAssertTrue(warning.contains("2"), "the count of stranded pages must be stated")
    }

    func testResizeFailureIsReported() async throws {
        let app = await makeApp()
        let model = SettingsModel(app: app)
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        await model.resize(panel: panel)   // nothing enqueued
        XCTAssertNotNil(model.errorMessage)
    }

    func testSigningOutClearsTheCredentialAndAsksToSignIn() async {
        let app = await makeApp()
        let model = SettingsModel(app: app)
        model.signOut()
        XCTAssertEqual(app.route, .signIn)
    }

    func testForgettingTheBoardReturnsToConnect() async {
        let app = await makeApp()
        let model = SettingsModel(app: app)
        model.forget()
        XCTAssertNil(app.connection.saved)
        XCTAssertEqual(app.route, .connect)
    }

    func testPresetsCoverCommonTVSizes() {
        XCTAssertTrue(SettingsModel.presetDiagonals.contains(55))
        XCTAssertTrue(SettingsModel.presetDiagonals.contains(65))
        XCTAssertTrue(SettingsModel.presetDiagonals.contains(85))
        XCTAssertEqual(SettingsModel.presetDiagonals.first, 32)
    }

    func testScreenRenders() async {
        let app = await makeApp()
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/panels")
        RenderHarness.render(SettingsScreen().environment(app))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./build-and-run.sh --test`
Expected: FAIL — `SettingsModel` undefined.

- [ ] **Step 3: Implement `SettingsModel.swift`**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class SettingsModel {

    static let presetDiagonals: [Double] = [32, 43, 50, 55, 65, 75, 85]

    var panels: [Panel] = []
    var isLoading = false
    var errorMessage: String?
    var warningMessage: String?
    var resizeDiagonal: Double = 65
    var sizing: BoardSizing = .fit

    private let app: AppModel

    init(app: AppModel) {
        self.app = app
        if let raw = UserDefaults.standard.string(forKey: "fiestaboard.sizing"),
           let stored = BoardSizing(rawValue: raw) {
            sizing = stored
        }
    }

    var defaultPanelRef: String? { app.connection.saved?.defaultPanelRef }

    var boardName: String { app.connection.saved?.displayName ?? "Not connected" }

    var boardAddress: String { app.connection.saved?.host.absoluteString ?? "" }

    /// The grid `resizeDiagonal` would produce, computed locally so the
    /// change can be seen before the server reshapes anything.
    var previewGrid: String {
        guard let grid = try? BoardGeometry.computeAutofitGrid(diagonal: resizeDiagonal) else {
            return "—"
        }
        return "\(grid.notesWide * BoardGeometry.noteCols) × \(grid.notesTall * BoardGeometry.noteRows)"
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            panels = try await app.connection.authorized { try await $0.panels() }
        } catch FiestaError.unauthorized {
            app.route = .signIn
        } catch {
            errorMessage = "Couldn't reach your FiestaBoard."
        }
    }

    func setDefaultPanel(_ ref: String?) {
        app.connection.setDefaultPanel(ref: ref)
    }

    func setSizing(_ sizing: BoardSizing) {
        self.sizing = sizing
        UserDefaults.standard.set(sizing.rawValue, forKey: "fiestaboard.sizing")
    }

    func resize(panel: Panel) async {
        errorMessage = nil
        warningMessage = nil
        do {
            let result = try await app.connection.authorized {
                try await $0.updatePanel(id: panel.id, diagonal: resizeDiagonal)
            }
            if !result.incompatibleReferences.isEmpty {
                let count = result.incompatibleReferences.count
                let noun = count == 1 ? "page was" : "pages were"
                warningMessage = "The grid changed. \(count) \(noun) authored for the old size and won't fill this one — edit them in the FiestaBoard app."
            }
            await load()
        } catch FiestaError.unauthorized {
            app.route = .signIn
        } catch {
            errorMessage = "Couldn't resize this panel."
        }
    }

    func signOut() {
        app.connection.signOut()
        app.route = .signIn
    }

    func forget() {
        app.disconnect()
    }
}
```

- [ ] **Step 4: Implement `SettingsScreen.swift`**

```swift
import SwiftUI

struct SettingsScreen: View {
    @Environment(AppModel.self) private var app
    @State private var model: SettingsModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 44) {
                Text("Settings").font(Fiesta.Text.title)
                    .foregroundStyle(Fiesta.Colors.foreground)

                if let message = model?.errorMessage {
                    Text(message).font(Fiesta.Text.body)
                        .foregroundStyle(Fiesta.Colors.destructive)
                }
                if let warning = model?.warningMessage {
                    Text(warning).font(Fiesta.Text.body)
                        .foregroundStyle(Fiesta.Colors.brand)
                }

                section("Board") {
                    labelled("Name", model?.boardName ?? "")
                    labelled("Address", model?.boardAddress ?? "")
                    HStack(spacing: 20) {
                        FiestaButton("Sign out") { model?.signOut() }
                        FiestaButton("Forget this board") { model?.forget() }
                    }
                }

                section("Open at launch") {
                    Text("Skip the list and go straight to a panel when the app opens.")
                        .font(Fiesta.Text.caption)
                        .foregroundStyle(Fiesta.Colors.mutedForeground)
                    ForEach(model?.panels ?? []) { panel in
                        FiestaButton(panel.name + (model?.defaultPanelRef == panel.id ? "  ✓" : "")) {
                            model?.setDefaultPanel(model?.defaultPanelRef == panel.id ? nil : panel.id)
                        }
                    }
                }

                section("Size") {
                    Picker("Sizing", selection: Binding(
                        get: { model?.sizing ?? .fit },
                        set: { model?.setSizing($0) })) {
                        Text("Fit the screen").tag(BoardSizing.fit)
                        Text("True flap size").tag(BoardSizing.trueScale)
                    }
                    .pickerStyle(.segmented)

                    Text(model?.sizing == .trueScale
                         ? "Flaps render at real Vestaboard size. Expect black margins unless the panel was built for this screen."
                         : "The board fills the screen, keeping its shape.")
                        .font(Fiesta.Text.caption)
                        .foregroundStyle(Fiesta.Colors.mutedForeground)
                }

                section("Resize a panel for this TV") {
                    Text("Rebuilds the panel's grid on your FiestaBoard for a screen this size.")
                        .font(Fiesta.Text.caption)
                        .foregroundStyle(Fiesta.Colors.mutedForeground)

                    HStack(spacing: 16) {
                        ForEach(SettingsModel.presetDiagonals, id: \.self) { inches in
                            Button("\(Int(inches))\"") { model?.resizeDiagonal = inches }
                                .font(Fiesta.Text.body)
                        }
                    }

                    Text("New grid: \(model?.previewGrid ?? "—")")
                        .font(Fiesta.Text.body)
                        .foregroundStyle(Fiesta.Colors.foreground)

                    ForEach(model?.panels ?? []) { panel in
                        FiestaButton("Resize \(panel.name)") {
                            Task { await model?.resize(panel: panel) }
                        }
                    }
                }

                FiestaButton("Done") { app.showPanels() }
                    .frame(width: 420)
            }
            .padding(Fiesta.Metrics.safeInset)
            .frame(maxWidth: 1200, alignment: .leading)
        }
        .task {
            if model == nil { model = SettingsModel(app: app) }
            await model?.load()
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(Fiesta.Text.heading)
                .foregroundStyle(Fiesta.Colors.foreground)
            content()
        }
    }

    private func labelled(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Fiesta.Colors.mutedForeground)
            Spacer()
            Text(value).foregroundStyle(Fiesta.Colors.foreground)
        }
        .font(Fiesta.Text.body)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `./build-and-run.sh --test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(ui): settings and the resize-for-this-TV flow

Connection, default panel, sizing mode, and a re-fit that previews the
resulting grid locally before PATCHing — you see 30x12 become 45x18
before the server reshapes anything.

When the server reports pages authored for the old grid, the count is
shown rather than swallowed: reshaping someone's board out from under
their pages should not be silent.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 15: Fonts, icon, and release readiness

**Files:**
- Create: `Resources/SplineSansMono.ttf`, `Resources/OFL.txt`, `Sources/UI/Assets.xcassets/…`, `LICENSE`, `docs/PUBLISHING.md`
- Modify: `project.yml`, `README.md`

- [ ] **Step 1: Vendor the board font**

```bash
mkdir -p Resources
curl -sL -o Resources/SplineSansMono.ttf \
  "https://github.com/google/fonts/raw/main/ofl/splinesansmono/SplineSansMono%5Bwght%5D.ttf"
curl -sL -o Resources/OFL.txt \
  "https://github.com/google/fonts/raw/main/ofl/splinesansmono/OFL.txt"
file Resources/SplineSansMono.ttf   # must report TrueType Font data
```

Spline Sans Mono is FiestaUI's `--font-mono`, licensed OFL — the licence
file ships beside it. Add to `project.yml` under the app target's
`sources`:

```yaml
      - path: Resources
        type: folder
```

and to the app target's `info.properties`:

```yaml
        UIAppFonts: [SplineSansMono.ttf]
```

- [ ] **Step 2: Verify the font actually registers**

Add to `Tests/BoardCanvasTests.swift`:

```swift
func testTheBoardFontRegistersFromTheBundle() {
    BoardFont.registerIfNeeded()
    XCTAssertNotNil(UIFont(name: BoardFont.familyName, size: 24),
                    "Spline Sans Mono must load from the bundle — the system fallback is a degradation, not the target")
}
```

Run: `./build-and-run.sh --test`
Expected: PASS. If it fails, confirm the PostScript family name with
`fc-query Resources/SplineSansMono.ttf | head -3` (or open the file in
Font Book) and set `BoardFont.familyName` to what it actually reports —
variable fonts sometimes register under a different family name than the
filename suggests.

- [ ] **Step 3: Add the app icon and Top Shelf assets**

tvOS requires a layered `App Icon & Top Shelf Image` asset. Create
`Sources/UI/Assets.xcassets` with a `Brand Assets` set containing:
- App Icon — 3 layers, 400×240 and 1280×768
- Top Shelf Image — 1920×720 and 3840×1440
- Top Shelf Image Wide — 2320×720 and 4640×1440

Build the layers from the fiesta orange `#f5a623` ground with the board
wordmark; the source art is `fiesta-icon.png` in the FiestaBoard repo.
Export at the sizes above. A missing icon fails App Store validation but
not the build, so this step is verified by `xcodebuild` archive in Step 5.

- [ ] **Step 4: Write `LICENSE` and `docs/PUBLISHING.md`**

`PUBLISHING.md` records what submission needs, so it is not rediscovered:

- Bundle `com.fiestaboard.tv`, a `DEVELOPMENT_TEAM` set locally (never committed)
- App Store name **FiestaBoard for Apple TV**, subtitle "Your panels, on your TV"
- The 5.2.5 naming risk and the fallback name (**FiestaBoard**), per the spec §12
- Privacy: the app collects nothing. Data Safety answers are all "no" —
  the credential stays in the device Keychain and the only network traffic
  is to the user's own FiestaBoard.
- `NSLocalNetworkUsageDescription` is required and is already in `Info.plist`
- Review notes must include a demo FiestaBoard address or a video, since a
  reviewer has no board on their network

- [ ] **Step 5: Verify a release build archives**

```bash
xcodegen generate
xcodebuild -project FiestaBoardTV.xcodeproj -scheme FiestaBoardTV \
  -configuration Release -destination "generic/platform=tvOS" \
  -derivedDataPath build archive -archivePath build/FiestaBoardTV.xcarchive \
  CODE_SIGNING_ALLOWED=NO
```

Expected: ARCHIVE SUCCEEDED. Signing is off because CI has no certificate;
this proves the Release configuration compiles and the bundle assembles.

- [ ] **Step 6: Add the archive check to CI**

Append to `.github/workflows/ci.yml`, in the same job after the test step:

```yaml
      - name: Archive (unsigned)
        run: |
          xcodebuild -project FiestaBoardTV.xcodeproj \
            -scheme FiestaBoardTV \
            -configuration Release \
            -destination "generic/platform=tvOS" \
            -derivedDataPath build \
            archive -archivePath build/FiestaBoardTV.xcarchive \
            CODE_SIGNING_ALLOWED=NO
```

- [ ] **Step 7: Run the full suite and the app**

```bash
./build-and-run.sh --test
./build-and-run.sh
```

Expected: tests PASS, and the app launches on the simulator showing the
Connect screen scanning for boards.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "chore: vendor the board font, app icon, and publishing notes

Spline Sans Mono (OFL) is FiestaUI's mono face, so shipping it is what
makes the glyphs on the TV the same shapes as in the web viewer rather
than a system-font approximation.

CI now also archives a Release build unsigned, which catches
configuration breakage that a Debug simulator test never would.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage.** §2 scope → Tasks 11–14. §3 server contract → Task 4;
auth and the single silent re-login → Task 5. §4 layers → Task 1 (guard),
2–9 (Core), 8 (Render), 10–14 (UI). §5 shared spec file → Task 2, asserted
in Tasks 2 and 3. §6 rendering → Tasks 7–8; the hardware performance
checkpoint is called out below as it needs a device, not a task. §7 sizing
→ Task 7 (`BoardSizing`), Task 13 (`gridSuitsScreen`), Task 14 (re-fit and
`incompatible_references`). §8 failure behaviour → Task 9 (stale, deleted,
blank), Task 13 (amber dot, idle timer, auto-dim opacity). §9 configuration
→ Task 1. §10 Android → the Core layering rule (Task 1 guard) and
`board-spec.json` (Task 2). §11 testing → every task. §12 naming → Task 15.
§13 CI → Tasks 1 and 15. §14 FiestaBoard PRs → deliberately out of this
plan; they are optional and non-blocking, and are raised after the app
works.

**Deferred to a device, not a task:** the spec's §6 checkpoint — measure
`Canvas` at 45×18 with animation on, on real hardware, and fall back to
`CALayer` flips only if it cannot hold 60fps. The simulator cannot answer
this, so it is a post-build measurement with a known remedy rather than a
planned change.

**Placeholder scan:** no TBDs; every code step carries real code.

**Type consistency:** `BoardCell`, `BoardColor`, `Code62Glyph` (Task 2) are
used unchanged in Tasks 7–9. `BoardGeometry.colPitchIn` exists both as a
constant and as `colPitchIn(deviceType:)`; both are referenced correctly
(Task 13 uses the function, Tasks 3 and 7 the constant). `PanelStore`'s
`snapshots()` returns `AsyncStream<PanelSnapshot>` in Tasks 9 and 13.
`ConnectionStore.authorized` is used identically in Tasks 12 and 14.
`AppModel.route` is `Route` throughout.
