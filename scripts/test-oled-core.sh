#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
PACKAGE=$(mktemp -d /tmp/fiestaboard-oled.XXXXXX)
trap 'rm -rf "$PACKAGE"' EXIT
mkdir -p "$PACKAGE/Sources/OLEDCore" "$PACKAGE/Tests/OLEDCoreTests"
printf '%s\n' '// swift-tools-version: 5.9' 'import PackageDescription' 'let package = Package(name: "OLEDCore", products: [.library(name: "OLEDCore", targets: ["OLEDCore"])], targets: [.target(name: "OLEDCore"), .testTarget(name: "OLEDCoreTests", dependencies: ["OLEDCore"])])' > "$PACKAGE/Package.swift"
if [[ -f Sources/Core/OLEDCare.swift ]]; then cp Sources/Core/OLEDCare.swift "$PACKAGE/Sources/OLEDCore/"; else touch "$PACKAGE/Sources/OLEDCore/Empty.swift"; fi
cp Tests/OLEDCareTests.swift "$PACKAGE/Tests/OLEDCoreTests/"
export CLANG_MODULE_CACHE_PATH="$PACKAGE/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PACKAGE/module-cache"
swift test --package-path "$PACKAGE" --scratch-path "$PACKAGE/build" --disable-sandbox
