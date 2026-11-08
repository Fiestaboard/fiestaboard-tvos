/**
 * Figma parity checks (MASTER-PLAN §3.3). Pure functions over PNGs and plain
 * data; the browser half (capturing the shot and measuring the DOM) lives in
 * vrt.mjs's `parity` mode, which calls `evaluateEntry` per ref.
 *
 * Inputs, per the manifest split (C3):
 *   - a refs directory (a checkout of fiestaboard-design-refs at a pinned tag,
 *     or any local stand-in) holding refs.json + the ref PNGs. Each ref
 *     carries its Figma metadata: node, mode, slot size, scale, the named
 *     child nodes (get_metadata) and bound variables (get_variable_defs);
 *   - vrt/figma-refs.json in this repo: per ref id, the Storybook target, the
 *     probes (selectors live with the code they select), tolerance overrides
 *     and waivers.
 *
 * Checks, in order of weight (pixel diff counts least):
 *   1. token     computed style resolves to the Figma-bound variable
 *   2. geometry  named child bounds vs DOM rects, ±1 CSS px
 *   3. text      Figma text === DOM text (=== COPY-CANON when supplied)
 *   4. colour    sample points ≥4 px from any text, ΔE2000 ≤ 2
 *   5. board     tile count, size class and colour code, zero tolerance
 *   6. pixel     pixelmatch threshold 0.1; ≤1.0% component / ≤2.5% screen
 *                (provisional until K2); any contiguous blob larger than
 *                24×24 CSS px is flagged regardless of the percentage.
 *
 * REPORT-ONLY in slice 1.0b: `wouldPass` is computed and reported, and
 * nothing here or in the CLI turns it into an exit code. Slice 1.1 makes it
 * gate after K2 calibration.
 */

import { existsSync, readFileSync, statSync } from "node:fs";
import path from "node:path";

import pixelmatch from "pixelmatch";
import { PNG } from "pngjs";

export const GEOMETRY_TOLERANCE_PX = 1;
export const COLOR_DELTA_E_MAX = 2;
export const TEXT_CLEARANCE_PX = 4;
export const PIXEL_THRESHOLD = 0.1;
export const PIXEL_LIMITS = { component: 0.01, screen: 0.025 };
/** A differing blob is flagged when its bounding box exceeds this in BOTH axes (CSS px). */
export const BLOB_CSS_PX = 24;
/** Tile sizes in CSS px (§3.3 probe 5). */
export const TILE_SIZES = { sm: [13, 18], md: [28, 40], lg: [32, 46] };

const REQUIRED_REF_FIELDS = ["id", "figmaNode", "mode", "slotWidth", "slotHeight"];

// --- inputs ------------------------------------------------------------------

/**
 * `--refs` is a local directory (C3): a refs-repo checkout at a pinned tag, a
 * temp dir, or an unpacked CI artifact. Never a URL — fetching is the
 * caller's job, so the harness never depends on network or on O4.
 *
 * @param {string} input
 * @returns {string} absolute directory
 */
export function resolveRefsDir(input) {
  if (!input) throw new Error("--refs <local path> is required");
  if (/^[a-z][a-z0-9+.-]*:\/\//i.test(input) || /^[^/\\]+@[^:]+:/.test(input)) {
    throw new Error(`--refs must be a local path, not a URL or remote: ${input}`);
  }
  const dir = path.resolve(input);
  if (!existsSync(dir) || !statSync(dir).isDirectory()) throw new Error(`--refs is not a directory: ${dir}`);
  if (!existsSync(path.join(dir, "refs.json"))) throw new Error(`--refs has no refs.json: ${dir}`);
  return dir;
}

/**
 * @param {string} dir a directory accepted by resolveRefsDir
 * @returns {Array<object>} refs with defaults filled and `pngPath` resolved
 */
