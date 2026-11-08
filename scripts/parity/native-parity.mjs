#!/usr/bin/env node
/**
 * Native (tvOS) Figma parity report — REPORT-ONLY (PHASE-4-TV-PLAN §2.1).
 *
 *   node scripts/parity/native-parity.mjs [--refs <local dir>] [--shots build/parity]
 *        [--manifest scripts/parity/figma-refs.json] [--out build/parity/report]
 *
 * Inputs:
 *   --refs      a local refs directory (refs.json + PNGs): a checkout of
 *               fiestaboard-design-refs once O4 exists, or a local stand-in.
 *               Never a URL. Optional: without it the report lists the shots
 *               and probes it found and says no refs were given.
 *   --shots     where the tests wrote `<ref>.png` (3840×2160, scale 2) and
 *               `<ref>.probes.json` (FigmaGeometryRegistry frames, points,
 *               relative to the Screen slot; see Tests/Support/ParityProbe.swift).
 *   --manifest  per ref id: kind, and which Figma ids to probe for geometry/text.
 *
 * The checks are FiestaUI's, vendored verbatim in ./parity.mjs and pinned
 * below; this file only adapts native inputs to them:
 *   - the shot is box-downscaled to the ref's scale (a 1x MCP ref gets a 1x
 *     shot; a REST @2x ref is compared as is);
 *   - probes are joined to ref nodes by Figma id, not by DOM selector.
 *
 * Findings never change the exit code. Exit 2 only for bad input.
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { PNG } from "pngjs";

import { evaluateEntry, loadRefs, renderMarkdown, resolveRefsDir } from "./parity.mjs";

/** FiestaUI scripts/vrt/parity.mjs, PR #378 head. Bump deliberately; the test checks the hash. */
export const PINNED = {
  repo: "Fiestaboard/FiestaUI",
  path: "scripts/vrt/parity.mjs",
  commit: "5a451b7470dfc5e56b27740acd1d065b06bc5c2b",
  sha256: "94cd0bb7f918ccdf92d7cbea3ed8868e5c42ef75b16a7d23b12e09479e12dc22",
};

/** @param {string} file */
export function loadNativeManifest(file) {
  const raw = JSON.parse(readFileSync(file, "utf8"));
  if (!Array.isArray(raw.entries)) throw new Error(`${file}: expected { entries: [...] }`);
  for (const entry of raw.entries) {
    if (!entry.id) throw new Error(`${file}: an entry has no "id"`);
    entry.probes = { geometry: [], text: [], ...(entry.probes ?? {}) };
  }
  return raw;
}

/**
 * Box-filter `png` down by an integer factor (2 → a scale-2 shot onto a 1x ref).
 * @param {PNG} png
 * @param {number} factor
 */
export function downscale(png, factor) {
  if (factor === 1) return png;
  if (!Number.isInteger(factor) || factor < 1) throw new Error(`downscale factor must be a positive integer, got ${factor}`);
  const width = Math.floor(png.width / factor);
  const height = Math.floor(png.height / factor);
  const out = new PNG({ width, height });
  const n = factor * factor;
  for (let y = 0; y < height; y++)
    for (let x = 0; x < width; x++) {
      const sum = [0, 0, 0, 0];
      for (let dy = 0; dy < factor; dy++)
        for (let dx = 0; dx < factor; dx++) {
          const o = ((y * factor + dy) * png.width + (x * factor + dx)) * 4;
          for (let c = 0; c < 4; c++) sum[c] += png.data[o + c];
        }
      const o = (y * width + x) * 4;
      for (let c = 0; c < 4; c++) out.data[o + c] = Math.round(sum[c] / n);
    }
  return out;
}

/**
 * The `dom` argument of evaluateEntry, from native probes. A probed id that
 * the shot never registered is reported with a null rect / text.
 */
export function buildDom(ref, entry, probes) {
  const byFigma = new Map((probes?.nodes ?? []).map((n) => [n.figma, n]));
  const nameOf = (id) => ref.nodes.find((n) => n.id === id)?.name ?? id;
  return {
    geometry: entry.probes.geometry.map((id) => ({ node: nameOf(id), rect: byFigma.get(id)?.rect ?? null })),
    text: entry.probes.text.map((id) => ({ node: nameOf(id), text: byFigma.get(id)?.text ?? null })),
    tokens: [],
    board: null,
  };
}

