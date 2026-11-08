#!/usr/bin/env node
/**
 * Inset guard (PHASE-4-TV-PLAN A4a, the user-complete rule; S4).
 *
 *   node scripts/insets/check-insets.mjs [--root <repo>]
 *
 * Screens sit inside the system safe area, which is the 07b title-safe on
 * Apple TV (80 pt sides, 60 pt top and bottom; measured in A4a). Only the
 * full-bleed viewer applies those values itself, through `PlatformTV`. This
 * fails on anything that would bring back a hand-rolled or doubled inset:
 *   - any `Fiesta.Metrics.safeInset` (removed in A4a);
 *   - a `.padding(...)` with a literal 60 or 80 (use the safe area, or
 *     `PlatformTV.safeSide` / `safeTopBottom` in a full-bleed view);
 *   - an `.ignoresSafeArea()` that isn't on a background colour line and
 *     carries no `// full-bleed: <reason>` comment.
 *
 * Runs in Repository guards and in the Release archive job. Exit 1 with a
 * list of findings; 2 on bad input.
 */
import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const LITERAL_INSET = /\.padding\([^)]*?\b(60|80)(\.0)?\b/;
const BACKGROUND_LINE = /\b(Color\.\w+|Color\(|Fiesta\.Colors\.\w+)\s*\.ignoresSafeArea\(/;
const FULL_BLEED = /\/\/\s*full-bleed:\s*\S/;

/** Code part of a Swift line (drops // comments; keeps the comment for the full-bleed tag). */
function split(line) {
  const at = line.indexOf("//");
  return at < 0 ? { code: line, comment: "" } : { code: line.slice(0, at), comment: line.slice(at) };
}

/** @returns {{file: string, line: number, text: string, problem: string}[]} */
export function checkSwift(source, file) {
  const out = [];
  source.split("\n").forEach((raw, index) => {
    const { code, comment } = split(raw);
    if (!code.trim()) return;
    const finding = (problem) => out.push({ file, line: index + 1, text: raw.trim(), problem });
    if (code.includes("Fiesta.Metrics.safeInset")) finding("Fiesta.Metrics.safeInset was removed: the safe area is the inset");
    if (LITERAL_INSET.test(code)) finding("literal 60/80 padding: use the safe area, or PlatformTV in a full-bleed view");
    if (code.includes(".ignoresSafeArea(") && !BACKGROUND_LINE.test(code) && !FULL_BLEED.test(comment)) {
      finding("ignoresSafeArea on content: add `// full-bleed: <reason>` or keep it to a background colour");
    }
  });
  return out;
}

function swiftFiles(dir) {
  const out = [];
  for (const name of readdirSync(dir)) {
    const p = path.join(dir, name);
    if (statSync(p).isDirectory()) out.push(...swiftFiles(p));
    else if (name.endsWith(".swift")) out.push(p);
  }
  return out;
}

export function checkRepo(root) {
  const dir = path.join(root, "Sources", "UI");
  return swiftFiles(dir).flatMap((file) => checkSwift(readFileSync(file, "utf8"), path.relative(root, file)));
}

function main(argv) {
  let root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--root") root = path.resolve(argv[++i]);
    else throw new Error(`unknown argument: ${argv[i]}`);
  }
  const results = checkRepo(root);
  if (results.length) {
    for (const r of results) process.stderr.write(`${r.file}:${r.line}: ${r.problem}\n    ${r.text}\n`);
    return 1;
  }
  process.stdout.write("Insets: ok\n");
  return 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    process.exitCode = main(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`check-insets: ${error.message}\n`);
    process.exitCode = 2;
  }
}