export function loadRefs(dir) {
  const raw = JSON.parse(readFileSync(path.join(dir, "refs.json"), "utf8"));
  const list = Array.isArray(raw) ? raw : raw.refs;
  if (!Array.isArray(list)) throw new Error("refs.json must be an array or { refs: [...] }");
  return list.map((ref) => {
    for (const field of REQUIRED_REF_FIELDS) {
      if (ref[field] === undefined || ref[field] === null) {
        throw new Error(`refs.json entry ${JSON.stringify(ref.id ?? "?")} is missing "${field}"`);
      }
    }
    const scale = ref.scale ?? 2;
    return {
      ...ref,
      scale,
      renderOffset: ref.renderOffset ?? { x: 0, y: 0 },
      nodes: ref.nodes ?? [],
      variables: ref.variables ?? {},
      tiles: ref.tiles ?? null,
      pngPath: path.join(dir, ref.file ?? `refs/${ref.id}@${scale}x.png`),
    };
  });
}

/** @param {string} file vrt/figma-refs.json */
export function loadManifest(file) {
  const raw = JSON.parse(readFileSync(file, "utf8"));
  if (!Array.isArray(raw.entries)) throw new Error(`${file}: expected { entries: [...] }`);
  for (const entry of raw.entries) {
    if (!entry.id) throw new Error(`${file}: an entry has no "id"`);
    if (!entry.target?.story) throw new Error(`${file}: entry "${entry.id}" has no target.story`);
  }
  return raw;
}

/**
 * Keep a screenshot clip on the page. A root at the canvas origin with a
 * render bleed would put the clip at a negative offset, which Playwright
 * rejects; trimming instead yields a shot smaller than the ref, which the
 * pixel check then reports as a size mismatch rather than the run crashing.
 *
 * @param {{x: number, y: number, width: number, height: number}} clip
 */
export function clampClip({ x, y, width, height }) {
  const cx = Math.max(0, x);
  const cy = Math.max(0, y);
  return { x: cx, y: cy, width: Math.max(1, width - (cx - x)), height: Math.max(1, height - (cy - y)) };
}

/** Join refs.json with the consumer manifest by ref id. */
export function joinRefs(refs, manifest) {
  const byId = new Map(refs.map((r) => [r.id, r]));
  const listed = new Set(manifest.entries.map((e) => e.id));
  return {
    pairs: manifest.entries.filter((e) => byId.has(e.id)).map((entry) => ({ ref: byId.get(entry.id), entry })),
    missingRefs: manifest.entries.filter((e) => !byId.has(e.id)).map((e) => e.id),
    unmanifested: refs.filter((r) => !listed.has(r.id)).map((r) => r.id),
  };
}

// --- colour ------------------------------------------------------------------

/**
 * Parse a hex (#rgb, #rrggbb, #rrggbbaa) or rgb()/rgba() string. The capture
 * step normalises every computed colour (oklch, color-mix, …) to rgb() through
 * a canvas in the browser, so these two forms are all that reach here.
 *
 * @returns {[number, number, number, number]|null} r, g, b 0–255; a 0–1
 */
export function parseColor(value) {
  if (typeof value !== "string") return null;
  const v = value.trim().toLowerCase();
  let m = v.match(/^#([0-9a-f]{3,8})$/);
  if (m) {
    let h = m[1];
    if (h.length === 3 || h.length === 4) h = [...h].map((c) => c + c).join("");
    if (h.length !== 6 && h.length !== 8) return null;
    const n = (i) => parseInt(h.slice(i, i + 2), 16);
    return [n(0), n(2), n(4), h.length === 8 ? n(6) / 255 : 1];
  }
  m = v.match(/^rgba?\(\s*([\d.]+)[,\s]+([\d.]+)[,\s]+([\d.]+)(?:\s*[,/]\s*([\d.]+%?))?\s*\)$/);
  if (m) {
    let a = m[4] === undefined ? 1 : parseFloat(m[4]);
    if (m[4]?.endsWith("%")) a /= 100;
    return [+m[1], +m[2], +m[3], a];
  }
  return null;
}

/** sRGB 0–255 → CIE L*a*b* (D65). */
export function srgbToLab([r, g, b]) {
  const lin = (c) => {
    const s = c / 255;
    return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  };
  const [R, G, B] = [lin(r), lin(g), lin(b)];
  const x = (R * 0.4124564 + G * 0.3575761 + B * 0.1804375) / 0.95047;
  const y = R * 0.2126729 + G * 0.7151522 + B * 0.072175;
  const z = (R * 0.0193339 + G * 0.119192 + B * 0.9503041) / 1.08883;
  const f = (t) => (t > 216 / 24389 ? Math.cbrt(t) : (t * 24389) / 27 / 116 + 16 / 116);
  return [116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))];
}

