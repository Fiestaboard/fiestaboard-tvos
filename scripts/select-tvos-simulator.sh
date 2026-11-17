#!/usr/bin/env bash
set -euo pipefail

# Reads `xcrun simctl list devices available` on stdin and prints one Apple TV
# simulator UUID. Select by UUID so model names containing parentheses remain
# unambiguous.
#
# Prefers a full Apple TV 4K (scale 2, 3840x2160 px): Figma parity shots
# (PHASE-4-TV-PLAN §2.1) are compared against scale=2 exports of 1920x1080 pt
# slots, and the parity tests assert the scale. The "(at 1080p)" 4K variant
# and older Apple TVs are scale 1, so they are only a fallback.
uuid() { sed -nE 's/.*\(([[:xdigit:]-]{36})\) \((Booted|Shutdown)\) *$/\1/p'; }

tv=$(grep -E '^[[:space:]]*Apple TV' || true)
preferred=$(printf '%s\n' "$tv" | grep 'Apple TV 4K' | grep -v '(at 1080p)' || true)
{ printf '%s\n' "$preferred" | uuid; printf '%s\n' "$tv" | uuid; } | sed -n 1p
