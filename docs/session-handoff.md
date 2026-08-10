# Session handoff — audit remediation & dependency modernization

Working context carried over from an agent session so the next one can resume
without re-deriving anything. **Baseline commit: `901e1aa`** (`main`, clean tree,
CI green). Delete or rewrite this file once the outstanding items below are done.

---

## 1. Orientation (30 seconds)

Alotno is a local-first PNG→vector converter. The *product* is the converter; the
*point* is that two assets are authored once and everything else consumes them:

1. **`core/`** — the whole conversion engine, pure Rust. Compiles to **WASM**
   (`bindings/wasm` → `apps/web`) **and** native **FFI** (`apps/app/rust` via
   flutter_rust_bridge → `apps/app`).
2. **`design/tokens.json`** — generates `tokens.css` / `.ts` / `.dart`.

Hard rules (see [architecture.md](architecture.md), [developer.md](developer.md)):
conversion logic lives **only** in `core/`; styling lives **only** in
`tokens.json`; shells do file I/O + UI only. The core is **panic-free by
contract** — it ships `panic = "abort"`, so a panic poisons the WASM module /
aborts the FFI host.

---

## 2. What landed (all merged to `main`)

| PR | What |
|---|---|
| [#75](https://github.com/mshykov/alotno/pull/75) | social preview metadata |
| [#76](https://github.com/mshykov/alotno/pull/76) | `/.well-known/security.txt` |
| [#77](https://github.com/mshykov/alotno/pull/77) | optimized `icon-208.png` for visible page icons |
| [#78](https://github.com/mshykov/alotno/pull/78) | gitignore per-developer AI assistant artifacts (incl. `AGENTS.md`) |
| [#79](https://github.com/mshykov/alotno/pull/79) | **architecture + SecOps audit remediation** (see §3) |
| [#80](https://github.com/mshykov/alotno/pull/80) | vitest 2.1.9 → 3.2.6 |
| [#82](https://github.com/mshykov/alotno/pull/82) | CSP: pin inline theme scripts by `sha256`, drop `script-src 'unsafe-inline'` |
| [#83](https://github.com/mshykov/alotno/pull/83) | drift guard test for those CSP hashes |
| [#84](https://github.com/mshykov/alotno/pull/84) | ignore `RUSTSEC-2026-0206` (rustybuzz) — unblocked all CI |
| [#85](https://github.com/mshykov/alotno/pull/85) | **Astro 5.18.2 → 6.4.8** + CI/deploy Node 20 → 22 |
| [#86](https://github.com/mshykov/alotno/pull/86) | tokio 1.34 → 1.52 (FFI crate lockfile) |
| [#87](https://github.com/mshykov/alotno/pull/87) | align `@vitest/coverage-v8` with vitest 3; gitignore `coverage/` |

[#81](https://github.com/mshykov/alotno/pull/81) (Dependabot's naive Astro 6 bump)
was **closed** in favour of the deliberate migration in #85.

### Also resolved outside of git

- **Production outage.** `alotno.app` was serving an empty **404**. Cause: a
  **second, independent deploy path** — Cloudflare Pages' *native* Git
  integration was connected *alongside* `.github/workflows/deploy-web.yml`. It
  built commit `562c96d` (a `.gitignore`-only change that the path-filtered
  workflow correctly skipped) with no Rust/WASM/tokens pipeline, produced an
  empty output, and — being the newest deployment — was promoted to production,
  overriding the good wrangler deploy. Fixed by re-running
  `gh workflow run deploy-web.yml --ref main`, then permanently by
  **disconnecting the Git integration** in the Pages dashboard. Verified: the
  "Cloudflare Pages" check no longer appears on PRs.

---

## 3. Audit findings — status

An architecture + SecOps audit was run across four surfaces. Findings were coded
and remediated in #79/#82/#83. **Per [developer.md](developer.md), reference these
codes in commit messages, never in source comments.**

| Code | Sev | Finding | Status |
|---|---|---|---|
| **H1** | High | `hex_to_rgb` (eps.rs) guarded on **byte** length then **byte**-sliced → multibyte fill (`#€€`) sliced mid-codepoint → **panic** (fatal under `panic="abort"`). Reproduced, then fixed by rejecting non-ASCII-hex before slicing. Root cause of the miss: proptests fuzzed the `d` attribute but hardcoded `fill="#000000"`. | ✅ fixed |
| **O1** | High | Dual deploy path (see §2). | ✅ fixed (dashboard) |
| **M1** | Med | `MAX_PIXELS = 100M` too generous for wasm32 — 400 MB RGBA, and the trace pipeline peaks at several multiples (`to_color_image` clones the whole buffer; `binarize` allocates another). A max-legal image can still exhaust wasm32 memory → `handle_alloc_error` → abort. | ⬜ **open** |
| **M2a** | Med | No advisory scanning. Added `cargo deny check advisories` for **both** workspaces + `deny.toml`; fixed the real vuln `RUSTSEC-2026-0204` (crossbeam-epoch → 0.9.20) in both lockfiles. | ✅ fixed |
| **M2b** | Med | `vtracer` drags advisory-flagged deps (`clap 2`→`atty`/`ansi_term`, `image 0.23`→`adler`) into the WASM build. | ⬜ **open** (see §4) |
| **S1** | Med | `script-src 'unsafe-inline'`. | ✅ fixed |
| **S2** | Med | No HSTS. | ✅ fixed |
| **O2** | Med | Floating `npx wrangler@3` running with `CLOUDFLARE_API_TOKEN`. Pinned to `3.114.17`. | ✅ fixed |
| **L1** | Low | Unvalidated `stroke_width` / WebP `quality` (NaN/inf/negative → `stroke-width="NaN"` in output). Sanitized at the `OptionsDto` boundary and the core encode dispatch. | ✅ fixed |
| **L2** | Low | `tokenize()` allocated a `String` per token (~10× amplification for a hostile `d`). Now borrows `&str`. | ✅ fixed |
| **W1** | Low | `logo.png` + `logo.PNG` collided in the output map/ZIP and one silently overwrote the other (queue dedup is case-sensitive, the `.png` strip is not). Colliding names now suffixed `logo (2).svg`. | ✅ fixed |
| **I1** | Info | Panic contract enforced by review only. Added `clippy::{unwrap_used, expect_used, panic}` crate-wide, `cfg(test)`-exempt. | ✅ fixed |

### Verified strengths (checked against code, not docs)

- **"Nothing is uploaded" holds.** Zero `fetch`/`XHR`/`sendBeacon`/analytics in
  `apps/web`; the only network call is wasm-bindgen fetching its own `.wasm`,
  same-origin, and `connect-src 'self'` blocks anything else.
- **No DOM-injection surface** — filenames render via `textContent`; the sole
  `set:html` is static JSON-LD.
- **Decode caps are enforced before allocation**; `parse_path` is total (2000-case
  fuzz); stroke-colour injection is allowlisted and tested; bindings are genuinely
  thin; **zero `unsafe`** in `core/`, `bindings/wasm/`, `apps/app/rust/src/api/`.

---

## 4. Outstanding work

### 4.1 Never audited — real coverage gap ⚠️

Two of the four audit agents died on a session usage limit and their surfaces
were **never covered**:

- **`apps/app` (Flutter shell + FFI boundary)** — completely unaudited. Unknowns:
  FFI panic/abort behaviour on the desktop/mobile host, path traversal when
  batch-writing user-controlled filenames, **macOS entitlements vs. the
  "100% local" promise** (is `com.apple.security.network.client` enabled and does
  anything need it?), iOS `Info.plist` permissions, Android manifest,
  telemetry/analytics sweep, hardcoded colours violating the token rule.
- **CI/CD + supply chain** — was written up from first-hand session evidence
  (which is solid on what was directly observed) but never got a dedicated pass.
  A real one should check workflow `permissions:` blocks, `${{ }}` script
  injection, cache poisoning, and the `build-wasm` composite action.

### 4.2 M2b — replace `vtracer`

Verified constraints: **vtracer 0.6.5 is the latest** release, and **`clap` +
`image 0.23` are hard, unconditional deps** (only `pyo3` is optional) — so
`default-features = false` cannot drop them. The conversion lives in vtracer's
`src/converter.rs` (~237 lines) calling **`visioncortex 0.8.8`, already a direct
dependency**. Plan:

1. Branch; **build the golden-output harness FIRST, while vtracer is still in** —
   run the current `vtracer::convert` over ~5–10 fixture PNGs (logo, photo, mono,
   gradient) and commit the SVG outputs as goldens. This is the regression oracle.
2. Port `converter.rs` + `svg.rs` onto `visioncortex` directly (new
   `core/src/vector/trace_impl.rs`), mapping the existing `Config`/`ColorMode`/
   `Hierarchical` (already mirrored in `core/src/vector/trace.rs`).
3. Swap the call at `core/src/vector/trace.rs` (`vtracer::convert(...)`), remove
   `vtracer` from `core/Cargo.toml` + root `Cargo.toml`.
4. Run the harness — output must match. Byte-identical is ideal; otherwise assert
   structural equivalence (path count, bounding box) and eyeball a few.
5. `cargo tree` to confirm `clap`/`atty`/`ansi_term`/`image 0.23`/`adler` are gone,
   then **remove the now-stale ignores from `deny.toml`** (`cargo-deny` errors on
   stale ignores, which forces this). `ttf-parser` + `rustybuzz` stay — they come
   via `svg2pdf`.
6. Verify: tests + clippy + wasm32 build; the WASM payload should shrink.

Lighter alternatives: fork vtracer and feature-gate `clap`/`image` behind a
non-default `cli` feature, or upstream that as a PR to `visioncortex/vtracer`.

### 4.3 Open Dependabot PR — needs a decision

- **[#88](https://github.com/mshykov/alotno/pull/88) astro 6.4.8 → 7.1.0.**
  Another **breaking major**, days after the 5→6 migration. Do *not* auto-merge:
  repeat the §5 migration checklist, especially the **CSP hash re-verification**.
  Check whether Astro 7 raises the minimum Node again (6 required ≥ 22.12; CI is
  now on 22).

### 4.4 Smaller / non-code

- **`astro6-preview` Pages deployment** left over from migration verification.
  Wrangler v3 `pages deployment` has only `list`/`tail` — **no CLI delete**.
  Remove via *Workers & Pages → alotno → Deployments → `astro6-preview` → ⋯ →
  Delete*. Harmless if left.
- **M1** (§3) — lower `MAX_PIXELS` to ~40–50M or make it `target_arch`-conditional,
  and drop the full-buffer clone in `to_color_image`.
- **Deferred clippy lints** — `clippy::indexing_slicing` / `clippy::string_slice`
  are *not* enabled; ~30 verified-total slice sites would each need `#[allow]`.
  Rationale is recorded in `core/src/lib.rs`. `string_slice` is what would have
  caught H1.
- **Carry-forward from the June retro** (still open): rotate the Sonar token in
  `_do_not_commit/` from admin → analysis scope; store the `alotno-notary`
  credential and finish the **v1.2.0 macOS notarized release** (latest GitHub
  release is still v1.1.0).
- **No retrospective entry** has been written for this session in
  [retrospectives.md](retrospectives.md) — the convention is a dated section per
  session. Lessons worth recording are in §6.

---

## 5. The CSP hash mechanism (read before touching `index.astro`)

`apps/web/public/_headers` pins the **two `is:inline` theme scripts** in
`src/pages/index.astro` (theme-before-paint + toggle) by `sha256`, instead of
`'unsafe-inline'`. `style-src` still needs `'unsafe-inline'` for Astro's scoped
styles.

- Astro emits `is:inline` **verbatim**, so the hash of the *source* body equals
  the hash the browser enforces — confirmed true on both Astro 5 and 6.
- `apps/web/src/csp-script-hashes.test.ts` recomputes the hashes from
  `index.astro?raw` and asserts `_headers` still lists them, so **editing a theme
  script without updating the CSP fails CI** instead of silently refusing to run
  the script in production.
- Recompute hashes from the built output:
  ```bash
  pnpm --filter @alotno/web build
  node -e 'const fs=require("fs"),c=require("crypto");
    const h=fs.readFileSync("apps/web/dist/index.html","utf8");
    const re=/<script(?![^>]*application\/ld\+json)[^>]*>([\s\S]*?)<\/script>/g;let m;
    while((m=re.exec(h))){const b=m[1];if(!b.trim())continue;
      console.log("sha256-"+c.createHash("sha256").update(b,"utf8").digest("base64"));}'
  ```
- **The CSP is enforced only by Cloudflare Pages** — `astro dev`/`preview` do not
  apply `_headers`. Any CSP change must be verified on a real preview deploy:
  ```bash
  npx --yes wrangler@3.114.17 pages deploy apps/web/dist --project-name=alotno --branch=<name>
  ```
  Then check the browser console for zero CSP violations and confirm the theme
  toggle still flips `data-theme` and persists to `localStorage`.

---

## 6. Operational lessons from this session

- **The advisory gate has a live-DB tradeoff.** `cargo deny` reads the RUSTSEC DB
  at run time, so a newly-published advisory turns CI red on **unrelated** PRs
  (`rustybuzz` did exactly this, blocking everything until #84). That's the gate
  working — but expect occasional "document the new ignore" maintenance, and fix
  it centrally on `main` first rather than per-PR.
- **Never ignore a real vulnerability in `deny.toml`.** The policy encoded there:
  vulnerabilities get *fixed* (crossbeam-epoch was bumped), only
  *unmaintained*-class advisories on unused transitive deps get ignored, each with
  provenance verified by `cargo tree -i`.
- **Two Cargo workspaces exist.** The root (engine + bindings) and the standalone
  `apps/app/rust` FFI crate, which has **its own `Cargo.lock`** the root scan
  cannot see. Both needed the crossbeam-epoch fix; CI now scans both.
- **`SonarCloud` is *not* a required check** — only `Rust core (test + wasm)` and
  `Web (tokens + Astro build)` are. A red Sonar does not block a merge; several
  transient Sonar failures cleared themselves on rebase.
- **Squash-merges leave local branches looking "unmerged"** by ancestry. Compare
  *content* (`git diff origin/main..branch --shortstat`, `git cherry`) before
  deleting, not just `git branch --merged`.
- **Order matters when PRs touch the same file.** Merging #76 first made #77
  conflict on `raw-imports.d.ts`; #80 landing made #85 conflict on
  `package.json`/`pnpm-lock.yaml`. Both were additive — resolution was the union
  plus a regenerated lockfile (`git checkout main -- pnpm-lock.yaml && pnpm install`).
- **A stale branch can be worse than useless.** `docs/self-contained-docs` (1
  commit, 18 behind, −2155 lines) was **deleted**: its stated goal was already met
  on `main`, and merging it would have deleted `csp-script-hashes.test.ts`,
  `headers.test.ts`, `deny.toml`, `security.txt`, `icon-208.png` and reverted
  `CLAUDE.md`/CI. Recoverable at `e796bb8` via reflog if ever needed.
- **Reproduce before fixing.** H1 was written as a failing test first; proptest
  shrank it to a minimal counterexample (`fill = "#𐀀…"`), which is what proved the
  bug was real rather than theoretical. The seed is committed at
  `core/tests/path_parsers.proptest-regressions`.

---

## 7. Verification cheat-sheet

```bash
# Rust (mirrors the required CI job)
cargo fmt --all --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace --all-features          # incl. the 2000-case parser fuzz
cargo deny check advisories
cargo deny --manifest-path apps/app/rust/Cargo.toml check advisories
cargo check -p alotno-wasm --target wasm32-unknown-unknown
cargo test --manifest-path apps/app/rust/Cargo.toml

# Web
pnpm install
pnpm --filter @alotno/design build             # tokens first — the build needs them
wasm-pack build bindings/wasm --target web --out-dir pkg --release
pnpm --filter @alotno/web test                 # 20 tests
pnpm --filter @alotno/web check                # astro check — expect 0 errors, 1 pre-existing hint
pnpm --filter @alotno/web build

# Deploy (the ONLY sanctioned path — never re-add a second one)
gh workflow run deploy-web.yml --ref main
```

`cargo-deny` is pinned to `0.19.9` in CI so advisory results don't drift.
