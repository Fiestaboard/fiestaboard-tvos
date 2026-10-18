#!/usr/bin/env bash
# Sources/Core is the Android port target: it must stay free of UI frameworks
# and of the Apple-only reactive plumbing that cannot cross to Kotlin.
#
# docs/HANDOFF.md has always stated the whole rule — no SwiftUI, no UIKit, no
# Combine, no @Observable, and nothing from TVServices — while this script
# only ever grepped for the first two. A rule that is written down and not
# enforced is enforced by whoever notices in review, which is nobody.
set -euo pipefail
cd "$(dirname "$0")/.."

banned='SwiftUI|UIKit|AppKit|WatchKit|Combine|Observation|TVServices'
readable='SwiftUI, UIKit, AppKit, WatchKit, Combine, Observation, @Observable and TVServices'

# Two patterns rather than one. An import is matched anchored to the start of
# a line, where prose cannot reach it. The macro and protocol names have to be
# matched anywhere — and they legitimately appear in the comments that explain
# this very rule ("Deliberately not an ObservableObject: Core stays free of
# Combine…" in ConnectionStore.swift). So comment lines are dropped before the
# second pattern runs: the guard reads the code, not the documentation of
# itself. Do not soften the pattern to get past that comment; drop the comment
# line instead, as here.
imports='^[[:space:]]*(@[A-Za-z]+[[:space:]]+)*(public|internal|package|fileprivate|private)?[[:space:]]*import[[:space:]]+('"$banned"')([[:space:]]|$|\.)'
symbols='@Observable|@ObservationIgnored|@ObservationTracked|@Published|ObservableObject|AnyPublisher|(Passthrough|CurrentValue)Subject|TVTopShelf'

scan() {
  grep -rnE "$1" Sources/Core --include='*.swift' 2>/dev/null || true
}

# A hit is `path:line:text`; the comment test applies to the text only.
drop_comments() {
  grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|\*|/\*)' || true
}

violations=$( { scan "$imports"; scan "$symbols" | drop_comments; } | sort -u )

if [ -n "$violations" ]; then
  echo "$violations"
  echo "LAYERING VIOLATION: Sources/Core must stay free of $readable (see above)." >&2
  exit 1
fi
echo "Layering OK: Sources/Core is free of $readable."
