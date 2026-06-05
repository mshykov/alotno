# Running Alotno locally

All commands run from the repo root unless noted.

## Prerequisites

Already required and present on this machine: **Node 20+**, **pnpm**, **git**.

Install once for the conversion engine:

```sh
# Rust + the browser compile target
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"
rustup target add wasm32-unknown-unknown

# wasm-pack (compiles the core to a browser bundle)
cargo install wasm-pack
```

(Flutter is only needed later for the desktop/mobile app — not for the web run.)

---

## Full web app (marketing page + working converter)

```sh
# 1. Install JS dependencies
pnpm install

# 2. Generate design tokens (CSS/TS/Dart from design/tokens.json)
pnpm --filter @alotno/design build

# 3. Build the Rust core → WASM bundle (outputs bindings/wasm/pkg/)
wasm-pack build bindings/wasm --target web --out-dir pkg --release

# 4. Run the dev server
pnpm --filter @alotno/web dev
```

Open the URL Astro prints (default **http://localhost:4321**). Drop a PNG and
convert to SVG / PDF / EPS / DXF / WebP — everything runs in the browser via WASM.

### Rebuild loop
- Changed `design/tokens.json`? → re-run step 2.
- Changed anything in `core/` or `bindings/wasm/`? → re-run step 3.
- Astro hot-reloads `apps/web/` automatically.

---

## Just the marketing page (no Rust needed)

Skip steps 1 (still run it) and 3. The page loads fine; the converter shows
"engine not built yet" until you build the WASM bundle.

```sh
pnpm install
pnpm --filter @alotno/design build
pnpm --filter @alotno/web dev
```

---

## Core engine only (Rust)

```sh
cargo test  -p alotno-core              # unit tests (decode, webp roundtrip)
cargo build -p alotno-core --release    # native build
cargo build -p alotno-core --features libwebp   # with libwebp lossy WebP
(cd apps/app/rust && cargo check)       # verify the Flutter FFI binding compiles
cargo doc   -p alotno-core --open       # browse the API
```

> First Rust build may surface crate-API mismatches (`vtracer`, `svg2pdf`/`usvg`,
> `image-webp`) — these are pinned but unverified. Fix any signature errors the
> compiler points to; the module structure won't change.

---

## Production web build (what Cloudflare Pages runs)

```sh
pnpm --filter @alotno/design build
wasm-pack build bindings/wasm --target web --out-dir pkg --release
pnpm --filter @alotno/web build      # outputs apps/web/dist/
pnpm --filter @alotno/web preview    # serve the built site locally
```

---

## Legacy Electron prototype (reference only)

```sh
cd legacy/electron-mac && npm install && npm start
```
Not part of the new build; kept for reference until the Flutter app reaches parity.
