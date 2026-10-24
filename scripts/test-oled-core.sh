#!/bin/bash
# Compile the production Foundation policy and its actual XCTest cases on macOS.
# No simulator, generated production stubs, or package/plugin sandbox changes.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_BUILD=$(mktemp -d /tmp/fiestaboard-oled.XXXXXX)
trap 'rm -rf "$TEST_BUILD"' EXIT
SDK=$(xcrun --sdk macosx --show-sdk-path)
DEVELOPER=$(xcode-select -p)
FRAMEWORKS="$DEVELOPER/Platforms/MacOSX.platform/Developer/Library/Frameworks"
swiftc -sdk "$SDK" -module-cache-path "$TEST_BUILD/cache" -emit-module -emit-library -enable-testing -module-name OLEDCore Sources/Core/OLEDCare.swift -o "$TEST_BUILD/libOLEDCore.dylib" -emit-module-path "$TEST_BUILD/OLEDCore.swiftmodule"
cat > "$TEST_BUILD/main.swift" <<'SWIFT'
import Foundation
import XCTest
let suite = OLEDCareTests.defaultTestSuite
suite.run()
exit(suite.testRun?.hasSucceeded == true ? 0 : 1)
SWIFT

swiftc -sdk "$SDK" -module-cache-path "$TEST_BUILD/cache" -F "$FRAMEWORKS" -I "$DEVELOPER/Platforms/MacOSX.platform/Developer/usr/lib" -L "$DEVELOPER/Platforms/MacOSX.platform/Developer/usr/lib" -I "$TEST_BUILD" -L "$TEST_BUILD" -lOLEDCore -Xlinker -rpath -Xlinker "$TEST_BUILD" -Xlinker -rpath -Xlinker "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$DEVELOPER/Platforms/MacOSX.platform/Developer/usr/lib" Tests/OLEDCareTests.swift "$TEST_BUILD/main.swift" -o "$TEST_BUILD/tests"
"$TEST_BUILD/tests"
