// Guards for the hub-vocabulary check (PHASE-4-TV-PLAN §2.0 user-complete rule, A2).
// Run: node --test scripts/vocabulary/tests/*.test.mjs
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { ALLOW, APP_COPY_ALLOW, checkFastfile, checkListing, checkProjectYml, checkSwift, swiftLiterals } from "../check-vocabulary.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../../..");
const cli = path.join(here, "..", "check-vocabulary.mjs");
const run = (args) => spawnSync(process.execPath, [cli, ...args], { encoding: "utf8" });

test("string literals are extracted, comments are not", () => {
  const src = [
    '// "Forget this board" in a comment is fine',
    'let a = "Forget this hub" // "your board" trailing comment',
    'let b = """',
    "    Multi-line about the hub \\",
    "    and more.",
    '    """',
    'let c = "escaped \\"quote\\" board"',
  ].join("\n");
  const literals = swiftLiterals(src).map((l) => l.text);
  assert.deepEqual(literals, ["Forget this hub", "    Multi-line about the hub \\\n    and more.\n    ", 'escaped \\"quote\\" board']);
});

test("hub-sense board is flagged", () => {
  for (const s of [
    "Forget this board",
    "Open your board's web page in a browser",
    "Use another board",
    "Connected board",
    "The board asked this TV to wait.",
    "Requests go to your board and its AI provider.",
  ]) {
    assert.equal(checkSwift(`let x = "${s}"`, "X.swift").length, 1, s);
  }
});

test("'your FiestaBoard' means the hub and needs the word hub", () => {
  assert.equal(checkSwift('let x = "Couldn\'t reach your FiestaBoard. Check it."', "X.swift").length, 1);
  assert.equal(checkSwift('let x = "This FiestaBoard has no account yet."', "X.swift").length, 1);
  assert.equal(checkSwift('let x = "Couldn\'t reach your FiestaBoard hub."', "X.swift").length, 0);
  assert.equal(checkSwift('let x = "Find your FiestaBoard hub"', "X.swift").length, 0);
  assert.equal(checkSwift('let x = "Open the FiestaBoard app on your phone."', "X.swift").length, 0);
});

test("display-sense board passes through the allow-list", () => {
  assert.ok(ALLOW.length > 0);
  for (const s of [
    "The virtual board behind this panel was deleted.",
    "Rotate the board's position?",
    "Night level multiplies board brightness.",
    "Current board content",
    "Shifts the board a few pixels over 20 min",
  ]) {
    assert.deepEqual(checkSwift(`let x = "${s}"`, "X.swift"), [], s);
  }
});

test("identifiers and keys without spaces are not copy", () => {
  assert.deepEqual(checkSwift('let x = ["target": "board", "board_id": id]', "X.swift"), []);
  assert.deepEqual(checkSwift('let host = "http://board.local"', "X.swift"), []);
});

test("project.yml's user-facing strings are checked too", () => {
  const bad = "        NSLocalNetworkUsageDescription: FiestaBoard connects to the board you choose.\n";
  const good = "        NSLocalNetworkUsageDescription: FiestaBoard connects to the hub you choose.\n";
  assert.equal(checkProjectYml(bad).length, 1);
  assert.deepEqual(checkProjectYml(good), []);
  assert.deepEqual(checkProjectYml("# the board you choose, in a comment\n"), []);
});

test("CLI: exits 1 with findings on a seeded tree, 0 on a clean one", () => {
  const dir = mkdtempSync(path.join(tmpdir(), "vocab-"));
  mkdirSync(path.join(dir, "Sources", "UI"), { recursive: true });
  writeFileSync(path.join(dir, "project.yml"), "name: X\n");
  writeFileSync(path.join(dir, "Sources", "UI", "A.swift"), 'let a = "Forget this hub"\n');
  assert.equal(run(["--root", dir]).status, 0);
  writeFileSync(path.join(dir, "Sources", "UI", "B.swift"), 'let b = "Forget this board"\n');
  const r = run(["--root", dir]);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /B\.swift:1: "Forget this board"/);
});

test("this repository uses hub vocabulary everywhere (the user-complete rule)", () => {
  const r = run(["--root", root]);
  assert.equal(r.status, 0, r.stderr);
});

test("interpolated identifiers and product nouns are not hub-sense copy", () => {
  assert.deepEqual(checkSwift('let x = "\\(board.name), \\(address)"', "X.swift"), []);
  assert.deepEqual(checkSwift('let x = "Your FiestaBoard account"', "X.swift"), []);
  assert.deepEqual(checkSwift('let x = "Hold Select on the FiestaBoard icon"', "X.swift"), []);
  assert.equal(checkSwift('let x = "\\(name) on this board"', "X.swift").length, 1);
});

