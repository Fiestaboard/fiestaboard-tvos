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

# Symbols and launch arguments, then any Figma node id: an instance path
# (`I166:147296;149:182603…`), a bare page or component id (`166:147344`,
# `154:8169`: 2–4 digits, a colon, 3–7 digits — a 4-digit pair such as
# 1920:1080 reads as one too, and the Release binary has none; 16:9 and
# 12:30 don't),
# or a DEBUG fixture id (`parity:glass`). Ids stored in a view's property
# survive into Release even though inlined figmaNode arguments do not.
pattern='FigmaGeometryRegistry|FigmaNodeModifier|figmaNode|ParityFixture|fiestaboard\.figmaProbeOut|fiestaboard\.parityFixture'
# A12: the DEBUG timing and review probes A4b-A11 added, and their defaults
# keys. Each is compiled out with `#if DEBUG`.
pattern+='|PanelNavigationProbe|RenderPacingProbe|MatrixPreparationProbe|FocusChangeProbe|DrawnPreviewMarker'
pattern+='|ConnectReviewDiscovery|fiestaboard\.(panelProfile|renderProfile|viewerMaterial)'
pattern+='|I[0-9]+:[0-9]+;[0-9]+:[0-9]+|(^|[^0-9])[0-9]{2,4}:[0-9]{3,7}([^0-9]|$)|parity:[a-z]+'
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
