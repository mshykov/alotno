import { describe, expect, it } from "vitest";
import astroSrc from "./pages/index.astro?raw";
import headers from "../public/_headers?raw";

// script-src pins the inline theme scripts by sha256 hash instead of
// 'unsafe-inline'. Astro emits `is:inline` scripts verbatim, so the hash of the
// source body equals the hash the browser computes for the emitted script.
// This test recomputes those hashes from source and asserts _headers still
// lists them — so editing a theme script without updating the CSP fails CI
// here, rather than silently breaking script execution in production.

async function sha256Base64(input: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return btoa(String.fromCharCode(...new Uint8Array(digest)));
}

const inlineScriptBodies = [...astroSrc.matchAll(/<script\s+is:inline\s*>([\s\S]*?)<\/script>/g)].map(
  (m) => m[1],
);

describe("CSP script-src hashes", () => {
  it("finds the inline theme scripts in index.astro", () => {
    // Before-paint theme setter + theme toggle. Update this count (and the
    // hashes in _headers) if the page's inline scripts change.
    expect(inlineScriptBodies).toHaveLength(2);
  });

  it("lists a matching sha256 hash in _headers for every inline script", async () => {
    // Guard against a vacuous pass: if the regex ever stops matching, the loop
    // below would run zero assertions and still go green.
    expect(inlineScriptBodies.length).toBeGreaterThan(0);
    for (const body of inlineScriptBodies) {
      const hash = `sha256-${await sha256Base64(body)}`;
      expect(headers, `_headers script-src is missing ${hash}`).toContain(hash);
    }
  });

  it("no longer allows 'unsafe-inline' in script-src", () => {
    const csp = headers.match(/Content-Security-Policy:[^\n]*/)?.[0] ?? "";
    const scriptSrc = csp.match(/script-src[^;]*/)?.[0] ?? "";
    expect(scriptSrc).not.toContain("'unsafe-inline'");
  });
});
