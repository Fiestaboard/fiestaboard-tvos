#!/usr/bin/env python3
"""Read-only App Store release planner. Delivery is handled by Fastlane."""
import argparse
import base64
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import urllib.request

SOURCE_PATHS = ["Sources", "Resources", "TopShelf", "Spec", "project.yml", "Config/AppGroup.entitlements"]
REQUIRED_JOBS = ("build-and-test", "Release archive")
RELEASED = {"READY_FOR_SALE", "READY_FOR_DISTRIBUTION"}
ACTIVE = {"WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE",
          "PENDING_APPLE_RELEASE", "PROCESSING_FOR_APP_STORE", "PREORDER_READY_FOR_SALE"}
REJECTED = {"REJECTED", "METADATA_REJECTED", "DEVELOPER_REJECTED", "INVALID_BINARY"}


class ReleaseError(RuntimeError):
    pass


def version_parts(value):
    if not re.fullmatch(r"\d+(?:\.\d+){0,2}", value):
        raise ReleaseError("Unsupported version number: " + value)
    values = [int(v) for v in value.split(".")]
    return tuple(values + [0] * (3 - len(values)))


def plan_release(versions, source_changed, jobs):
    for name in REQUIRED_JOBS:
        matches = [j for j in jobs if j["name"] == name]
        if not matches or any(j.get("conclusion") != "success" for j in matches):
            raise ReleaseError("Required CI job is missing or unsuccessful: " + name)
    versions = [v for v in versions if v["attributes"]["platform"] == "TV_OS"]
    for v in versions:
        state = v["attributes"]["appStoreState"]
        if state in ACTIVE:
            return {"publish": False, "reason": "Apple review/release is active: " + state}
        if state in REJECTED:
            raise ReleaseError("Existing App Store version needs attention: " + state)
        if state not in RELEASED | {"PREPARE_FOR_SUBMISSION"}:
            raise ReleaseError("Unsupported Apple version state: " + state)
    drafts = [v for v in versions if v["attributes"]["appStoreState"] == "PREPARE_FOR_SUBMISSION"]
    if len(drafts) > 1:
        raise ReleaseError("Multiple editable tvOS drafts need attention")
    if drafts:
        draft = drafts[0]
        if draft.get("relationships", {}).get("build", {}).get("data"):
            raise ReleaseError("Editable draft already has a build; finish or resolve that release manually")
    if not source_changed:
        return {"publish": False, "reason": "No app-source changes since the last successful upload"}
    if drafts:
        number = draft["attributes"]["versionString"]
        version_parts(number)
    elif versions:
        major, minor, patch = max(version_parts(v["attributes"]["versionString"]) for v in versions)
        number = f"{major}.{minor}.{patch + 1}"
    else:
        number = "1.0"
    return {"publish": True, "version": number, "reason": "Tested app-source changes are ready"}


def run_json(args):
    return json.loads(subprocess.check_output(args, text=True))


def apple_token():
    encode = lambda v: base64.urlsafe_b64encode(v).rstrip(b"=")
    now = int(time.time())
    header = {"alg": "ES256", "kid": os.environ["ASC_KEY_ID"], "typ": "JWT"}
    payload = {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}
    message = b".".join(encode(json.dumps(x, separators=(",", ":")).encode()) for x in (header, payload))
    signature = subprocess.run(["openssl", "dgst", "-sha256", "-sign", os.environ["ASC_KEY_PATH"]],
                               input=message, capture_output=True, check=True).stdout
    index = 2 + (signature[1] & 127) if signature[1] & 128 else 2
    parts = []
    for _ in range(2):
        if signature[index] != 2:
            raise ReleaseError("Unexpected ES256 signature encoding")
        length = signature[index + 1]
        parts.append(int.from_bytes(signature[index + 2:index + 2 + length], "big").to_bytes(32, "big"))
        index += length + 2
    return (message + b"." + encode(b"".join(parts))).decode()


def apple_get(path, token):
    if not path.startswith("https://api.appstoreconnect.apple.com/"):
        path = "https://api.appstoreconnect.apple.com" + path
    req = urllib.request.Request(path, headers={"Authorization": "Bearer " + token})
    with urllib.request.urlopen(req, timeout=45) as response:
        return json.load(response)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    sha = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    repo = os.environ["GITHUB_REPOSITORY"]
    runs = run_json(["gh", "api", f"repos/{repo}/actions/workflows/ci.yml/runs?branch=main&event=push&head_sha={sha}&per_page=10"])["workflow_runs"]
    jobs = []
    for run in runs:
        if run["head_sha"] == sha and run["status"] == "completed":
            jobs = run_json(["gh", "api", f"repos/{repo}/actions/runs/{run['id']}/jobs?per_page=100"])["jobs"]
            break
    if not jobs:
        raise ReleaseError("No completed main CI run for the selected commit " + sha)
    tags = subprocess.check_output(["git", "for-each-ref", "--sort=-creatordate", "--format=%(refname)",
                                    "refs/tags/app-store-builds/"], text=True).splitlines()
    changed = not tags or subprocess.run(["git", "diff", "--quiet", tags[0], sha, "--", *SOURCE_PATHS]).returncode == 1
    token = apple_token()
    data = apple_get("/v1/apps/" + os.environ["ASC_APP_ID"] + "/appStoreVersions?limit=200&include=build", token)
    versions = data["data"]
    if data.get("links", {}).get("next"):
        raise ReleaseError("Version listing exceeded one page; inspect release history before publishing")
    result = {**plan_release(versions, changed, jobs), "sha": sha}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as out:
            for key, value in result.items():
                out.write(f"{key}={str(value).lower() if isinstance(value, bool) else value}\n")


if __name__ == "__main__":
    try:
        main()
    except (ReleaseError, KeyError, subprocess.CalledProcessError) as error:
        print("Release planning stopped: " + str(error), file=sys.stderr)
        sys.exit(1)
