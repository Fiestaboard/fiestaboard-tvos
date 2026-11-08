// Guards for the native (tvOS) parity CLI. Run: npm test --prefix scripts/parity
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { PNG } from "pngjs";

import { PINNED, buildDom, downscale, loadNativeManifest } from "../native-parity.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const cli = path.join(here, "..", "native-parity.mjs");

function png(width, height, fill) {
  const p = new PNG({ width, height });
  for (let y = 0; y < height; y++)
    for (let x = 0; x < width; x++) {
      const [r, g, b] = fill(x, y);
      const o = (y * width + x) * 4;
      p.data[o] = r;
      p.data[o + 1] = g;
      p.data[o + 2] = b;
      p.data[o + 3] = 255;
    }
  return p;
}

/** A 1x 8×4 ref and a 2x 16×8 shot of the same left-red/right-blue picture. */
function fixture({ shotFill } = {}) {
  const dir = mkdtempSync(path.join(tmpdir(), "native-parity-"));
  const refs = path.join(dir, "refs");
  const shots = path.join(dir, "shots");
  mkdirSync(path.join(refs, "refs"), { recursive: true });
  mkdirSync(shots, { recursive: true });
  const split = (w) => (x) => (x < w / 2 ? [255, 0, 0] : [0, 0, 255]);
  writeFileSync(path.join(refs, "refs", "screen@1x.png"), PNG.sync.write(png(8, 4, split(8))));
  writeFileSync(
    path.join(refs, "refs.json"),
    JSON.stringify({
      refs: [
        {
          id: "screen",
          figmaNode: "1:1",
          mode: "dark",
          slotWidth: 8,
          slotHeight: 4,
          scale: 1,
          file: "refs/screen@1x.png",
          nodes: [
            { id: "1:2", name: "Button", type: "INSTANCE", x: 1, y: 1, width: 3, height: 2, characters: "Connect" },
            { id: "1:3", name: "Title", type: "TEXT", x: 0, y: 0, width: 8, height: 1, characters: "Hello" },
          ],
        },
      ],
    }),
  );
  writeFileSync(path.join(shots, "screen.png"), PNG.sync.write(png(16, 8, shotFill ?? split(16))));
  writeFileSync(
    path.join(shots, "screen.probes.json"),
    JSON.stringify({
      schema: 1,
      ref: "screen",
      root: "1:1",
      scale: 2,
      nodes: [
        { figma: "1:1", rect: { x: 0, y: 0, width: 8, height: 4 } },
        { figma: "1:2", text: "Connect", rect: { x: 1, y: 1.5, width: 3, height: 2 } },
      ],
    }),
  );
  const manifest = path.join(dir, "manifest.json");
  writeFileSync(
    manifest,
    JSON.stringify({ entries: [{ id: "screen", kind: "screen", probes: { geometry: ["1:2", "1:3"], text: ["1:2"] } }] }),
  );
  return { dir, refs, shots, manifest, out: path.join(dir, "out") };
}

const run = (args) => spawnSync(process.execPath, [cli, ...args], { encoding: "utf8" });

test("parity.mjs is the pinned FiestaUI file, unmodified", () => {
  const sha = createHash("sha256").update(readFileSync(path.join(here, "..", "parity.mjs"))).digest("hex");
  assert.equal(sha, PINNED.sha256);
  assert.match(PINNED.commit, /^[0-9a-f]{40}$/);
});

test("the pin is FiestaUI alpha after #378 merged, not the PR head", () => {
  assert.equal(PINNED.ref, "alpha");
  assert.equal(PINNED.commit, "a84531f5ad3e88095ca001b03aa6d1afe54601f6");
});

test("CLI: the report names the simulator runtime the shots came from", () => {
  const f = fixture();
  writeFileSync(
    path.join(f.shots, "runtime.json"),
    JSON.stringify({ osVersion: "26.2", runtimeBuild: "23K53", deviceModel: "Apple TV 4K (3rd generation)", goldenDirectory: "tvOS26", scale: 2 }),
  );
  const r = run(["--refs", f.refs, "--shots", f.shots, "--manifest", f.manifest, "--out", f.out]);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(JSON.parse(readFileSync(path.join(f.out, "report.json"), "utf8")).runtime.osVersion, "26.2");
  assert.match(readFileSync(path.join(f.out, "report.md"), "utf8"), /tvOS 26\.2 \(23K53\).*Apple TV 4K/);
  const bare = run(["--shots", f.shots, "--manifest", f.manifest, "--out", f.out]);
  assert.match(readFileSync(path.join(f.out, "report.md"), "utf8"), /tvOS 26\.2/);
  assert.equal(bare.status, 0);
});

