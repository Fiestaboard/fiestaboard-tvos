#!/usr/bin/env bash
# Build FiestaBoard for Apple TV and launch it on a tvOS simulator.
# Usage: ./build-and-run.sh [--test]
set -euo pipefail
cd "$(dirname "$0")"

./scripts/check-layering.sh
./scripts/check-brand-assets.swift

command -v xcodegen >/dev/null 2>&1 && xcodegen generate

DEVICE_ID=$(xcrun simctl list devices available | ./scripts/select-tvos-simulator.sh)
if [ -z "${DEVICE_ID:-}" ]; then
  echo "No Apple TV simulator found. Xcode > Settings > Components > tvOS Simulator." >&2
  exit 1
fi
echo "Using simulator: $DEVICE_ID"

DEST="platform=tvOS Simulator,id=$DEVICE_ID"

if [ "${1:-}" = "--test" ]; then
  xcodebuild -project FiestaBoardTV.xcodeproj -scheme FiestaBoardTV \
    -destination "$DEST" -derivedDataPath build -quiet test
  exit 0
fi

xcodebuild -project FiestaBoardTV.xcodeproj -scheme FiestaBoardTV \
  -destination "$DEST" -derivedDataPath build -quiet build

APP_PATH=$(find build/Build/Products -name "FiestaBoardTV.app" -type d | head -1)
xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
open -a Simulator 2>/dev/null || true
xcrun simctl install "$DEVICE_ID" "$APP_PATH"
xcrun simctl launch "$DEVICE_ID" com.fiestaboard.tv
