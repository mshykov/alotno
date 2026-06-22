> Baseline: `MSH/docs/developer.md` (org common rules). Below: Alotno-specific rules.

# Developer (Alotno)

## Engine-centric monorepo

- One Rust `core/` is the single conversion engine, compiled to **WASM** (web)
  and exposed via **FFI** (Flutter). Shells never reimplement conversion logic.
- `core/`, `bindings/`, `design/`, and `apps/` change together as one unit.
- `core/` is pure Rust with no platform assumptions; `bindings/` are thin
  pass-throughs (file I/O + UI glue only).

## Design tokens are the single source

- Edit `design/tokens.json`, then run `pnpm --filter @alotno/design build` to
  regenerate CSS / TS / Dart outputs.
- Never hardcode colors or sizes — always consume generated tokens.
- Generated `design/dist/` is git-ignored; never edit it by hand.

## Commits

- Conventional commits. Reference audit findings by code (`H`/`M`/`L`/`C` +
  number) in commit messages, **not** in source comments.

## Dev loop

```
pnpm install
pnpm --filter @alotno/design build
wasm-pack build bindings/wasm --target web --out-dir pkg --release
pnpm --filter @alotno/web dev
```

- Rebuild WASM after any `core/` or `bindings/` change.
- Flutter native: `flutter run -d macos`.
