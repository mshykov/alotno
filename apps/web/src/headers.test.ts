import { describe, expect, it } from "vitest";
import headers from "../public/_headers?raw";

// Pins the security-critical response headers so they can't be silently
// weakened in a future edit. The CSP is the backbone of the "nothing is
// uploaded" privacy promise; HSTS forces HTTPS.
describe("Cloudflare Pages _headers", () => {
  it("enforces the locked-down Content-Security-Policy", () => {
    expect(headers).toContain("Content-Security-Policy:");
    for (const directive of [
      "default-src 'self'",
      "connect-src 'self'", // no exfiltration endpoint
      "object-src 'none'",
      "base-uri 'none'",
      "frame-ancestors 'none'",
    ]) {
      expect(headers, `CSP must keep "${directive}"`).toContain(directive);
    }
  });

  it("sends HSTS to force HTTPS", () => {
    // Pin includeSubDomains too — it's security-relevant and could otherwise be
    // silently dropped without failing the test.
    expect(headers).toMatch(/Strict-Transport-Security:\s*max-age=\d+;\s*includeSubDomains/);
  });

  it("keeps the supporting hardening headers", () => {
    expect(headers).toContain("X-Content-Type-Options: nosniff");
    expect(headers).toContain("X-Frame-Options: DENY");
    expect(headers).toContain("Referrer-Policy: no-referrer");
  });
});