// A12: the App Store listing (fastlane/metadata) and the release notes in the
// Fastfile are copy too. CANON: "hub" (never "server" or hub-sense "board"),
// "silence" (never "quiet hours"), US spelling.
test("listing: the hub is never a server or a board", () => {
  for (const s of [
    "Connects to your own FiestaBoard server.",
    "See updates from your board.",
    "Manage TV access from your board.",
  ]) {
    assert.equal(checkListing(s, "description.txt").length, 1, s);
  }
});

test("listing: CANON terms and US spelling", () => {
  for (const s of [
    "Schedules, overrides and quiet hours at a glance.",
    "Quiet mode for the night.",
    "Pick a colour for your favourite panel.",
    "Centre the board layout.",
    "Its behaviour follows the hub.",
    "Licence notices are in Settings.",
  ]) {
    assert.ok(checkListing(s, "description.txt").length >= 1, s);
  }
  assert.deepEqual(checkListing("Schedules, overrides and silence, in your favorite colors.", "description.txt"), []);
  assert.deepEqual(checkListing("Your FiestaBoard hub runs on your own network.", "description.txt"), []);
});

test("listing: URLs and empty lines are not copy", () => {
  assert.deepEqual(checkListing("https://github.com/Fiestaboard/fiestaboard-tvos/blob/main/docs/PRIVACY.md\n\n", "privacy_url.txt"), []);
});

test("Fastfile: the release-notes string is checked", () => {
  assert.equal(checkFastfile('options[:release_notes] = { "en-US" => "Fixes for your FiestaBoard server." }\n').length, 1);
  assert.deepEqual(checkFastfile('options[:release_notes] = { "en-US" => "Fixes for your FiestaPanel displays." }\n'), []);
});

test("CLI: a seeded listing fails the repo check", () => {
  const dir = mkdtempSync(path.join(tmpdir(), "vocab-listing-"));
  mkdirSync(path.join(dir, "fastlane", "metadata", "en-US"), { recursive: true });
  writeFileSync(path.join(dir, "project.yml"), "name: X\n");
  writeFileSync(path.join(dir, "fastlane", "metadata", "en-US", "description.txt"), "Runs on your FiestaBoard hub.\n");
  assert.equal(run(["--root", dir]).status, 0, run(["--root", dir]).stderr);
  writeFileSync(path.join(dir, "fastlane", "metadata", "en-US", "subtitle.txt"), "Quiet hours on your TV\n");
  const r = run(["--root", dir]);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /subtitle\.txt:1/);
});

test("listing: the description names the FiestaBoard hub", () => {
  const description = readFileSync(path.join(root, "fastlane", "metadata", "en-US", "description.txt"), "utf8");
  assert.match(description, /FiestaBoard hub/);
});

// TV wrap-up M-T1: the listing bans (server, quiet) and US spelling also
// apply to the app's own copy under Sources/ and TopShelf/. The legacy
// sign-in footer once read "this server’s legacy sign-in" and the guard
// missed it because these rules only ran over the listing.
test("app copy: the hub is never a server, quiet is not a mode, US spelling", () => {
  for (const s of [
    "Your username and password are stored in this Apple TV’s Keychain for this server’s legacy sign-in.",
    "Couldn't reach the server.",
    "Quiet hours are on.",
    "Pick a colour.",
    "Centred on the screen.",
  ]) {
    assert.ok(checkSwift(`let x = "${s}"`, "X.swift").length >= 1, s);
  }
  assert.deepEqual(
    checkSwift('let x = "Your username and password are stored in this Apple TV’s Keychain for this hub’s legacy sign-in."', "X.swift"),
    [],
  );
});

test("app copy: the allow-list covers servers that are not the hub", () => {
  assert.ok(APP_COPY_ALLOW.length > 0);
  // Privacy: FiestaBoard (the project) runs no servers that see this app.
  assert.deepEqual(
    checkSwift('let x = "FiestaBoard’s servers and the app developer receive no analytics or tracking from this app."', "X.swift"),
    [],
  );
  assert.ok(checkSwift('let x = "Your servers and the app developer receive nothing."', "X.swift").length >= 1);
});

test("CLI: a seeded TopShelf literal with 'server' fails the repo check", () => {
  const dir = mkdtempSync(path.join(tmpdir(), "vocab-topshelf-"));
  mkdirSync(path.join(dir, "TopShelf"), { recursive: true });
  writeFileSync(path.join(dir, "project.yml"), "name: X\n");
  writeFileSync(path.join(dir, "TopShelf", "A.swift"), 'let a = "Now showing on your hub"\n');
  assert.equal(run(["--root", dir]).status, 0, run(["--root", dir]).stderr);
  writeFileSync(path.join(dir, "TopShelf", "B.swift"), 'let b = "Now showing on your server"\n');
  const r = run(["--root", dir]);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /TopShelf\/B\.swift:1/);
});
