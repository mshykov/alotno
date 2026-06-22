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
import {
  flatten,
  validate,
  kebab,
  cssValue,
  dartName,
  dartColor,
  deepMerge,
} from "./tokens-lib.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
const tokens = JSON.parse(await readFile(join(root, "tokens.json"), "utf8"));

const flat = flatten(tokens);

// ---- validate: fail loudly on malformed input, never emit broken output ----
for (const req of ["color", "font", "space", "radius"]) {
  if (!tokens[req]) throw new Error(`tokens.json: missing required top-level key "${req}"`);
}
validate(flat, "light");

// ---- CSS custom properties ----
const cssVar = ([k, v]) => `  --${kebab(k)}: ${cssValue(k, v, flat)};`;
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

// ---- Dart ---- (dartName/dartColor/deepMerge live in tokens-lib.mjs)
const dartLine = ([k, v]) => {
  const name = dartName(k);
  if (typeof v === "number") return `  static const ${name} = ${v}.0;`;
  if (typeof v === "string" && v.startsWith("#")) return `  static const ${name} = ${dartColor(v)};`;
  return `  static const ${name} = ${JSON.stringify(v)};`;
};

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