/** CIEDE2000 colour difference (Sharma, Wu & Dalal 2005). */
export function deltaE2000([L1, a1, b1], [L2, a2, b2]) {
  const rad = Math.PI / 180;
  const C1 = Math.hypot(a1, b1);
  const C2 = Math.hypot(a2, b2);
  const Cbar7 = ((C1 + C2) / 2) ** 7;
  const G = 0.5 * (1 - Math.sqrt(Cbar7 / (Cbar7 + 25 ** 7)));
  const a1p = (1 + G) * a1;
  const a2p = (1 + G) * a2;
  const C1p = Math.hypot(a1p, b1);
  const C2p = Math.hypot(a2p, b2);
  const hp = (b, a) => {
    if (a === 0 && b === 0) return 0;
    const h = Math.atan2(b, a) / rad;
    return h < 0 ? h + 360 : h;
  };
  const h1p = hp(b1, a1p);
  const h2p = hp(b2, a2p);
  const dLp = L2 - L1;
  const dCp = C2p - C1p;
  let dhp = 0;
  if (C1p * C2p !== 0) {
    dhp = h2p - h1p;
    if (dhp > 180) dhp -= 360;
    else if (dhp < -180) dhp += 360;
  }
  const dHp = 2 * Math.sqrt(C1p * C2p) * Math.sin((dhp / 2) * rad);
  const Lbp = (L1 + L2) / 2;
  const Cbp = (C1p + C2p) / 2;
  let hbp = h1p + h2p;
  if (C1p * C2p !== 0) {
    if (Math.abs(h1p - h2p) <= 180) hbp /= 2;
    else hbp = h1p + h2p < 360 ? (hbp + 360) / 2 : (hbp - 360) / 2;
  }
  const T =
    1 -
    0.17 * Math.cos((hbp - 30) * rad) +
    0.24 * Math.cos(2 * hbp * rad) +
    0.32 * Math.cos((3 * hbp + 6) * rad) -
    0.2 * Math.cos((4 * hbp - 63) * rad);
  const dTheta = 30 * Math.exp(-(((hbp - 275) / 25) ** 2));
  const Cbp7 = Cbp ** 7;
  const RC = 2 * Math.sqrt(Cbp7 / (Cbp7 + 25 ** 7));
  const SL = 1 + (0.015 * (Lbp - 50) ** 2) / Math.sqrt(20 + (Lbp - 50) ** 2);
  const SC = 1 + 0.045 * Cbp;
  const SH = 1 + 0.015 * Cbp * T;
  const RT = -Math.sin(2 * dTheta * rad) * RC;
  return Math.sqrt((dLp / SL) ** 2 + (dCp / SC) ** 2 + (dHp / SH) ** 2 + RT * (dCp / SC) * (dHp / SH));
}

/** Composite an RGBA pixel over white, so a translucent edge has one colour. */
function overWhite([r, g, b, a]) {
  const k = a / 255;
  return [r * k + 255 * (1 - k), g * k + 255 * (1 - k), b * k + 255 * (1 - k)];
}

function pixelAt(png, x, y) {
  if (x < 0 || y < 0 || x >= png.width || y >= png.height) return null;
  const i = (y * png.width + x) * 4;
  return [png.data[i], png.data[i + 1], png.data[i + 2], png.data[i + 3]];
}

// --- result helpers ------------------------------------------------------------

function summarise(items) {
  return { pass: items.every((i) => i.pass), checked: items.length, items };
}