test("downscale box-filters a 2x shot onto a 1x ref grid", () => {
  const src = png(4, 2, (x) => (x % 2 === 0 ? [200, 0, 0] : [0, 0, 100]));
  const out = downscale(src, 2);
  assert.equal(out.width, 2);
  assert.equal(out.height, 1);
  assert.deepEqual([...out.data.subarray(0, 4)], [100, 0, 50, 255]);
  assert.equal(downscale(src, 1), src, "factor 1 is the identity");
  assert.throws(() => downscale(src, 1.5), /integer/);
});

test("buildDom maps Figma ids to ref node names and reports unprobed nodes", () => {
  const ref = { nodes: [{ id: "a", name: "Alpha" }, { id: "b", name: "Beta" }] };
  const probes = { nodes: [{ figma: "a", text: "Hi", rect: { x: 1, y: 2, width: 3, height: 4 } }] };
  const dom = buildDom(ref, { probes: { geometry: ["a", "b", "zz"], text: ["a", "b"] } }, probes);
  assert.deepEqual(dom.geometry, [
    { node: "Alpha", rect: { x: 1, y: 2, width: 3, height: 4 } },
    { node: "Beta", rect: null },
    { node: "zz", rect: null },
  ]);
  assert.deepEqual(dom.text, [
    { node: "Alpha", text: "Hi" },
    { node: "Beta", text: null },
  ]);
});

test("the native manifest needs ids", () => {
  const { dir } = fixture();
  const bad = path.join(dir, "bad.json");
  writeFileSync(bad, JSON.stringify({ entries: [{ kind: "screen" }] }));
  assert.throws(() => loadNativeManifest(bad), /no "id"/);
});

test("CLI: compares a 2x shot to a 1x ref and writes a report, exit 0", () => {
  const f = fixture();
  const r = run(["--refs", f.refs, "--shots", f.shots, "--manifest", f.manifest, "--out", f.out]);
  assert.equal(r.status, 0, r.stderr);
  const report = JSON.parse(readFileSync(path.join(f.out, "report.json"), "utf8"));
  assert.equal(report.gating, false);
  const [entry] = report.entries;
  assert.equal(entry.id, "screen");
  assert.equal(entry.checks.pixel.sizeMatch, true);
  assert.equal(entry.checks.pixel.diffPixels, 0);
  assert.equal(entry.checks.geometry.items.find((i) => i.node === "Button").pass, true);
  assert.equal(entry.checks.geometry.items.find((i) => i.node === "Title").pass, false);
  assert.equal(entry.checks.text.items[0].pass, true);
  assert.equal(entry.wouldPass, false);
  assert.ok(existsSync(path.join(f.out, "screen.diff.png")));
  assert.match(readFileSync(path.join(f.out, "report.md"), "utf8"), /Report-only/);
});

test("CLI: findings never change the exit code", () => {
  const f = fixture({ shotFill: () => [0, 255, 0] });
  const r = run(["--refs", f.refs, "--shots", f.shots, "--manifest", f.manifest, "--out", f.out]);
  assert.equal(r.status, 0, r.stderr);
  const report = JSON.parse(readFileSync(path.join(f.out, "report.json"), "utf8"));
  assert.equal(report.entries[0].checks.pixel.pass, false);
});

test("CLI: a missing shot is a finding, not a crash", () => {
  const f = fixture();
  const r = run(["--refs", f.refs, "--shots", path.join(f.dir, "nowhere"), "--manifest", f.manifest, "--out", f.out]);
  assert.equal(r.status, 0, r.stderr);
  const report = JSON.parse(readFileSync(path.join(f.out, "report.json"), "utf8"));
  assert.match(report.entries[0].error, /no shot/);
});

test("CLI: without --refs it reports the shots it has and exits 0 (O4 not yet available)", () => {
  const f = fixture();
  const r = run(["--shots", f.shots, "--manifest", f.manifest, "--out", f.out]);
  assert.equal(r.status, 0, r.stderr);
  const md = readFileSync(path.join(f.out, "report.md"), "utf8");
  assert.match(md, /No refs/);
  assert.match(md, /screen/);
});

test("CLI: --refs must be local; unknown flags and --gate are rejected (exit 2)", () => {
  const f = fixture();
  assert.equal(run(["--refs", "https://example.com/refs", "--out", f.out]).status, 2);
  assert.equal(run(["--refs", f.refs, "--gate"]).status, 2);
});

test("the repo manifest lists the A1 Connect ref with probes", () => {
  const manifest = loadNativeManifest(path.join(here, "..", "figma-refs.json"));
  const a1 = manifest.entries.find((e) => e.id === "a1-connect");
  assert.ok(a1, "a1-connect entry");
  assert.equal(a1.kind, "screen");
  assert.ok(a1.probes.geometry.includes("I166:147296;149:182603;166:147351"));
});

