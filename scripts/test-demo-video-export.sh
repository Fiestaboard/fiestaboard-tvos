#!/usr/bin/env bash
# A moving 60 Hz source must retain every frame through the demo exporter.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEMO_TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$DEMO_TEST_DIR"' EXIT
ffmpeg -hide_banner -loglevel error -f lavfi \
  -i 'testsrc2=size=320x180:rate=60:duration=1' -c:v libx264 \
  "$DEMO_TEST_DIR/source.mov"
bash "$SCRIPT_DIR/export-demo-video.sh" "$DEMO_TEST_DIR/source.mov" "$DEMO_TEST_DIR/demo.mp4"
python3 - "$DEMO_TEST_DIR" <<'PY'
import json, pathlib, subprocess, sys
root = pathlib.Path(sys.argv[1])
movie = root / 'demo.mp4'
probe = json.loads(subprocess.check_output([
    'ffprobe', '-v', 'error', '-select_streams', 'v:0',
    '-show_entries', 'stream=width,height,r_frame_rate,nb_frames', '-of', 'json', str(movie)
]))['streams'][0]
assert probe['r_frame_rate'] == '60/1', probe
assert int(probe['nb_frames']) == 60, probe
assert (probe['width'], probe['height']) == (1920, 1080), probe
hashes = subprocess.check_output([
    'ffmpeg', '-v', 'error', '-i', str(movie), '-f', 'framemd5', '-'
], text=True)
distinct = {line.split(',')[-1].strip() for line in hashes.splitlines() if not line.startswith('#')}
assert len(distinct) == 60, f'Only {len(distinct)} distinct frames survived'
assert (root / 'source.mov').exists(), 'Original recording was deleted'
print('Video export OK: 60 distinct frames, 1080p60, original retained.')
PY
