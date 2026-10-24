#!/usr/bin/env bash
# Dedicated, opt-in test: the ordinary CI suite skips its intentional holds.
set -euo pipefail
if [[ $# != 1 ]]; then echo "Usage: $0 tvOS-simulator-UDID" >&2; exit 2; fi
MEDIA_DIR=build/app-store-media
mkdir -p "$MEDIA_DIR"
# xcodebuild forwards TEST_RUNNER_ values to its UI test runner after removing
# the prefix. No production app launch path or external server is added.
export TEST_RUNNER_FIESTA_APP_STORE_MEDIA=1
python3 -c 'import time; print(time.time())' > "$MEDIA_DIR/recording-start.txt"
xcrun simctl io "$1" recordVideo --codec=h264 --force "$MEDIA_DIR/capture.mov" > "$MEDIA_DIR/recording.log" 2>&1 &
RECORDING_PID=$!
stop_recording() {
  if kill -0 "$RECORDING_PID" 2>/dev/null; then
    kill -INT "$RECORDING_PID"
    wait "$RECORDING_PID" || true
  fi
}
trap stop_recording EXIT
# Let simctl initialize the recording before XCTest launches the app.
sleep 2
xcodebuild -project FiestaBoardTV.xcodeproj -scheme FiestaBoardTV \
  -destination "platform=tvOS Simulator,id=$1" -derivedDataPath build \
  -resultBundlePath build/app-store-media.xcresult \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:FiestaBoardTVUITests/AppStoreMediaUITests \
  test-without-building
stop_recording
trap - EXIT
xcrun xcresulttool export attachments --path build/app-store-media.xcresult \
  --output-path "$MEDIA_DIR/attachments"
python3 scripts/prepare-app-store-media.py "$MEDIA_DIR"