// --- probe 1: tokens -----------------------------------------------------------

/**
 * @param {Record<string, string>} variables the ref's get_variable_defs output
 * @param {{variable: string, property: string, value: string|null, selector?: string}[]} measured
 */
export function tokenProbe(variables, measured) {
  return summarise(
    measured.map((m) => {
      const expected = variables[m.variable];
      const base = { variable: m.variable, property: m.property, expected: expected ?? null, actual: m.value };
      if (expected === undefined) return { ...base, pass: false, note: "variable not in the ref's variable defs" };
      if (m.value === null || m.value === undefined) return { ...base, pass: false, note: "element not found" };
      const ec = parseColor(expected);
      if (ec) {
        const ac = parseColor(m.value);
        if (!ac) return { ...base, pass: false, note: "expected a colour" };
        // 8-bit rounding of oklch → sRGB on either side can move a channel by one or two.
        const pass = ec.slice(0, 3).every((c, i) => Math.abs(c - ac[i]) <= 2) && Math.abs(ec[3] - ac[3]) <= 0.02;
        return { ...base, pass, note: pass ? "" : "colour differs" };
      }
      const en = parseFloat(expected);
      const an = parseFloat(m.value);
      if (Number.isNaN(en) || Number.isNaN(an)) {
        const pass = expected.trim() === String(m.value).trim();
        return { ...base, pass, note: pass ? "" : "value differs" };
      }
      const pass = Math.abs(en - an) <= 0.5;
      return { ...base, pass, note: pass ? "" : `${an} ≠ ${en}` };
    }),
  );
}

// --- probe 2: geometry ---------------------------------------------------------

/**
 * @param {{name: string, x: number, y: number, width: number, height: number}[]} nodes
 *   Figma child bounds relative to the ref node's origin (get_metadata)
 * @param {{node: string, rect: {x,y,width,height}|null}[]} measured
 *   DOM rects relative to the target root's border box, CSS px
 */
export function geometryProbe(nodes, measured, tolerance = GEOMETRY_TOLERANCE_PX) {
  return summarise(
    measured.map(({ node, rect }) => {
      const fig = nodes.find((n) => n.name === node);
      if (!fig) return { node, pass: false, note: `no Figma node named "${node}"` };
      if (!rect) return { node, pass: false, note: "element not found" };
      const off = ["x", "y", "width", "height"].filter((k) => Math.abs(rect[k] - fig[k]) > tolerance);
      const deltas = Object.fromEntries(
        ["x", "y", "width", "height"].map((k) => [k, Math.round((rect[k] - fig[k]) * 100) / 100]),
      );
      return {
        node,
        pass: off.length === 0,
        expected: { x: fig.x, y: fig.y, width: fig.width, height: fig.height },
        actual: rect,
        deltas,
        note: off.length ? `${off.join(", ")} off by more than ${tolerance}px` : "",
      };
    }),
  );
}

// --- probe 3: text -------------------------------------------------------------

const norm = (s) =>
  String(s ?? "")
    .replace(/\s+/g, " ")
    .trim();

/**
 * @param {{name: string, characters?: string}[]} nodes
 * @param {{node: string, text: string|null, canonKey?: string}[]} measured
 * @param {Record<string, string>|null} canon COPY-CANON strings by i18n id, when available
 */
export function textProbe(nodes, measured, canon = null) {
  return summarise(
    measured.map(({ node, text, canonKey }) => {
      const fig = nodes.find((n) => n.name === node && n.characters !== undefined);
      if (!fig) return { node, pass: false, note: `no Figma text node named "${node}"` };
      if (text === null || text === undefined) return { node, pass: false, note: "element not found" };
      const expected = norm(fig.characters);
      const actual = norm(text);
      if (expected !== actual) return { node, pass: false, expected, actual, note: "text differs from Figma" };
      if (canon && canonKey) {
        if (norm(canon[canonKey]) !== actual) {
          return { node, pass: false, expected, actual, note: `differs from CANON ${canonKey}` };
        }
      }
      return { node, pass: true, expected, actual, note: "" };
    }),
  );
}

