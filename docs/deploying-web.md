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

## Automatic deploys (GitHub Actions) — recommended

[`.github/workflows/deploy-web.yml`](../.github/workflows/deploy-web.yml) deploys
to Cloudflare Pages on every push to `main` that touches the web app / core /
bindings / design. It builds Rust→WASM in the runner (so Cloudflare doesn't need
Rust) and uploads via Wrangler.

**One-time: add two repo secrets** (Settings → Secrets and variables → Actions):
- `CLOUDFLARE_API_TOKEN` — create at *Cloudflare → My Profile → API Tokens →
  Create Token*, with the **"Cloudflare Pages: Edit"** permission.
- `CLOUDFLARE_ACCOUNT_ID` — *Cloudflare dashboard → Workers & Pages → Account ID*
  (right sidebar).

After that, merging to `main` auto-deploys. You can also trigger it manually from
the Actions tab (workflow_dispatch). The local `scripts/deploy-web.sh` remains for
ad-hoc deploys.

> The Pages project (`alotno`) must already exist (it does). The workflow deploys
> to its `main` branch = production.

## Notes
- The repo can stay **private**; Wrangler upload doesn't expose it. (Git
  integration would require granting Cloudflare access to the private repo.)
- `wrangler` reads auth from `wrangler login`; nothing secret is committed.
