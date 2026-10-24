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
    index = None
    for test in manifest:
        for item in test.get("attachments", []):
            name = item.get("suggestedHumanReadableName", "")
            # xcresult removes an attachment's extension before appending its
            # export index/UUID, e.g. AppStore-media-index_0_UUID.json.
            if name.startswith("AppStore-media-index"):
                if index is not None:
                    raise ValueError("Expected one media index attachment")
                index = json.loads((root / "attachments" / item["exportedFileName"]).read_text())
            if name.startswith("AppStore-") and item["exportedFileName"].endswith(".png"):
                # xcresult appends an attachment index and UUID to the name.
                stem = name.split("_", 1)[0].removeprefix("AppStore-")
                selected[stem] = item
    if index is None or index.get("version") != 2:
        raise ValueError("The capture must include its version 2 media index")
    store_shots = index["expectedStoreScreenshots"]
    review_shots = index["expectedReviewScreenshots"]
    expected = store_shots + review_shots
    if len(store_shots) not in range(8, 11) or len(expected) != len(set(expected)):
        raise ValueError("Expected 8–10 unique store screenshots and separate review captures")
    roles = {shot["name"]: shot["role"] for shot in index["shots"]}
    if set(selected) != set(expected) or set(roles) != set(expected):
        raise ValueError(f"Missing or unexpected media captures: {sorted(selected)}")
    if any(roles[name] != "store" for name in store_shots) or any(roles[name] != "review" for name in review_shots):
        raise ValueError("Media index roles must agree with the controlled screenshot lists")
    required_events = {"split-flap-update-request", "split-flap-frame-received", "split-flap-settled",
                       "led-update-request", "led-frame-received", "led-settled"}
    if not required_events.issubset({event["event"] for event in index["events"]}):
        raise ValueError("The walkthrough must record both native HTTP content transitions")
    screenshots = root / "screenshots"
    if screenshots.exists():
        shutil.rmtree(screenshots)
    screenshots.mkdir()
    for stem in store_shots:
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
    start = max(0, selected[index["start"]]["timestamp"] - recording_start)
    end = selected[index["end"]]["timestamp"] - recording_start + 1
    if not 20 < end - start < 165:
        raise ValueError(f"Unexpected walkthrough duration: {end - start:.2f} seconds")
    destination = root / "reviewer-walkthrough.mp4"
    subprocess.run([
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-fflags", "+igndts",
        "-i", str(root / "capture.mov"),
        # simctl stores sparse frames. Fill the real presentation timeline
        # before trimming so an input seek cannot discard the current still
        # and jump to the next UI change. Always start the exported PTS at zero.
        "-vf", f"scale=1920:1080,fps=60,trim=start={start:.3f}:end={end:.3f},setpts=PTS-STARTPTS",
        "-an", "-c:v", "libx264", "-preset", "fast",
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
    origin = recording_start + start
    chapters = [{"screen": stem, "role": roles[stem], "seconds": round(selected[stem]["timestamp"] - origin, 3)}
                for stem in sorted(expected, key=lambda name: selected[name]["timestamp"]) if stem != index["end"]]
    events = [{**event, "seconds": round(event["timestamp"] - origin, 3)} for event in index["events"]]
    (root / "chapters.json").write_text(json.dumps(chapters, indent=2) + "\n")
    (root / "events.json").write_text(json.dumps(events, indent=2) + "\n")
    transitions = []
    for name in ("split-flap", "led"):
        update = next(event for event in events if event["event"] == f"{name}-update-request")
        received = next(event for event in events if event["event"] == f"{name}-frame-received")
        settled = next(event for event in events if event["event"] == f"{name}-settled")
        if not update["seconds"] <= received["seconds"] < settled["seconds"]:
            raise ValueError(f"Invalid {name} transition timing")
        transitions.append({"kind": name, "request_seconds": update["seconds"],
                            "frame_received_seconds": received["seconds"], "settled_seconds": settled["seconds"],
                            "suggested_clip_start": round(max(0, update["seconds"] - 0.75), 3),
                            "suggested_clip_end": round(settled["seconds"] + 0.75, 3),
                            "note": "Real HTTP frame update while viewer stays open; no transition added in editing."})
    (root / "transitions.json").write_text(json.dumps(transitions, indent=2) + "\n")
    (root / "media-index.json").write_text(json.dumps(index, indent=2) + "\n")
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
        "Sequence: discovery and TV sign-in, diverse panel browser, weather and "
        "departures split-flap boards, a white home-message board updating to "
        "a dinner note, a square LED clock, and a round LED landscape updating "
        "from sunset to starlight, followed by TV settings. All weather, "
        "departures and clock values are illustrative example data. Pixel art "
        "is original. No live weather or transit provider is connected.\n\n"
        "Both content changes arrive over the normal HTTP frame poll while "
        "the viewer remains open. The app's own split-flap drums and LED pixel "
        "dissolve animate them; no transition is composited in editing. "
        "chapters.json records screen captures, events.json records update "
        "requests/frame receipt/settling, and transitions.json gives useful "
        "before-through-after clip ranges for visual inspection.\n\n"
        "Screenshots show actual app captures, resized to 1920 × 1080 where "
        "the simulator captures at 4K; no content is composited or retouched. The video is "
        "trimmed to the app walkthrough and encoded as H.264 at 1920 × 1080, "
        "60 fps without audio. It is supporting review evidence, not an "
        "App Store preview.\n"
    )
    print(f"Prepared {len(store_shots)} screenshots and {end - start:.1f}s reviewer walkthrough in {root}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: prepare-app-store-media.py media-directory")
    prepare(Path(sys.argv[1]))
