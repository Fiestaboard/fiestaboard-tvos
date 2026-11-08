// Guards for the token bridge generator. Run: node --test scripts/tokens/tests/*.test.mjs
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { INPUTS, OUTPUT, generate, swiftName } from "../generate-swift.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../../..");
const cli = path.join(here, "..", "generate-swift.mjs");
const run = (args) => spawnSync(process.execPath, [cli, ...args], { encoding: "utf8", cwd: root });
const sha = (file) => createHash("sha256").update(readFileSync(path.join(root, file))).digest("hex");

test("the vendored tokens.json is the pinned FiestaUI alpha build", () => {
  assert.equal(sha(INPUTS.tokens.path), INPUTS.tokens.sha256);
  assert.equal(INPUTS.tokens.fiestauiCommit, "a84531f5ad3e88095ca001b03aa6d1afe54601f6");
  const tokens = JSON.parse(readFileSync(path.join(root, INPUTS.tokens.path), "utf8"));
  assert.equal(tokens.$extensions["app.fiestaboard"].package, "@fiestaboard/ui");
});

test("platform-tv.json is the pinned Figma export", () => {
  assert.equal(sha(INPUTS.platformTV.path), INPUTS.platformTV.sha256);
  const tv = JSON.parse(readFileSync(path.join(root, INPUTS.platformTV.path), "utf8"));
  assert.equal(tv.$extensions["app.fiestaboard"].collection, "VariableCollectionId:149:182577");
});

test("generation is deterministic and records both input hashes", () => {
  const a = generate(root);
  assert.equal(a, generate(root));
  assert.match(a, new RegExp(INPUTS.tokens.sha256));
  assert.match(a, new RegExp(INPUTS.platformTV.sha256));
  assert.doesNotMatch(a, /import SwiftUI/, "Core must stay free of SwiftUI (check-layering.sh)");
});

test("colours keep the token's hex and alpha", () => {
  const swift = generate(root);
  assert.match(swift, /static let background = TokenColor\(hex: "#0b0a08"/);
  assert.match(swift, /static let border = TokenColor\(hex: "#f5f3f1", red: [\d.]+, green: [\d.]+, blue: [\d.]+, alpha: 0\.14\)/);
  assert.match(swift, /static let textOnDark = TokenColor\(hex: "#f0f0e8"/);
  assert.match(swift, /"muted-foreground": mutedForeground/);
});

test("Platform · TV values are emitted for tvOS", () => {
  const swift = generate(root);
  for (const [name, value] of [["safeSide", 80], ["safeTopBottom", 60], ["cardRadius", 24], ["focusOutline", 6]]) {
    assert.match(swift, new RegExp(`static let ${name}: Double = ${value}\\b`));
  }
  assert.doesNotMatch(swift, /gtv/i, "Google TV values belong to the Android app");
});

test("kebab-case token names become Swift identifiers", () => {
  assert.equal(swiftName("muted-foreground"), "mutedForeground");
  assert.equal(swiftName("category-home-foreground"), "categoryHomeForeground");
  assert.equal(swiftName("base"), "base");
});

test("drift check: --check passes on the committed file", () => {
  const r = run(["--check"]);
  assert.equal(r.status, 0, r.stderr);
});

test("drift check: --check fails on an edited copy", () => {
  const dir = mkdtempSync(path.join(tmpdir(), "tokens-"));
  const copy = path.join(dir, "edited.swift");
  writeFileSync(copy, readFileSync(path.join(root, OUTPUT), "utf8").replace("#0b0a08", "#0c0c0e"));
  const r = run(["--check", "--out", copy]);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /out of date/);
});
