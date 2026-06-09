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
const kebab = (s) => s.replace(/\./g, "-").replace(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase();
const isPx = (path) => /^(font\.size|space|radius)\./.test(path) && typeof flat[path] === "number";

// ---- CSS custom properties ----
const cssVar = ([k, v]) => `  --${kebab(k)}: ${isPx(k) ? `${v}px` : v};`;
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
    .split(/[.\-]/)
    .map((p, i) => (i === 0 ? p : p[0].toUpperCase() + p.slice(1)))
    .join("");
const dartLine = ([k, v]) => {
  const name = dartName(k);
  if (typeof v === "number") return `  static const ${name} = ${v}.0;`;
  if (typeof v === "string" && v.startsWith("#"))
    return `  static const ${name} = Color(0xFF${v.slice(1).toUpperCase()});`;
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
