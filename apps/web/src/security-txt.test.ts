import { describe, expect, it } from "vitest";
import securityTxt from "../public/.well-known/security.txt?raw";

describe("security.txt", () => {
  it("publishes the security contact at the well-known path", () => {
    expect(securityTxt).toContain("Contact: mailto:security@alotno.app");
    expect(securityTxt).toContain("Expires: 2027-06-30T00:00:00Z");
    expect(securityTxt).toContain("Preferred-Languages: en");
    expect(securityTxt).toContain("Canonical: https://alotno.app/.well-known/security.txt");
  });
});
