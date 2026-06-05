#!/usr/bin/env bash
#
# Build the web app (design tokens → WASM core → Astro) and deploy the static
# output to Cloudflare Pages.
#
# ONE-TIME (see docs/deploying-web.md):
#   npm i -g wrangler && wrangler login
#   wrangler pages project create alotno --production-branch main
#   (then add the custom domain alotno.app in the Pages dashboard)
#
# Usage:  scripts/deploy-web.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
source "$HOME/.cargo/env" 2>/dev/null || true

echo "▸ design tokens";       pnpm --filter @alotno/design build
echo "▸ WASM core";           wasm-pack build bindings/wasm --target web --out-dir pkg --release
echo "▸ static site (Astro)"; pnpm --filter @alotno/web build
echo "▸ deploy to Cloudflare Pages";
npx wrangler pages deploy apps/web/dist --project-name alotno --branch main

echo ""
echo "✅ Deployed. Production URL is shown above; custom domain → alotno.app (one-time, in the dashboard)."
