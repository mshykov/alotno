import { describe, expect, it } from "vitest";
import optimizedIconUrl from "../public/icon-208.png?url";
import originalIconUrl from "../public/icon.png?url";
import source from "./pages/index.astro?raw";

describe("home page visible icon assets", () => {
  it("uses the optimized 208px PNG for visible page icons", () => {
    expect(source).toContain('<img src="/icon-208.png" width="28" height="28" alt="" />');
    expect(source).toContain(
      '<img class="logo" src="/icon-208.png" width="104" height="104" alt="Alotno — PNG to vector converter" />',
    );
    expect(source).not.toContain('src="/icon.png"');
  });

  it("ships a dedicated optimized visible icon asset", () => {
    expect(optimizedIconUrl).toContain("icon-208.png");
    expect(originalIconUrl).toContain("icon.png");
    expect(optimizedIconUrl).not.toBe(originalIconUrl);
  });
});
