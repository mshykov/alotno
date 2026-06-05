# `alotno-wasm`

WebAssembly binding that lets the web app call the Rust core from JavaScript.

## Build

```sh
# from repo root
wasm-pack build bindings/wasm --target web --out-dir pkg --release
```

This emits `bindings/wasm/pkg/` (JS glue + `.wasm`). The web app imports it:

```js
import init, { pngToSvg, pngToPdf, pngToEps, pngToWebp } from "@alotno/wasm";

await init();
const opts = { preset: "high", colorMode: "color", curveType: "curves" };
const svg  = pngToSvg(bytes, opts);            // string
const pdf  = pngToPdf(bytes, opts);            // Uint8Array
const eps  = pngToEps(bytes, opts);            // string
const webp = pngToWebp(bytes, 82, /*lossless*/ true); // Uint8Array — lossless works here
```

The web app references this package via a `pnpm` workspace path (see
`apps/web/package.json`). `pkg/` is git-ignored — it's a build artifact, produced
in CI and locally on demand.
