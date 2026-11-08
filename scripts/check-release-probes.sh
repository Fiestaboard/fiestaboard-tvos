#!/usr/bin/env bash
# Usage: check-release-probes.sh <path/to/FiestaBoardTV.xcarchive>
#
# Fails if a Release archive still carries the DEBUG Figma parity probes
# (PHASE-4-TV-PLAN §2.0 "Probe identifiers", S4): the figmaNode modifier, the
# FigmaGeometryRegistry, the parity fixture screen, their launch arguments, or
# a Figma node id literal that only probes use. These are compiled out with
# `#if DEBUG`; this proves it on what would ship.
set -euo pipefail

archive=${1:?usage: check-release-probes.sh <xcarchive>}
apps="$archive/Products/Applications"
if [ ! -d "$apps" ]; then
  echo "No Products/Applications in $archive" >&2
  exit 1
fi

pattern='FigmaGeometryRegistry|FigmaNodeModifier|figmaNode|ParityFixture|fiestaboard\.figmaProbeOut|fiestaboard\.parityFixture|149:182603'
found=0
while IFS= read -r -d '' binary; do
  if hits=$(strings -a "$binary" | grep -E "$pattern" | sort -u) && [ -n "$hits" ]; then
    echo "DEBUG parity probes in Release binary ${binary#"$archive"/}:" >&2
    printf '  %s\n' $hits >&2
    found=1
  fi
done < <(find "$apps" -type f -perm -u+x -print0)

if [ "$found" -ne 0 ]; then exit 1; fi
echo "No DEBUG parity probes in $(basename "$archive")"
