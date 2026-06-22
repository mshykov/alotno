import { describe, it, expect } from "vitest";
import {
  flatten,
  validate,
  kebab,
  isPx,
  cssValue,
  dartName,
  dartColor,
  deepMerge,
} from "./tokens-lib.mjs";

describe("flatten", () => {
  it("dot-paths nested objects and skips $-metadata", () => {
    const out = flatten({ color: { brand: { 500: "#fff" } }, $meta: { x: 1 }, space: { 1: 4 } });
    expect(out).toEqual({ "color.brand.500": "#fff", "space.1": 4 });
  });
});

describe("validate", () => {
  it("accepts strings and numbers", () => {
    expect(() => validate({ "color.x": "#abc", "space.1": 4 }, "light")).not.toThrow();
  });
  it("rejects a non-string/number value with TypeError", () => {
    expect(() => validate({ "x.y": true }, "light")).toThrow(TypeError);
  });
  it("rejects a malformed hex color", () => {
    expect(() => validate({ "color.x": "#12" }, "light")).toThrow(/not a 3\/6\/8-digit hex/);
  });
  it("rejects CSS/markup-breaking characters (injection guard)", () => {
    for (const bad of ["red;}", "a{b", "<svg>", "line\nbreak"]) {
      expect(() => validate({ "x.y": bad }, "light")).toThrow(/unsafe character/);
    }
  });
});

describe("kebab", () => {
  it("dots → hyphens and camelCase → kebab", () => {
    expect(kebab("color.brand.500")).toBe("color-brand-500");
    expect(kebab("fontSize.lg")).toBe("font-size-lg");
  });
});

describe("isPx / cssValue", () => {
  const flat = { "space.1": 4, "radius.sm": 6, "color.x": "#fff", "font.weight.bold": 700 };
  it("appends px only to numeric space/radius/font.size", () => {
    expect(cssValue("space.1", 4, flat)).toBe("4px");
    expect(cssValue("radius.sm", 6, flat)).toBe("6px");
  });
  it("leaves colors and non-size numerics unitless", () => {
    expect(cssValue("color.x", "#fff", flat)).toBe("#fff");
    expect(isPx("font.weight.bold", flat)).toBe(false);
  });
});

describe("dartName", () => {
  it("camelCases dot/hyphen-separated paths", () => {
    expect(dartName("color.brand.500")).toBe("colorBrand500");
    expect(dartName("font-size.lg")).toBe("fontSizeLg");
  });
});

describe("dartColor", () => {
  it("expands #rgb to 0xFFRRGGBB", () => {
    expect(dartColor("#abc")).toBe("Color(0xFFAABBCC)");
  });
  it("maps #rrggbb to 0xFFRRGGBB", () => {
    expect(dartColor("#6366F1")).toBe("Color(0xFF6366F1)");
  });
  it("reorders #rrggbbaa to 0xAARRGGBB", () => {
    expect(dartColor("#11223380")).toBe("Color(0x80112233)");
  });
});

describe("deepMerge", () => {
  it("overrides nested keys, keeps the rest, and skips $-metadata", () => {
    const base = { color: { a: "#000", b: "#111" } };
    const over = { color: { b: "#fff" }, $dark: { ignore: 1 } };
    expect(deepMerge(base, over)).toEqual({ color: { a: "#000", b: "#fff" } });
  });
});
