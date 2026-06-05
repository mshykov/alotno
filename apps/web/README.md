# `@alotno/web`

The marketing landing page **and** the in-browser converter, built with Astro.
Static output — deploys to Cloudflare Pages, no backend, files never leave the tab.

## Develop

```sh
# 1) generate design tokens (once, or when tokens change)
pnpm --filter @alotno/design build

# 2) build the WASM core (once, or when core/ changes)
wasm-pack build bindings/wasm --target web --out-dir pkg --release

# 3) run the site
pnpm --filter @alotno/web dev
```

If you skip step 2, the page still loads — the converter just shows a "engine not
built yet" message until the WASM bundle exists.

## How it consumes the foundation

- **Design:** `import "@alotno/design/css"` pulls in the generated CSS variables;
  every style references `var(--…)`. No hardcoded colors/sizes.
- **Engine:** the converter dynamically imports `bindings/wasm/pkg/` (the
  wasm-pack output) for **every** conversion — SVG, PDF, and WebP (incl. lossless)
  all run in the WASM core, so web output matches the native apps exactly.

## Deploy (Cloudflare Pages)

- Build command: `pnpm --filter @alotno/design build && wasm-pack build bindings/wasm --target web --out-dir pkg --release && pnpm --filter @alotno/web build`
- Output dir: `apps/web/dist`
- Point the `alotno.app` DNS (already on Cloudflare) at the Pages project.
