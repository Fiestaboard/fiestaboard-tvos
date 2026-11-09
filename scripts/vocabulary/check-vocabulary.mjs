#!/usr/bin/env node
/**
 * Hub vocabulary guard (PHASE-4-TV-PLAN §2.0, the user-complete rule; A2).
 *
 *   node scripts/vocabulary/check-vocabulary.mjs [--root <repo>]
 *
 * The thing the TV connects to is a **hub**. "Board" means only what is on
 * screen: the split-flap picture, a panel's virtual board, its position or
 * brightness. This scans every Swift string literal under Sources/ that
 * reads as copy (it contains whitespace) and project.yml's user-facing
 * strings, and fails on:
 *   - the word "board"/"boards" unless an allow-listed display-sense phrase
 *     covers it;
 *   - "your / this / the FiestaBoard" not followed by "hub" or "app", which
 *     also names the hub (TV-APPS §4 item 1).
 *
 * Runs in Repository guards and in the Release archive job. Exit 1 with a
 * list of findings; 2 on bad input.
 */
import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

/**
 * Display-sense phrases. Every "board" in a literal must sit inside one of
 * these (case-insensitive). Add a phrase only when "board" means the
 * picture on screen, never the hub.
 */
export const ALLOW = [
  "virtual board",
  "board's position",
  "board brightness",
  "how bright should the board be",
  "around the board",
  "same live board",
  "board layout",
  "board content",
  "board grid",
  "board is paused",
  "board shortcut",
  "board was removed",
  "board removed",
  "board unavailable",
  "board reads",
  "unavailable boards",
  "missing/deleted boards",
  "another board render",
  "board is showing",
  // 07b A8b `248:110205` subtitle: the picture on screen.
  "keeps the board bright",
];

const BOARD = /\bboards?\b/gi;
const HUB_FIESTABOARD = /\b(your|this|the|a)\s+FiestaBoard\b(?!\s+(hub|app|server|account|icon|for\b))/gi;

/** Swift string literals with their 1-based start line. Skips // comments. */
export function swiftLiterals(source) {
  const out = [];
  let i = 0;
  let line = 1;
  const n = source.length;
  while (i < n) {
    const ch = source[i];
    if (ch === "\n") {
      line++;
      i++;
      continue;
    }
    if (ch === "/" && source[i + 1] === "/") {
      while (i < n && source[i] !== "\n") i++;
      continue;
    }
    if (ch === "/" && source[i + 1] === "*") {
      i += 2;
      while (i < n && !(source[i] === "*" && source[i + 1] === "/")) {
        if (source[i] === "\n") line++;
        i++;
      }
      i += 2;
      continue;
    }
    if (source.startsWith('"""', i)) {
      const start = line;
      let j = source.indexOf("\n", i) + 1;
      line++;
      const end = source.indexOf('"""', j);
      if (j <= 0 || end < 0) break;
      const text = source.slice(j, end);
      for (const c of text) if (c === "\n") line++;
      out.push({ text, line: start });
      i = end + 3;
      continue;
    }
    if (ch === '"') {
      let j = i + 1;
      while (j < n && source[j] !== '"' && source[j] !== "\n") {
        if (source[j] === "\\") j++;
        j++;
      }
      out.push({ text: source.slice(i + 1, j), line });
      i = j + 1;
      continue;
    }
    i++;
  }
  return out;
}

function findings(raw) {
  const problems = [];
  // Interpolated code (`\(board.name)`) is not copy.
  const text = raw.replace(/\\\((?:[^()]|\([^()]*\))*\)/g, "{}");
  if (!/\s/.test(text)) return problems; // identifiers, keys, URLs
  const lower = text.toLowerCase();
  const covered = [];
  for (const phrase of ALLOW) {
    let at = lower.indexOf(phrase);
    while (at >= 0) {
      covered.push([at, at + phrase.length]);
      at = lower.indexOf(phrase, at + 1);
    }
  }
  for (const m of text.matchAll(BOARD)) {
    const inside = covered.some(([a, b]) => m.index >= a && m.index < b);
    if (!inside) problems.push(`hub-sense "${m[0]}"`);
  }
  for (const m of text.matchAll(HUB_FIESTABOARD)) problems.push(`"${m[0]}" names the hub: say "FiestaBoard hub"`);
  return problems;
}

/** @returns {{file: string, line: number, text: string, problems: string[]}[]} */
export function checkSwift(source, file) {
  const out = [];
  for (const literal of swiftLiterals(source)) {
    const problems = findings(literal.text);
    if (problems.length) out.push({ file, line: literal.line, text: literal.text, problems });
  }
  return out;
}

/** project.yml: values of the user-facing Info.plist strings (NS…Description, CFBundleDisplayName). */
export function checkProjectYml(source, file = "project.yml") {
  const out = [];
  source.split("\n").forEach((raw, index) => {
    const m = raw.match(/^\s*(NS\w+Description|CFBundleDisplayName)\s*:\s*(.+)$/);
    if (!m) return;
    const problems = findings(m[2]);
    if (problems.length) out.push({ file, line: index + 1, text: m[2], problems });
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
  const results = [];
  for (const dir of ["Sources", "TopShelf"]) {
    const abs = path.join(root, dir);
    try {
      statSync(abs);
    } catch {
      continue;
    }
    for (const file of swiftFiles(abs)) {
      results.push(...checkSwift(readFileSync(file, "utf8"), path.relative(root, file)));
    }
  }
  results.push(...checkProjectYml(readFileSync(path.join(root, "project.yml"), "utf8")));
  return results;
}

function main(argv) {
  let root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--root") root = path.resolve(argv[++i]);
    else throw new Error(`unknown argument: ${argv[i]}`);
  }
  const results = checkRepo(root);
  if (results.length) {
    for (const r of results) {
      process.stderr.write(`${r.file}:${r.line}: "${r.text.trim().slice(0, 140)}" — ${r.problems.join("; ")}\n`);
    }
    process.stderr.write(`\n${results.length} string(s) use "board" for the hub. Say "hub"; if "board" means the picture on screen, add the phrase to ALLOW.\n`);
    return 1;
  }
  process.stdout.write("Hub vocabulary: ok\n");
  return 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    process.exitCode = main(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`check-vocabulary: ${error.message}\n`);
    process.exitCode = 2;
  }
}
