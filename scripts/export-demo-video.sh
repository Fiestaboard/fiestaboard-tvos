#!/usr/bin/env bash
# Preserve 60 Hz flap motion. fps=30 drops half the animation samples;
# an 80 ms drum step then has only two or three frames to show the fall.
# This cannot recover frames already dropped by the simulator or device.
set -euo pipefail
if [[ $# != 2 ]]; then
  echo "Usage: $0 source.mov destination.mp4" >&2
  exit 2
fi
if [[ "$1" == "$2" ]]; then
  echo "Source and destination must differ." >&2
  exit 2
fi
# Xcode captures can carry misleading decode timestamps. Honor presentation
# timestamps so FFmpeg does not substitute DTS and jump the visible timeline.
ffmpeg -y -hide_banner -loglevel error -fflags +igndts -i "$1" \
  -vf 'scale=1920:1080,fps=60' -an \
  -c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p \
  -movflags +faststart "$2"
ffmpeg -hide_banner -loglevel error -i "$2" -f null -