function parseArgs(argv) {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const args = {
    refs: null,
    shots: "build/parity",
    manifest: path.join(here, "figma-refs.json"),
    out: "build/parity/report",
  };
  for (let i = 0; i < argv.length; i++) {
    const flag = argv[i];
    const key = flag.replace(/^--/, "");
    if (!flag.startsWith("--") || !(key in args)) throw new Error(`unknown argument: ${flag}`);
    const value = argv[++i];
    if (value === undefined) throw new Error(`${flag} needs a value`);
    args[key] = value;
  }
  return args;
}

function main(argv) {
  const args = parseArgs(argv);
  const refsDir = args.refs ? resolveRefsDir(args.refs) : null;
  const manifest = loadNativeManifest(args.manifest);
  mkdirSync(args.out, { recursive: true });

  const report = {
    gating: false,
    pinned: PINNED,
    refsDir: refsDir ?? "(none)",
    refsTag: null,
    manifest: args.manifest,
    missingRefs: [],
    unmanifested: [],
    entries: [],
  };

  if (!refsDir) {
    const lines = [
      "# Figma parity report (tvOS)",
      "",
      "**Report-only.** No refs: `--refs` was not given (fiestaboard-design-refs, O4, does not exist yet).",
      "Shots and probes found, for a local run with `--refs <dir>`:",
      "",
    ];
    for (const entry of manifest.entries) {
      const shot = path.join(args.shots, `${entry.id}.png`);
      const probes = path.join(args.shots, `${entry.id}.probes.json`);
      lines.push(`- \`${entry.id}\`: shot ${existsSync(shot) ? "yes" : "no"}, probes ${existsSync(probes) ? "yes" : "no"}`);
      report.entries.push({ id: entry.id, error: "no refs" });
    }
    writeFileSync(path.join(args.out, "report.json"), JSON.stringify(report, null, 2));
    writeFileSync(path.join(args.out, "report.md"), `${lines.join("\n")}\n`);
    process.stdout.write(`${lines.join("\n")}\n`);
    return 0;
  }

  const refs = loadRefs(refsDir);
  const refIds = new Set(refs.map((r) => r.id));
  report.missingRefs = manifest.entries.filter((e) => !refIds.has(e.id)).map((e) => e.id);
  report.unmanifested = refs.filter((r) => !manifest.entries.some((e) => e.id === r.id)).map((r) => r.id);

  for (const entry of manifest.entries) {
    const ref = refs.find((r) => r.id === entry.id);
    if (!ref) continue;
    const shotPath = path.join(args.shots, `${entry.id}.png`);
    const probesPath = path.join(args.shots, `${entry.id}.probes.json`);
    if (!existsSync(shotPath)) {
      report.entries.push({ id: entry.id, figmaNode: ref.figmaNode, error: `no shot at ${shotPath}` });
      continue;
    }
    const probes = existsSync(probesPath) ? JSON.parse(readFileSync(probesPath, "utf8")) : null;
    const shotScale = probes?.scale ?? 2;
    const factor = shotScale / ref.scale;
    const shotPng = downscale(PNG.sync.read(readFileSync(shotPath)), factor);
    writeFileSync(path.join(args.out, `${entry.id}.png`), PNG.sync.write(shotPng));
    const refPng = PNG.sync.read(readFileSync(ref.pngPath));
    writeFileSync(path.join(args.out, `${entry.id}.ref.png`), PNG.sync.write(refPng));
    const result = evaluateEntry({ ref, entry, refPng, shotPng, dom: buildDom(ref, entry, probes) });
    writeFileSync(path.join(args.out, `${entry.id}.diff.png`), PNG.sync.write(result.diffPng));
    delete result.diffPng;
    result.shotScale = shotScale;
    result.comparedAtScale = ref.scale;
    report.entries.push(result);
  }

  const md = renderMarkdown(report).replace(
    /\*\*Report-only \(slice 1\.0b\)\.\*\*[^\n]*/,
    "**Report-only (tvOS A0).** Nothing here fails CI; gating waits for K2n calibration (PHASE-4-TV-PLAN §2.1).",
  );
  writeFileSync(path.join(args.out, "report.json"), JSON.stringify(report, null, 2));
  writeFileSync(path.join(args.out, "report.md"), md);
  process.stdout.write(md);
  return 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    process.exitCode = main(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`native-parity: ${error.message}\n`);
    process.exitCode = 2;
  }
}
