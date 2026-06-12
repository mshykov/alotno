import { defineConfig } from "astro/config";
import { fileURLToPath } from "node:url";

const repoRoot = fileURLToPath(new URL("../../", import.meta.url));
const wasmPkg = fileURLToPath(new URL("../../bindings/wasm/pkg", import.meta.url));

// Static marketing site + in-browser converter. No SSR/backend — deploys as
// static files (Cloudflare Pages). WASM is loaded client-side in the converter.
export default defineConfig({
  site: "https://alotno.app",
  output: "static",
  vite: {
    resolve: {
      // `@wasm` → the wasm-pack output, so components don't hardcode ../../.. paths.
      alias: { "@wasm": wasmPkg },
    },
    server: {
      // Allow importing the wasm bundle from the repo root (outside apps/web).
      fs: { allow: [repoRoot] },
    },
    worker: {
      // The convert worker is a module worker using top-level await; vite's
      // default IIFE worker format can't express that.
      format: "es",
    },
  },
});
