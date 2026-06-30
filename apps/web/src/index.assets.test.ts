import { existsSync, statSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import source from "./pages/index.astro?raw";

const publicDir = resolve(dirname(fileURLToPath(import.meta.url)), "../public");

describe("home page visible icon assets", () => {
  it("uses the optimized 208px PNG for visible page icons", () => {
    expect(source).toContain('<img src="/icon-208.png" width="28" height="28" alt="" />');
    expect(source).toContain(
      '<img class="logo" src="/icon-208.png" width="104" height="104" alt="Alotno — PNG to vector converter" />',
    );
  });

  it("ships an optimized visible icon asset", () => {
    const optimizedIcon = resolve(publicDir, "icon-208.png");

    expect(existsSync(optimizedIcon)).toBe(true);
    if (!existsSync(optimizedIcon)) return;

    expect(statSync(optimizedIcon).size).toBeLessThan(statSync(resolve(publicDir, "icon.png")).size);
  });
});
