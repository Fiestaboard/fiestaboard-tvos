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

clean=$(make_archive clean "BoardCanvas")
./scripts/check-release-probes.sh "$clean" >/dev/null

for leak in FigmaGeometryRegistry figmaNode FigmaNodeModifier ParityFixtureView fiestaboard.figmaProbeOut \
            "I166:147296;149:182603"; do
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
