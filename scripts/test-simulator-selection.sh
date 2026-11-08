#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

sample='    Apple TV 4K (3rd generation) (3AAC4E7C-8279-4E61-B3B6-BD64370C5AFD) (Shutdown)'
actual=$(printf '%s\n' "$sample" | ./scripts/select-tvos-simulator.sh)
expected='3AAC4E7C-8279-4E61-B3B6-BD64370C5AFD'
if [ "$actual" != "$expected" ]; then
  echo "Expected simulator id $expected; got $actual" >&2
  exit 1
fi

# Parity shots (D7) need scale 2: prefer an Apple TV 4K even when a 1080p
# Apple TV is listed first, and still fall back to any Apple TV.
mixed=$(cat <<'LIST'
-- tvOS 26.1 --
    Apple TV (8D0D2F2E-0000-4000-8000-000000000001) (Shutdown) 
    Apple TV 4K (3rd generation) (at 1080p) (8D0D2F2E-0000-4000-8000-000000000002) (Shutdown) 
    Apple TV 4K (3rd generation) (8D0D2F2E-0000-4000-8000-000000000003) (Shutdown) 
LIST
)
actual=$(printf '%s\n' "$mixed" | ./scripts/select-tvos-simulator.sh)
expected='8D0D2F2E-0000-4000-8000-000000000003'
if [ "$actual" != "$expected" ]; then
  echo "Expected the scale-2 Apple TV 4K $expected; got $actual" >&2
  exit 1
fi

only_hd='    Apple TV (8D0D2F2E-0000-4000-8000-000000000001) (Booted) '
actual=$(printf '%s\n' "$only_hd" | ./scripts/select-tvos-simulator.sh)
if [ "$actual" != '8D0D2F2E-0000-4000-8000-000000000001' ]; then
  echo "Expected the fallback Apple TV; got $actual" >&2
  exit 1
fi

actual=$(printf '%s\n' "-- iOS 26.1 --" "    iPhone 17 (8D0D2F2E-0000-4000-8000-000000000009) (Shutdown)" | ./scripts/select-tvos-simulator.sh)
if [ -n "$actual" ]; then
  echo "Expected no simulator from a list without an Apple TV; got $actual" >&2
  exit 1
fi
echo "simulator selection: ok"
