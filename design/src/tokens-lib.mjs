// Pure token-transform helpers, extracted from build.mjs so the hex/validation/
// naming logic is unit-testable without doing file I/O. build.mjs imports these
// and adds only readFile/writeFile around them.

/** Flatten nested tokens to dot-paths, skipping `$`-prefixed metadata keys. */
export function flatten(obj, prefix = "", out = {}) {
  for (const [k, v] of Object.entries(obj)) {
    if (k.startsWith("$")) continue;
    const key = prefix ? `${prefix}.${k}` : k;
    if (v && typeof v === "object" && !Array.isArray(v)) flatten(v, key, out);
    else out[key] = v;
  }
  return out;
}

export const HEX = /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/;

/** Throw on malformed input so the build never emits broken tokens. */
export function validate(flatTokens, label) {
  for (const [k, v] of Object.entries(flatTokens)) {
    if (typeof v === "number") continue;
    if (typeof v !== "string") {
      throw new TypeError(
        `tokens.json (${label}): "${k}" must be a string or number, got ${typeof v}`,
      );
    }
    if (v.startsWith("#") && !HEX.test(v)) {
      throw new Error(`tokens.json (${label}): "${k}" is not a 3/6/8-digit hex color: ${v}`);
    }
    // Reject characters that would break out of a CSS value / SVG-ish markup.
    if (/[;{}<>]|[\r\n]/.test(v)) {
      throw new Error(
        `tokens.json (${label}): "${k}" contains an unsafe character: ${JSON.stringify(v)}`,
      );
    }
  }
}

export const kebab = (s) =>
  s.replaceAll(".", "-").replace(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase();

export const isPx = (path, flat) =>
  /^(font\.size|space|radius)\./.test(path) && typeof flat[path] === "number";

export const cssValue = (k, v, flat) => (isPx(k, flat) ? v + "px" : v);

export const dartName = (k) =>
  k
    .split(/[.-]/)
    .map((p, i) => (i === 0 ? p : p[0].toUpperCase() + p.slice(1)))
    .join("");

/** #rgb / #rrggbb / #rrggbbaa → Dart Color(0xAARRGGBB). */
export function dartColor(hex) {
  let h = hex.slice(1);
  if (h.length === 3) h = [...h].map((c) => c + c).join(""); // #rgb → rrggbb
  if (h.length === 6) return `Color(0xFF${h.toUpperCase()})`;
  const rgb = h.slice(0, 6);
  const a = h.slice(6, 8);
  return `Color(0x${(a + rgb).toUpperCase()})`;
}

/** Deep-merge `over` onto `base` (dark color overrides onto light). */
export function deepMerge(base, over) {
  const out = { ...base };
  for (const [k, v] of Object.entries(over || {})) {
    if (k.startsWith("$")) continue;
    out[k] = v && typeof v === "object" && !Array.isArray(v) ? deepMerge(base?.[k] ?? {}, v) : v;
  }
  return out;
}