// --- probe 4: colour sampling --------------------------------------------------

/**
 * Sample points are CSS px relative to the ref node's origin. A point closer
 * than 4 px to any Figma TEXT node's bounds is invalid: text never matches
 * pixel for pixel (Skia vs FreeType), so a sample there measures fonts.
 */
export function colorProbe({ ref, refPng, shotPng, points, max = COLOR_DELTA_E_MAX }) {
  const texts = ref.nodes.filter((n) => n.type === "TEXT");
  return summarise(
    points.map(({ x, y, label }) => {
      const near = texts.find(
        (t) =>
          x > t.x - TEXT_CLEARANCE_PX &&
          x < t.x + t.width + TEXT_CLEARANCE_PX &&
          y > t.y - TEXT_CLEARANCE_PX &&
          y < t.y + t.height + TEXT_CLEARANCE_PX,
      );
      const base = { x, y, label: label ?? "" };
      if (near) return { ...base, pass: false, note: `invalid sample: within 4 px of text "${near.name}"` };
      const px = Math.round((x + ref.renderOffset.x) * ref.scale);
      const py = Math.round((y + ref.renderOffset.y) * ref.scale);
      const a = pixelAt(refPng, px, py);
      const b = pixelAt(shotPng, px, py);
      if (!a || !b) return { ...base, pass: false, note: "sample outside an image" };
      const deltaE = Math.round(deltaE2000(srgbToLab(overWhite(a)), srgbToLab(overWhite(b))) * 100) / 100;
      return {
        ...base,
        expected: a,
        actual: b,
        deltaE,
        pass: deltaE <= max,
        note: deltaE <= max ? "" : `ΔE2000 ${deltaE} > ${max}`,
      };
    }),
  );
}

// --- probe 5: board ------------------------------------------------------------

/** @returns {"sm"|"md"|"lg"|null} */
export function sizeClassOf({ width, height }) {
  for (const [name, [w, h]] of Object.entries(TILE_SIZES)) {
    if (Math.round(width) === w && Math.round(height) === h) return name;
  }
  return null;
}

/**
 * Zero tolerance: same tile count, and per tile (in reading order) the same
 * size class and colour code.
 *
 * @param {{width: number, height: number, color: number|string}[]} expected from Figma instances
 * @param {{width: number, height: number, color: number|string}[]} actual from DOM data-* attributes
 */
export function boardProbe(expected, actual) {
  const items = [];
  items.push({
    what: "count",
    expected: expected.length,
    actual: actual.length,
    pass: expected.length === actual.length,
  });
  const n = Math.min(expected.length, actual.length);
  for (let i = 0; i < n; i++) {
    const es = sizeClassOf(expected[i]);
    const as = sizeClassOf(actual[i]);
    if (es !== as || as === null) items.push({ what: `tile ${i} size`, expected: es, actual: as, pass: false });
    if (String(expected[i].color) !== String(actual[i].color)) {
      items.push({ what: `tile ${i} colour`, expected: expected[i].color, actual: actual[i].color, pass: false });
    }
  }
  return summarise(items);
}

// --- check 6: pixel diff -------------------------------------------------------

/** Copy `png` into a transparent canvas of width × height. */
function padTo(png, width, height) {
  if (png.width === width && png.height === height) return png;
  const out = new PNG({ width, height });
  out.data.fill(0);
  for (let y = 0; y < png.height; y++) {
    png.data.copy(out.data, y * width * 4, y * png.width * 4, (y + 1) * png.width * 4);
  }
  return out;
}

/**
 * Connected components (8-connected) of a boolean mask, as bounding boxes.
 *
 * @param {Uint8Array} mask
 */
