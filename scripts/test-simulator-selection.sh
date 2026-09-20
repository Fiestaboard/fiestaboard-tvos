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
