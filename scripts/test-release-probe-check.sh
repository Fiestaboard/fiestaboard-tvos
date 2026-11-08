#!/usr/bin/env bash
# Guards scripts/check-release-probes.sh, which the Release archive job runs
# to prove the DEBUG parity probes (figmaNode, FigmaGeometryRegistry, the
# parity fixture) are compiled out of what ships.
set -euo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

make_archive() { # name, payload
  local app="$tmp/$1.xcarchive/Products/Applications/FiestaBoardTV.app"
  mkdir -p "$app/PlugIns/FiestaBoardTopShelf.appex"
  printf 'CFBundleExecutable' > "$app/Info.plist"
  printf '\x00\x01release code\x00%s\x00more\x00' "$2" > "$app/FiestaBoardTV"
  printf '\x00extension\x00' > "$app/PlugIns/FiestaBoardTopShelf.appex/FiestaBoardTopShelf"
  chmod +x "$app/FiestaBoardTV" "$app/PlugIns/FiestaBoardTopShelf.appex/FiestaBoardTopShelf"
  echo "$tmp/$1.xcarchive"
}

# Ordinary strings that look a little like ids must still pass.
clean=$(make_archive clean "BoardCanvas 1920:1080 16:9 12:30 v1.0:2")
./scripts/check-release-probes.sh "$clean" >/dev/null

# Any Figma node id: an instance path (I…;…), a bare page-07b id, or a DEBUG
# fixture id — stored ids are not optimized away like inlined-call arguments.
for leak in FigmaGeometryRegistry figmaNode FigmaNodeModifier ParityFixtureView fiestaboard.figmaProbeOut \
            "I166:147296;149:182603" "I252:122495;1:2" "166:147344" "parity:glass"; do
  dirty=$(make_archive "dirty-$RANDOM" "x${leak}y")
  if ./scripts/check-release-probes.sh "$dirty" >/dev/null 2>&1; then
    echo "check-release-probes.sh accepted an archive containing $leak" >&2
    exit 1
  fi
done

if ./scripts/check-release-probes.sh "$tmp/missing.xcarchive" >/dev/null 2>&1; then
  echo "check-release-probes.sh accepted a missing archive" >&2
  exit 1
fi
echo "release probe check: ok"