export function findBlobs(mask, width, height) {
  const seen = new Uint8Array(mask.length);
  const blobs = [];
  const stack = [];
  for (let start = 0; start < mask.length; start++) {
    if (!mask[start] || seen[start]) continue;
    let minX = width;
    let minY = height;
    let maxX = -1;
    let maxY = -1;
    let pixels = 0;
    seen[start] = 1;
    stack.push(start);
    while (stack.length) {
      const i = stack.pop();
      const x = i % width;
      const y = (i - x) / width;
      pixels++;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      for (let dy = -1; dy <= 1; dy++) {
        for (let dx = -1; dx <= 1; dx++) {
          const nx = x + dx;
          const ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
          const j = ny * width + nx;
          if (mask[j] && !seen[j]) {
            seen[j] = 1;
            stack.push(j);
          }
        }
      }
    }
    blobs.push({ x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1, pixels });
  }
  return blobs;
}

/**
 * pixelmatch at threshold 0.1 (anti-aliased pixels excluded, as pixelmatch
 * does by default), plus blob detection on the differing pixels.
 *
 * @param {PNG} refPng
 * @param {PNG} shotPng
 * @param {{scale?: number, threshold?: number, blobCssPx?: number}} [options]
 *   scale converts the CSS-px blob size to image px (the shot's deviceScaleFactor)
 */
export function pixelDiff(refPng, shotPng, { scale = 2, threshold = PIXEL_THRESHOLD, blobCssPx = BLOB_CSS_PX } = {}) {
  const width = Math.max(refPng.width, shotPng.width);
  const height = Math.max(refPng.height, shotPng.height);
  const a = padTo(refPng, width, height);
  const b = padTo(shotPng, width, height);
  const diff = new PNG({ width, height });
  const diffPixels = pixelmatch(a.data, b.data, diff.data, width, height, {
    threshold,
    diffColor: [255, 0, 0],
    aaColor: [255, 255, 0],
    alpha: 0.2,
  });
  // Re-derive the counted pixels from the output: exact red, never AA yellow.
  // The faded backdrop pixelmatch draws is grey (r === g === b), so it never
  // reads as red.
  const mask = new Uint8Array(width * height);
  for (let i = 0; i < mask.length; i++) {
    const o = i * 4;
    mask[i] = diff.data[o] === 255 && diff.data[o + 1] === 0 && diff.data[o + 2] === 0 ? 1 : 0;
  }
  const blobs = findBlobs(mask, width, height);
  const limit = blobCssPx * scale;
  return {
    width,
    height,
    sizeMatch: refPng.width === shotPng.width && refPng.height === shotPng.height,
    refSize: [refPng.width, refPng.height],
    shotSize: [shotPng.width, shotPng.height],
    diffPixels,
    ratio: diffPixels / (width * height),
    blobs,
    flaggedBlobs: blobs.filter((blob) => blob.width > limit && blob.height > limit),
    diffPng: diff,
  };
}

// --- one entry -----------------------------------------------------------------

/**
 * Run every check for one ref/manifest pair.
 *
 * @param {{ref: object, entry: object, refPng: PNG, shotPng: PNG,
 *   dom: {geometry?: object[], text?: object[], tokens?: object[], board?: {tiles: object[]}|null},
 *   canon?: Record<string,string>|null}} input
 */
export function evaluateEntry({ ref, entry, refPng, shotPng, dom, canon = null }) {
  const tolerance = entry.tolerance ?? {};
  const checks = {
    token: tokenProbe(ref.variables, dom.tokens ?? []),
    geometry: geometryProbe(ref.nodes, dom.geometry ?? [], tolerance.geometryPx ?? GEOMETRY_TOLERANCE_PX),
    text: textProbe(ref.nodes, dom.text ?? [], canon),
    color: colorProbe({
      ref,
      refPng,
      shotPng,
      points: entry.probes?.colors ?? [],
      max: tolerance.deltaE ?? COLOR_DELTA_E_MAX,
    }),
  };
  if (ref.tiles || dom.board) {
    checks.board = boardProbe(ref.tiles ?? [], dom.board?.tiles ?? []);
  }
  const diff = pixelDiff(refPng, shotPng, { scale: ref.scale });
  const limit = tolerance.pixelRatio ?? PIXEL_LIMITS[entry.kind ?? "component"] ?? PIXEL_LIMITS.component;
  const pixelPass = diff.sizeMatch && diff.ratio <= limit && diff.flaggedBlobs.length === 0;
  checks.pixel = {
    pass: pixelPass,
    limit,
    ratio: Math.round(diff.ratio * 1e5) / 1e5,
    diffPixels: diff.diffPixels,
    sizeMatch: diff.sizeMatch,
    refSize: diff.refSize,
    shotSize: diff.shotSize,
    flaggedBlobs: diff.flaggedBlobs,
    blobCount: diff.blobs.length,
  };
  const waived = new Set((entry.waivers ?? []).map((w) => w.check));
  const wouldPass = Object.entries(checks).every(([name, c]) => c.pass || waived.has(name));
  return {
    id: ref.id,
    figmaNode: ref.figmaNode,
    kind: entry.kind ?? "component",
    wouldPass,
    checks,
    diffPng: diff.diffPng,
  };
}

