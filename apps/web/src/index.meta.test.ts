import { describe, expect, it } from "vitest";
import source from "./pages/index.astro?raw";

function extractConst(source: string, name: string) {
  const match = source.match(new RegExp(`const ${name} =\\n\\s+"([^"]+)";`));
  return match?.[1];
}

describe("home page social metadata", () => {
  it("keeps the long SEO description on the standard description tag", () => {
    const description = extractConst(source, "description");
    const ogDescription = extractConst(source, "ogDescription");

    expect(description).toBeDefined();
    expect(ogDescription).toBeDefined();
    expect(description).not.toBe(ogDescription);
    expect(source).toContain('<meta name="description" content={description} />');
  });

  it("uses a short Open Graph description for mobile previews", () => {
    const ogDescription = extractConst(source, "ogDescription");

    expect(ogDescription).toBeDefined();
    expect(ogDescription!.length).toBeLessThanOrEqual(125);
    expect(source).toContain('<meta property="og:description" content={ogDescription} />');
    expect(source).toContain('<meta name="twitter:description" content={ogDescription} />');
  });

  it("names the site for social cards", () => {
    expect(source).toContain('<meta property="og:site_name" content="Alotno" />');
  });
});
