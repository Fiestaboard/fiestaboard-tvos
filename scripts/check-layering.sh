#!/usr/bin/env bash
# Sources/Core is the Android port target: it must stay free of UI frameworks.
set -euo pipefail
cd "$(dirname "$0")/.."

if grep -rn "import SwiftUI\|import UIKit" Sources/Core 2>/dev/null; then
  echo "LAYERING VIOLATION: UI framework imported in Sources/Core (see above)." >&2
  exit 1
fi
echo "Layering OK: Sources/Core is UI-framework-free."
