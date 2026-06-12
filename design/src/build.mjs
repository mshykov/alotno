// Generates platform-specific token files from tokens.json.
// One source of truth -> CSS custom properties, a TS module, and a Dart class.
//
//   node src/build.mjs
//
// Outputs:
//   dist/tokens.css   (consumed by apps/web)
//   dist/tokens.ts    (typed access in web/JS)
//   dist/tokens.dart  (copy into apps/app/lib/design/, consumed by Flutter)

import { readFile, mkdir, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
const tokens = JSON.parse(await readFile(join(root, "tokens.json"), "utf8"));

/** Flatten nested tokens to dot-paths, skipping `$`-prefixed metadata keys. */
function flatten(obj, prefix = "", out = {}) {
  for (const [k, v] of Object.entries(obj)) {
    if (k.startsWith("$")) continue;
    const key = prefix ? `${prefix}.${k}` : k;
    if (v && typeof v === "object" && !Array.isArray(v)) flatten(v, key, out);
    else out[key] = v;
  }
  return out;
}

const flat = flatten(tokens);

// ---- validate: fail loudly on malformed input, never emit broken output ----
const HEX = /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/;
function validate(flatTokens, label) {
  for (const [k, v] of Object.entries(flatTokens)) {
    if (typeof v === "number") continue;
    if (typeof v !== "string") {
      throw new TypeError(`tokens.json (${label}): "${k}" must be a string or number, got ${typeof v}`);
    }
    if (v.startsWith("#") && !HEX.test(v)) {
      throw new Error(`tokens.json (${label}): "${k}" is not a 3/6/8-digit hex color: ${v}`);
    }
    // Reject characters that would break out of a CSS value / SVG-ish markup.
    if (/[;{}<>]|[\r\n]/.test(v)) {
      throw new Error(`tokens.json (${label}): "${k}" contains an unsafe character: ${JSON.stringify(v)}`);
    }
  }
}
for (const req of ["color", "font", "space", "radius"]) {
  if (!tokens[req]) throw new Error(`tokens.json: missing required top-level key "${req}"`);
}
validate(flat, "light");

const kebab = (s) => s.replaceAll(".", "-").replace(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase();
const isPx = (path) => /^(font\.size|space|radius)\./.test(path) && typeof flat[path] === "number";

// ---- CSS custom properties ----
const cssValue = (k, v) => (isPx(k) ? v + "px" : v);
const cssVar = ([k, v]) => `  --${kebab(k)}: ${cssValue(k, v)};`;
let css =
  `/* GENERATED from design/tokens.json — do not edit by hand. */\n:root {\n` +
  Object.entries(flat).map(cssVar).join("\n") +
  `\n}\n`;

// Dark-mode overrides (tokens.$dark). Emitted as a prefers-color-scheme block
// AND a [data-theme="dark"] hook for an explicit toggle.
if (tokens.$dark) {
  const darkFlat = flatten(tokens.$dark);
  const darkVars = Object.entries(darkFlat).map(cssVar).join("\n");
  css +=
    `\n@media (prefers-color-scheme: dark) {\n  :root:not([data-theme="light"]) {\n` +
    darkVars.replace(/^/gm, "  ") +
    `\n  }\n}\n` +
    `\n:root[data-theme="dark"] {\n${darkVars}\n}\n`;
}

// ---- TypeScript ----
function stripMeta(obj) {
  if (Array.isArray(obj)) return obj.map(stripMeta);
  if (obj && typeof obj === "object") {
    return Object.fromEntries(
      Object.entries(obj)
        .filter(([k]) => !k.startsWith("$"))
        .map(([k, v]) => [k, stripMeta(v)]),
    );
  }
  return obj;
}

const cleanTs =
  `// GENERATED from design/tokens.json — do not edit by hand.\n` +
  `export const tokens = ${JSON.stringify(stripMeta(tokens), null, 2)} as const;\n`;

// ---- Dart ----
const dartName = (k) =>
  k
    .split(/[.-]/)
    .map((p, i) => (i === 0 ? p : p[0].toUpperCase() + p.slice(1)))
    .join("");
// #rgb / #rrggbb / #rrggbbaa → Dart Color(0xAARRGGBB). Handles all valid hex
// lengths (validated above), not just 6-digit.
function dartColor(hex) {
  let h = hex.slice(1);
  if (h.length === 3) h = [...h].map((c) => c + c).join(""); // #rgb → rrggbb
  if (h.length === 6) return `Color(0xFF${h.toUpperCase()})`;
  // #rrggbbaa → 0xAARRGGBB
  const rgb = h.slice(0, 6);
  const a = h.slice(6, 8);
  return `Color(0x${(a + rgb).toUpperCase()})`;
}
const dartLine = ([k, v]) => {
  const name = dartName(k);
  if (typeof v === "number") return `  static const ${name} = ${v}.0;`;
  if (typeof v === "string" && v.startsWith("#")) return `  static const ${name} = ${dartColor(v)};`;
  return `  static const ${name} = ${JSON.stringify(v)};`;
};

// Deep-merge the dark color overrides over the light colors so TokensDark has
// every color name (dark where overridden, light otherwise).
function deepMerge(base, over) {
  const out = { ...base };
  for (const [k, v] of Object.entries(over || {})) {
    if (k.startsWith("$")) continue;
    out[k] = v && typeof v === "object" && !Array.isArray(v) ? deepMerge(base?.[k] ?? {}, v) : v;
  }
  return out;
}

const dartLines = Object.entries(flat).map(dartLine);
let dart =
  `// GENERATED from design/tokens.json — do not edit by hand.\n` +
  `import 'package:flutter/material.dart';\n\n` +
  `class Tokens {\n${dartLines.join("\n")}\n}\n`;

// Dark-mode color tokens (only colors change in dark). Consumers pick the class
// by brightness: `isDark ? TokensDark.colorSurfaceBase : Tokens.colorSurfaceBase`.
if (tokens.$dark) {
  const darkColors = flatten({ color: deepMerge(tokens.color, tokens.$dark.color) });
  validate(darkColors, "dark");
  const darkLines = Object.entries(darkColors)
    .filter(([, v]) => typeof v === "string" && v.startsWith("#"))
    .map(dartLine);
  dart += `\nclass TokensDark {\n${darkLines.join("\n")}\n}\n`;
}

await mkdir(join(root, "dist"), { recursive: true });
await Promise.all([
  writeFile(join(root, "dist", "tokens.css"), css),
  writeFile(join(root, "dist", "tokens.ts"), cleanTs),
  writeFile(join(root, "dist", "tokens.dart"), dart),
]);

console.log("✓ tokens generated: dist/tokens.css, dist/tokens.ts, dist/tokens.dart");
