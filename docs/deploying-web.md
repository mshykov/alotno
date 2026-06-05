# Deploying the web app (Cloudflare Pages → alotno.app)

The site is a static Astro build whose converter loads the **Rust→WASM** bundle.
Because the build needs Rust + `wasm-pack`, the simplest, most reliable approach is
**build locally and upload the static output** with Wrangler. (A fully automatic
git-integration option is at the bottom, with its caveat.)

Cloudflare Pages free tier: unlimited bandwidth/requests, free SSL + custom domain.

## One-time setup

```sh
npm i -g wrangler            # Cloudflare CLI
wrangler login              # opens the browser to authorize your CF account
wrangler pages project create alotno --production-branch main
```

Then point the domain (one-time):
- Cloudflare dashboard → **Workers & Pages → alotno → Custom domains → Set up a
  custom domain** → `alotno.app` (and optionally `www.alotno.app`).
- Since DNS is already on Cloudflare, the records are added automatically; SSL is
  issued in a minute.

## Deploy (each release)

```sh
scripts/deploy-web.sh
```

That runs: design tokens → `wasm-pack build` → `astro build` → `wrangler pages
deploy apps/web/dist`. The command prints a unique preview URL plus the production
URL; once the custom domain is attached, `main` deploys go live at **alotno.app**.

Manual equivalent:
```sh
pnpm --filter @alotno/design build
wasm-pack build bindings/wasm --target web --out-dir pkg --release
pnpm --filter @alotno/web build
npx wrangler pages deploy apps/web/dist --project-name alotno --branch main
```

## Alternative: automatic git deploys (optional)

Connect the repo in **Pages → Create → Connect to Git** for auto-deploy on push.
The catch: Cloudflare's build container has Node but **not Rust**, so the WASM step
must install it. Configure:

- **Root directory:** repo root
- **Build command:**
  ```sh
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    && source "$HOME/.cargo/env" && rustup target add wasm32-unknown-unknown \
    && cargo install wasm-pack \
    && corepack enable && pnpm install \
    && pnpm --filter @alotno/design build \
    && wasm-pack build bindings/wasm --target web --out-dir pkg --release \
    && pnpm --filter @alotno/web build
  ```
- **Build output directory:** `apps/web/dist`

This works but each build recompiles `wasm-pack` (slow, several minutes). For a
solo project, the local `scripts/deploy-web.sh` is faster and simpler — prefer it
unless you want push-to-deploy.

## Notes
- The repo can stay **private**; Wrangler upload doesn't expose it. (Git
  integration would require granting Cloudflare access to the private repo.)
- `wrangler` reads auth from `wrangler login`; nothing secret is committed.
