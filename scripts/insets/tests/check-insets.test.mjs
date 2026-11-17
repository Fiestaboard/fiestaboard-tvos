// Guards for the inset check (PHASE-4-TV-PLAN A4a, the user-complete rule).
// Run: node --test scripts/insets/tests/*.test.mjs
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { checkSwift } from "../check-insets.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../../..");
const cli = path.join(here, "..", "check-insets.mjs");
const run = (args) => spawnSync(process.execPath, [cli, ...args], { encoding: "utf8" });

test("the removed hand-rolled inset is flagged", () => {
  assert.equal(checkSwift(".padding(Fiesta.Metrics.safeInset)", "A.swift").length, 1);
});

test("literal 60/80 paddings that bypass PlatformTV are flagged", () => {
  for (const line of [".padding(60)", ".padding(.horizontal, 80)", ".padding(.top, 60)", ".padding(EdgeInsets(top: 60, leading: 80, bottom: 60, trailing: 80))"]) {
    assert.equal(checkSwift(line, "A.swift").length, 1, line);
  }
  assert.deepEqual(checkSwift(".padding(.horizontal, 32)", "A.swift"), []);
  assert.deepEqual(checkSwift(".padding(.top, PlatformTV.safeTopBottom)", "A.swift"), []);
  assert.deepEqual(checkSwift(".frame(width: 600, height: 80)", "A.swift"), [], "a frame isn't an inset");
});

test("ignoresSafeArea is allowed on backgrounds and commented full-bleed views only", () => {
  assert.deepEqual(checkSwift("Fiesta.Colors.background.ignoresSafeArea()", "A.swift"), []);
  assert.deepEqual(checkSwift("Color.black.ignoresSafeArea()", "A.swift"), []);
  assert.deepEqual(checkSwift(".ignoresSafeArea() // full-bleed: the board fills the TV", "A.swift"), []);
  assert.equal(checkSwift("content.ignoresSafeArea()", "A.swift").length, 1);
  assert.equal(checkSwift(".ignoresSafeArea() // because", "A.swift").length, 1);
});

test("comments are not code", () => {
  assert.deepEqual(checkSwift("// .padding(60) used to be here", "A.swift"), []);
  assert.deepEqual(checkSwift("/// `.padding(Fiesta.Metrics.safeInset)` is gone", "A.swift"), []);
});

test("CLI: exits 1 on a seeded tree, 0 on a clean one", () => {
  const dir = mkdtempSync(path.join(tmpdir(), "insets-"));
  mkdirSync(path.join(dir, "Sources", "UI"), { recursive: true });
  writeFileSync(path.join(dir, "Sources", "UI", "A.swift"), "Text(x).padding(.horizontal, 32)\n");
  assert.equal(run(["--root", dir]).status, 0);
  writeFileSync(path.join(dir, "Sources", "UI", "B.swift"), "Text(x).padding(60)\n");
  const r = run(["--root", dir]);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /B\.swift:1/);
});

test("this repository's screens use the safe area or PlatformTV", () => {
  const r = run(["--root", root]);
  assert.equal(r.status, 0, r.stderr);
});
