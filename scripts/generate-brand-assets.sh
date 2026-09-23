#!/usr/bin/env bash
# Rebuild the layered app icon and the static Top Shelf art.
#
# The generator is compiled against Sources/Render/TacoMark.swift rather than
# interpreted, so the artwork the app draws and the artwork the catalog ships
# come from one definition of the mark.
set -euo pipefail
cd "$(dirname "$0")/.."

BIN=$(mktemp -d)/generate-brand-assets
trap 'rm -rf "$(dirname "$BIN")"' EXIT

swiftc -O -o "$BIN" scripts/brand-assets/main.swift Sources/Render/TacoMark.swift
"$BIN"

./scripts/check-brand-assets.swift