// --- report --------------------------------------------------------------------

const CHECK_ORDER = ["token", "geometry", "text", "color", "board", "pixel"];

/** Markdown for a human (and for Fable's §3.4 parity review). */
export function renderMarkdown(report) {
  const lines = [
    "# Figma parity report",
    "",
    "**Report-only (slice 1.0b).** Nothing here fails CI; gating starts in slice 1.1 after K2 calibration.",
    "",
    `Refs: \`${report.refsDir}\` (tag: ${report.refsTag ?? "none"}) · manifest: \`${report.manifest}\``,
    "",
  ];
  if (report.missingRefs.length) lines.push(`Manifest ids with no ref: ${report.missingRefs.join(", ")}`, "");
  if (report.unmanifested.length) lines.push(`Refs with no manifest entry: ${report.unmanifested.join(", ")}`, "");
  lines.push("| Ref | Figma node | Token | Geometry | Text | Colour | Board | Pixel | Verdict |");
  lines.push("|---|---|---|---|---|---|---|---|---|");
  for (const e of report.entries) {
    if (e.error) {
      lines.push(`| \`${e.id}\` | ${e.figmaNode ?? ""} | | | | | | | would fail: ${e.error} |`);
      continue;
    }
    const cell = (name) => {
      const c = e.checks[name];
      if (!c) return "—";
      if (name === "pixel")
        return `${c.pass ? "ok" : "FAIL"} ${(c.ratio * 100).toFixed(2)}%${c.flaggedBlobs.length ? `, ${c.flaggedBlobs.length} blob(s)` : ""}${c.sizeMatch ? "" : ", size"}`;
      return c.checked === 0 ? "—" : `${c.pass ? "ok" : "FAIL"} ${c.items.filter((i) => i.pass).length}/${c.checked}`;
    };
    lines.push(
      `| \`${e.id}\` | ${e.figmaNode} | ${CHECK_ORDER.map(cell).join(" | ")} | ${e.wouldPass ? "would pass" : "would fail"} |`,
    );
  }
  const failures = report.entries.flatMap((e) =>
    e.error
      ? []
      : CHECK_ORDER.flatMap((name) =>
          (e.checks[name]?.items ?? [])
            .filter((i) => !i.pass)
            .map((i) => `- \`${e.id}\` ${name}: ${i.note || JSON.stringify(i)}`),
        ),
  );
  for (const e of report.entries) {
    const px = e.checks?.pixel;
    if (!px || px.pass) continue;
    const why = [];
    if (!px.sizeMatch) why.push(`size ${px.shotSize.join("×")} vs ref ${px.refSize.join("×")}`);
    if (px.ratio > px.limit) why.push(`${(px.ratio * 100).toFixed(2)}% differing > ${px.limit * 100}%`);
    for (const b of px.flaggedBlobs) why.push(`blob ${b.width}×${b.height} at ${b.x},${b.y}`);
    failures.push(`- \`${e.id}\` pixel: ${why.join("; ")} (see ${e.id}.diff.png)`);
  }
  if (failures.length) lines.push("", "## Findings", "", ...failures);
  return `${lines.join("\n")}\n`;
}
