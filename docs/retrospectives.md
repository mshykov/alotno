# Retrospectives

Working-practice lessons from build sessions — what to keep doing and what to do
differently. Append a dated section per retro. Specific over generic: cite the
PR/commit so the lesson is traceable.

---

## 2026-06-22 — audit → remediation → release cycle

Covered: an L6 audit and full remediation (#27–#44), an icon rebrand, the
desktop sidebar (#53), iOS + mobile polish (#51–#52), SonarCloud integration to
zero issues + ~85% coverage (#55–#64), a Lighthouse a11y pass (#65, #67), a
tech-debt sweep (#68–#71), and the v1.2.0 release prep (#72).

### What was good — keep doing

- **Evidence before assertion.** Every claim was backed by a command: the Sonar
  REST API for the real issue list (not the stale UI count), parsing the
  Lighthouse JSON for exact failing audits, `git` audits for branch/PR state.
  We never "remembered" what a tool said — we asked it.
- **Refusing the destructive shortcut, every time.** Did not bypass branch
  protection with `--admin` (waited for green checks); did not merge the
  38-commits-stale `docs/align-org-conventions` branch (would have reverted
  weeks of work — cherry-picked the one useful piece instead); did not ship an
  un-notarized DMG; did not pull a *beta* `file_picker` to chase a `share_plus`
  major. Each time: surface the trade-off, recommend, let the human decide.
- **One concern per PR, each independently verified.** Analyze + test + build
  green *locally* before push, then wait for required CI checks before merge.
  Squash-merge, delete branch, reset to `origin/main`. Kept history clean and
  every change bisectable.
- **Fix at the source, not the symptom.** A11y contrast was fixed in
  `design/tokens.json` (regenerated for css/ts/dart), not patched per-component;
  the per-format FFI switch was unified into one `writeConverted`.
- **Tests earned their cost.** They caught real bugs before merge — the
  unmodifiable-list crash on the first custom preset, and the completely
  untested PDF export path. Writing tests *found* defects, didn't just guard.
- **Honest signal vs. noise.** Distinguished a real finding from a false
  positive out loud — e.g. the "console error" Lighthouse logged was a Perplexity
  browser-extension font our CSP correctly blocked, not site code. Said so
  rather than "fixing" a non-bug.
- **Caught a latent secret leak.** The `_do_not_commit/` dir wasn't gitignored
  (org convention is `_do-not-commit/`); flagged and fixed before any `git add`
  could stage the Sonar token.

### What went wrong — and the lesson

- **Fixed instances, not the class — twice over.** The a11y link-underline fix
  (#65) scoped underlines to `.foot`/`.sub` and missed the FAQ link, costing a
  second PR (#67) that inverted the rule (underline by default, opt out for
  chrome). **Lesson:** when fixing a *category* of issue ("links rely on
  color"), fix the category — invert the default — don't enumerate the
  instances you can currently see.
- **Didn't anticipate the analyzer needs resolved deps.** The first CI Sonar
  scan reported 1263 issues; ~1197 were false `S2260`s because the Dart analyzer
  had no `package_config` (no `pub get` before the scan). **Lesson:** a static
  analyzer is only as good as its resolved dependency graph — run the package
  manager before the scan.
- **Designed around a platform feature without checking the plan.** Spent
  several rounds discovering SonarCloud's free tier locks the quality gate to
  "Sonar way" (custom gates are paid; assignment 403'd) and ignores fixed-date
  leak periods. **Lesson:** verify the plan/tier limits of a SaaS feature
  *before* building a workflow that depends on it.
- **Preflighted a credential at the end instead of the start.** The v1.2.0
  release (#72) merged the version bump, then blocked: the `alotno-notary`
  notarization profile was missing from the keychain (a user-only,
  app-specific-password setup). **Lesson:** for any multi-step deliverable with
  an external/credential dependency, **preflight the prerequisite first** — fail
  fast before doing the dependent work.
- **Rediscovered the same test-harness trap repeatedly.** Async `dart:io`
  futures never resolve inside the widget-test fake-async zone — hit 3+ times
  (mobile intake, settings sheet) before it was written down. Now captured in
  [testing.md](testing.md). **Lesson:** the moment a non-obvious harness gotcha
  costs a second debugging round, document it immediately.
- **A merge raced its own CI report.** An early merge attempt read `OPEN`
  because checks hadn't reported yet; a re-poll fixed it. **Lesson:** poll
  required checks to `pass` before attempting the merge, don't merge-then-hope.

### Carry-forward backlog (not code — needs a human)

- Rotate the Sonar token in `_do_not_commit/` from admin scope to analysis scope
  (nothing automated needs admin anymore).
- Store the `alotno-notary` credential, then finish the v1.2.0 macOS release
  (notarized DMG + GitHub release). See [releasing-macos.md](releasing-macos.md).
