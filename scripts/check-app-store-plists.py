#!/usr/bin/env python3
"""Catch Apple's arm64 upload requirement in processed app/extension plists."""
import plistlib
import sys
from pathlib import Path

if len(sys.argv) < 3:
    raise SystemExit("Pass the app and embedded extension Info.plist files")
for value in sys.argv[1:]:
    path = Path(value)
    data = plistlib.loads(path.read_bytes())
    capabilities = data.get("UIRequiredDeviceCapabilities", [])
    present = (capabilities.get("arm64") is True if isinstance(capabilities, dict)
               else isinstance(capabilities, list) and "arm64" in capabilities)
    if not present:
        raise SystemExit(str(path) + ": missing required arm64 capability (ITMS-90502)")
    print(str(path) + ": arm64 capability declared")
