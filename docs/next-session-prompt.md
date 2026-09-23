# Next-session prompt

Paste one of the blocks below into a fresh Claude Code session opened in the
repo root. Full background lives in [session-handoff.md](session-handoff.md).

---

## A. Generic resume (start here if unsure)

```text
Read docs/session-handoff.md first — it's the handoff from the previous session
and contains the current state, what already landed, and the outstanding work.

Then confirm the live state yourself rather than trusting the doc (it may be
stale): `git status -sb`, `git log --oneline -5`, `gh pr list --state open`.

Ground rules for this repo:
- Conversion logic goes ONLY in core/ (Rust); styling ONLY in design/tokens.json.
  Shells (apps/*) do file I/O + UI only.
- core/ is panic-free by contract (panic = "abort" — a panic poisons the WASM
  module / aborts the FFI host). No unwrap/expect/indexing on input-derived data.
- Reference audit codes (H1, M2b, …) in commit messages, NOT in source comments.
- One concern per PR. Verify locally (fmt + clippy -D warnings + tests + both
  cargo-deny scans + wasm32 build; web tests + astro check) BEFORE pushing, then
  wait for the required checks — `Rust core (test + wasm)` and
  `Web (tokens + Astro build)` — to pass. SonarCloud is NOT required.
- Never bypass branch protection. Never add a second deploy path: the only
  sanctioned deploy is .github/workflows/deploy-web.yml (wrangler upload).
- Don't push or commit unless I ask.

Tell me what you find and what you recommend doing first — don't start changing
things yet.
```

---

## B1. Close the audit gap — `apps/app` (Flutter + FFI) *(recommended first)*

```text
Read docs/session-handoff.md, section 4.1.

Two audit surfaces were never covered because the agents died on a usage limit:
(1) apps/app — the Flutter shell + its FFI boundary, and (2) a dedicated CI/CD +
supply-chain pass (see prompt B2). Run a proper security + architecture audit of
apps/app now.

Cover at minimum:
- apps/app/rust: confirm it's a thin pass-through to core (no duplicated
  conversion logic); how errors cross the flutter_rust_bridge boundary; panic
  behaviour on the native host given core builds panic="abort"; any unsafe
  outside generated bridge code.
- File I/O: output path construction from user-controlled filenames (path
  traversal on batch write?), overwrite behaviour, temp files, symlinks.
- macOS entitlements: is the app sandboxed, and is
  com.apple.security.network.client enabled? The product promise is "100% local,
  nothing uploaded" — flag any network entitlement and whether anything needs it.
- iOS Info.plist permissions; Android manifest permissions (that target is
  build-unverified per docs/roadmap.md).
- Telemetry sweep: grep for http/firebase/sentry/analytics — there should be zero.
- pubspec.yaml/lock: pinning discipline, risky or unmaintained packages.
- Design-token rule: spot-check for hardcoded colours/sizes instead of
  tokens.dart.

Verify every claim against the actual code — do not take docs at face value.
Report findings as a ranked list (severity, file:line, why it matters, concrete
fix) plus a short list of strengths you actually confirmed. Don't change code yet.
```

---

## B2. Close the audit gap — CI/CD + supply chain

```text
Read docs/session-handoff.md, sections 4.1 and 6.

The CI/CD and supply-chain surface was written up from a previous session's
first-hand observations but never got a dedicated audit pass. Do that now, for
.github/ (ci.yml, deploy-web.yml, the build-wasm composite action), scripts/,
sonar-project.properties, both Cargo workspaces, and the pnpm workspace.

Cover at minimum:
- Workflow security: trigger types (any pull_request_target / workflow_run?);
  whether each job sets an explicit `permissions:` block or inherits a broad
  default GITHUB_TOKEN; ${{ }} interpolation of untrusted input (PR titles,
  branch names) into `run:` steps (script injection); cache poisoning;
  artifact handling between the wasm and web jobs.
- Secrets: confirm secrets are only in the env of steps that need them and are
  never passed as CLI args or echoed. NEVER print a secret value — names only.
  Do not read anything under _do_not_commit/.
- Third-party actions: verify every `uses:` is pinned to a full commit SHA, and
  that pinned tool versions (cargo-deny, wrangler) are exact, not floating.
- Dependency/lockfile integrity: --frozen-lockfile and --ignore-scripts
  everywhere; pubspec `--enforce-lockfile`; is Dependabot configured for actions,
  npm AND cargo? Read .github/actions/build-wasm and flag any curl|sh installs.
- Release path: scripts/release-macos.sh — signing/notarization credential
  handling, and whether the release is built from a tag checkout or a dirty
  working tree.
- Repo hygiene: branch protection settings (query them), presence of
  SECURITY.md / CODEOWNERS / CONTRIBUTING.md, license consistency.

Note the known-good baseline so you don't re-report it: actions ARE SHA-pinned,
CI installs with --frozen-lockfile --ignore-scripts, cargo-deny is pinned to
0.19.9 and scans both workspaces, wrangler is pinned to 3.114.17, and the
duplicate Cloudflare-native deploy path has been disconnected.

Verify every claim against the actual files. Report a ranked list (severity,
file:line, why it matters, concrete fix) plus strengths you actually confirmed.
Don't change anything yet.
```

---

## C. M2b — replace `vtracer`

```text
Read docs/session-handoff.md, section 4.2, and follow that plan.

The critical constraint: this changes the trace code path, which changes
conversion OUTPUT — the core promise is "identical output everywhere". So build
the golden-output harness FIRST, while vtracer is still a dependency, and treat
it as the acceptance gate. If output can't be shown equivalent, stop and tell me
rather than accepting a diff.

Work on a branch. Don't push until the harness passes and I've seen the results.
```

---

## D. Astro 7 (open Dependabot PR #88)

```text
Read docs/session-handoff.md, sections 4.3 and 5.

Dependabot PR #88 bumps astro 6.4.8 → 7.1.0 — another breaking major, right
after the 5→6 migration. Assess it properly: read Astro's 6→7 upgrade guide,
check whether the minimum Node rises again (CI is on 22 now), then migrate
deliberately rather than merging the bump.

Section 5 is mandatory reading: the CSP in apps/web/public/_headers pins the two
is:inline theme scripts by sha256. If Astro 7 changes how is:inline is emitted,
those hashes break and the theme scripts silently stop executing in production.
Re-verify the hashes from the built dist/, and verify on a real Cloudflare Pages
preview deploy (astro dev/preview does NOT apply _headers) — zero console CSP
violations, theme toggle works.
```

---

## E. Housekeeping backlog

```text
Read docs/session-handoff.md, section 4.4, and work through the smaller items
one at a time, verifying each before moving on:

- M1: MAX_PIXELS is too generous for wasm32 (100M px = 400MB RGBA, and the trace
  pipeline peaks at several multiples). Lower it to ~40–50M or make it
  target_arch-conditional, and remove the full-buffer clone in to_color_image.
- Write the missing retrospective entry in docs/retrospectives.md for the
  previous session (lessons are in section 6 of the handoff) — the convention is
  a dated section per session.
- Decide on the deferred clippy lints (indexing_slicing / string_slice): either
  adopt them with #[allow] on the ~30 verified-total slice sites, or record the
  decision to keep them off.

Two items need me, not you: rotating the Sonar token in _do_not_commit/ from
admin to analysis scope, and storing the alotno-notary credential to finish the
v1.2.0 macOS notarized release. Remind me of both.
```
