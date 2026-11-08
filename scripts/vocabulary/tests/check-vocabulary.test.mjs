// Guards for the hub-vocabulary check (PHASE-4-TV-PLAN §2.0 user-complete rule, A2).
// Run: node --test scripts/vocabulary/tests/*.test.mjs
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { ALLOW, checkProjectYml, checkSwift, swiftLiterals } from "../check-vocabulary.mjs";

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
