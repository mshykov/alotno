# `@alotno/design`

The one design language. The human-readable spec is [`../DESIGN.md`](../DESIGN.md)
(the "Alotno" system — calm, technical, indigo-on-slate, light + dark); the
machine source is [`tokens.json`](tokens.json), generated from it. Every color,
font size, space, and radius lives in `tokens.json`. Nothing in any app hardcodes
a hex value or a pixel — they all consume generated tokens, so the UIs literally
cannot drift.

> When DESIGN.md and tokens.json disagree, DESIGN.md is the intent and tokens.json
> must be updated to match. Keep them in sync.

## Workflow

1. Edit [`tokens.json`](tokens.json).
2. Regenerate:
   ```sh
   pnpm --filter @alotno/design build
   ```
3. Outputs land in `dist/` (git-ignored — regenerated in CI):
   | File | Consumed by |
   |---|---|
   | `dist/tokens.css` | `apps/web` (imported globally) |
   | `dist/tokens.ts` | `apps/web` (typed access) |
   | `dist/tokens.dart` | `apps/app` — copy/symlink into `lib/design/tokens.dart` |

## Conventions

- Numbers under `font.size`, `space`, and `radius` are unitless in JSON and
  rendered as `px` (CSS) / `double` (Dart).
- Metadata keys start with `$` and are stripped from all output.
- Treat generated files as build artifacts — never edit them; edit the JSON.
