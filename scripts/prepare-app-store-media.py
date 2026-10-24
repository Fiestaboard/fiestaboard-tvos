#!/usr/bin/env python3
"""Extract named native screenshots and trim a real simulator walkthrough."""
import json
from pathlib import Path
import shutil
import struct
import subprocess
import sys


def prepare(root: Path) -> None:
    manifest = json.loads((root / "attachments/manifest.json").read_text())
    selected = {}
    for test in manifest:
        for item in test.get("attachments", []):
            name = item.get("suggestedHumanReadableName", "")
            if name.startswith("AppStore-") and item["exportedFileName"].endswith(".png"):
                # xcresult appends an attachment index and UUID to the name.
                stem = name.split("_", 1)[0].removeprefix("AppStore-")
                selected[stem] = item
    expected = ["01-connect", "02-sign-in", "03-tv-sign-in-code", "04-panels",
                "05-split-flap", "06-panel-appearance", "07-this-apple-tv",
                "08-square-led", "09-round-led", "10-walkthrough-end"]
    if set(selected) != set(expected):
        raise ValueError(f"Missing or unexpected media captures: {sorted(selected)}")
    screenshots = root / "screenshots"
    screenshots.mkdir(exist_ok=True)
    for stem in expected[:-1]:
        source = root / "attachments" / selected[stem]["exportedFileName"]
        data = source.read_bytes()
        dimensions = struct.unpack(">II", data[16:24])
        if data[:8] != b"\x89PNG\r\n\x1a\n" or dimensions not in ((1920, 1080), (3840, 2160)):
            raise ValueError(f"Expected a native 16:9 TV screenshot: {source}")
        destination = screenshots / f"{stem}.png"
        if dimensions == (1920, 1080):
            shutil.copyfile(source, destination)
        else:
            subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", str(source),
                            "-vf", "scale=1920:1080:flags=lanczos", "-frames:v", "1", str(destination)], check=True)
    # Use captured screenshot timestamps to exclude the simulator Home screen,
    # test runner startup, and the app's termination. This retains real timing.
    recording_start = float((root / "recording-start.txt").read_text())
    start = max(0, selected[expected[0]]["timestamp"] - recording_start)
    end = selected[expected[-1]]["timestamp"] - recording_start + 1
    if not 20 < end - start < 300:
        raise ValueError(f"Unexpected walkthrough duration: {end - start:.2f} seconds")
    destination = root / "reviewer-walkthrough.mp4"
    subprocess.run([
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-fflags", "+igndts",
        "-ss", f"{start:.3f}", "-i", str(root / "capture.mov"), "-t", f"{end - start:.3f}",
        "-vf", "scale=1920:1080,fps=60", "-an", "-c:v", "libx264", "-preset", "fast",
        "-crf", "18", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(destination)
    ], check=True)
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(destination),
                    "-f", "null", "-"], check=True)
    probe = subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-show_format",
                            "-of", "json", str(destination)], check=True, capture_output=True, text=True)
    metadata = json.loads(probe.stdout)
    videos = [stream for stream in metadata["streams"] if stream["codec_type"] == "video"]
    if len(videos) != 1 or (videos[0]["width"], videos[0]["height"]) != (1920, 1080):
        raise ValueError("The reviewer video must contain one 1920 × 1080 video stream")
    if videos[0]["codec_name"] != "h264" or videos[0]["r_frame_rate"] != "60/1":
        raise ValueError("The reviewer video must use H.264 at 60 fps")
    if abs(float(metadata["format"]["duration"]) - (end - start)) > 1:
        raise ValueError("The recording ended before the complete walkthrough was captured")
    (root / "video-metadata.json").write_text(probe.stdout)
    chapters = [{"screen": stem, "seconds": round(selected[stem]["timestamp"] - recording_start - start, 3)}
                for stem in expected[:-1]]
    (root / "chapters.json").write_text(json.dumps(chapters, indent=2) + "\n")
    (root / "REVIEWER-NOTES.txt").write_text(
        "FiestaBoard for Apple TV — reviewer walkthrough\n\n"
        "This video records the real tvOS app in an Apple TV simulator. "
        "An in-process local HTTP fixture supplies representative FiestaBoard "
        "discovery, authentication, panel, and frame responses. TV sign-in "
        "approval is simulated by that server. No physical Raspberry Pi "
        "or production board is shown or contacted.\n\n"
        "The app normally requires a reachable FiestaBoard server on the same "
        "network, with the open-source FiestaBoard software configured and "
        "panels created. It does not include a hosted service or standalone "
        "content editor.\n\n"
        "Sequence: discover board, sign-in choices, QR/manual TV sign-in, "
        "panel browser, split-flap viewer, shared panel appearance, settings "
        "for this Apple TV, square LED viewer, round LED viewer. "
        "The accompanying chapters.json gives screen timestamps.\n\n"
        "Screenshots show actual app captures, resized to 1920 × 1080 where "
        "the simulator captures at 4K; no content is composited or retouched. The video is "
        "trimmed to the app walkthrough and encoded as H.264 at 1920 × 1080, "
        "60 fps without audio. It is supporting review evidence, not an "
        "App Store preview.\n"
    )
    print(f"Prepared {len(expected) - 1} screenshots and {end - start:.1f}s reviewer walkthrough in {root}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: prepare-app-store-media.py media-directory")
    prepare(Path(sys.argv[1]))
