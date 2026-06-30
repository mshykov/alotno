import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const publicDir = resolve(dirname(fileURLToPath(import.meta.url)), "../public");

describe("security.txt", () => {
  it("publishes the security contact at the well-known path", () => {
    const securityTxt = resolve(publicDir, ".well-known/security.txt");

    expect(existsSync(securityTxt)).toBe(true);
    if (!existsSync(securityTxt)) return;

    const contents = readFileSync(securityTxt, "utf8");

    expect(contents).toContain("Contact: mailto:security@alotno.app");
    expect(contents).toContain("Expires: 2027-06-30T00:00:00Z");
    expect(contents).toContain("Preferred-Languages: en");
    expect(contents).toContain("Canonical: https://alotno.app/.well-known/security.txt");
  });
});
