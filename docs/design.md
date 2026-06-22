> Baseline: `MSH/docs/design.md` (org common rules). Below: Alotno-specific rules.

# Alotno

## Overview
Alotno is a design system for a precision image-conversion tool — PNG to SVG, PDF, EPS, DXF, and WebP — used by designers, developers, and people who care about clean vector output. The aesthetic is calm, exact, and unobtrusive: a near-monochrome slate canvas, generous whitespace, hairline borders, and a single confident indigo accent reserved for actions and active state. The system targets a technical audience that judges a tool by how little it gets in the way: fast, keyboard-friendly, legible at a glance, equally at home in light and dark. Alotno rejects two failure modes common in utility apps: the cluttered "every option visible at once" control panel that overwhelms, and the over-styled marketing-gradient look that feels untrustworthy for precision work. Instead it aims for the quiet confidence of a well-made instrument — think a pro audio plugin or a code editor's settings, not a consumer web app. Numbers (dimensions, file sizes, tolerances) are first-class and always set in mono.

## Colors
- **Indigo** (#6366F1): Primary brand/accent — primary buttons, active tabs, focus, selected options
- **Indigo Strong** (#4F46E5): Hover on primary, active radio/checkbox fill
- **Indigo Deep** (#4338CA): Pressed states, focused-input border
- **Indigo Soft** (#EEF2FF): Tint behind selected items and active option groups
- **Background** (#FFFFFF): Pure white page background (light mode)
- **Surface** (#F8FAFC): Card, panel, and control-group surface
- **Surface Sunken** (#F1F5F9): Inset wells, the dropzone, code/preview backgrounds
- **Surface Elevated** (#FFFFFF): Popovers, dropdowns, modals
- **Ink** (#0F172A): Primary text — near-black slate
- **Ink Muted** (#475569): Secondary text, labels, helper copy
- **Ink Subtle** (#94A3B8): Metadata, units, placeholder, disabled-but-readable
- **Ink Faint** (#CBD5E1): Disabled controls, dividers between dense rows
- **Outline** (#E2E8F0): Card edges, input borders, control separators
- **Outline Strong** (#94A3B8): Focus rings on neutral controls, prominent dividers
- **Success** (#16A34A): Conversion succeeded, valid input
- **Success Soft** (#DCFCE7): Tint behind success rows
- **Error** (#DC2626): Conversion failed, invalid file
- **Error Soft** (#FEE2E2): Tint behind error rows
- **Warning** (#D97706): Lossy/destructive notice, "unsupported" hints

Dark mode is a first-class target (this audience expects it). Dark surfaces invert toward slate: Background #0B1120, Surface #111827, Surface Sunken #0F172A, Ink #E2E8F0, Outline #1E293B; Indigo brightens to #818CF8 for accent so it holds contrast on dark.

## Typography
- **Sans** (Inter, fallback system-ui): everything — UI, labels, body, headings. Tight, neutral, screen-optimized.
- **Mono** (JetBrains Mono, fallback ui-monospace, SF Mono): all numbers, dimensions, file sizes, tolerances, color hex values, code/path snippets.

One sans for the whole interface keeps a utility tool coherent; the mono face does real work, not decoration — it signals "this value is exact." Numerals in data contexts use tabular figures so columns align. Base UI text is 14–15px; never below 12px (captions/units only).

Type scale: H1 28/36 (sans 600), H2 22/30 (sans 600), H3 18/26 (sans 600), Body 15/24 (sans 400), Body Strong 15/24 (sans 600), Label 13/18 (sans 500, slightly tightened), Small 13/18 (sans 400), Caption 12/16 (sans 400), Mono Data 13/20 (mono 500 tabular).

## Elevation
Alotno leans on borders, not shadows. Most surfaces are defined by a 1px outline (#E2E8F0) on a flat fill — no resting shadow. Only floating layers cast light: dropdowns/popovers use a small shadow (0 4px 12px rgba(15, 23, 42, 0.08)) with a 1px outline; modals use 0 16px 40px rgba(15, 23, 42, 0.16) over a subtle backdrop blur. Active/selected option groups are indicated by an indigo 1px border + indigo-soft fill, never by a shadow. Hover on interactive cards is a border-color shift and a 1px lift, not a glow.

Border radius is restrained and consistent: 6px on inputs, checkboxes, small chips; 8px on buttons and segmented controls; 10px on cards and control panels; 14px on modals and the dropzone; 999px only on pills/tags and toggle knobs. Sharper than a consumer app — corners read as "instrument," not "toy."

## Components
- **Dropzone**: The primary input. A surface-sunken area with a 2px dashed outline-strong border, 14px radius, centered icon + "Drop PNGs here, or click to browse." On drag-over: border becomes indigo, fill becomes indigo-soft, 120ms. Accepts multiple files.
- **Button**: Three weights. *Primary* — indigo fill, white text, 8px radius, 36–40px tall, sans 600 14px; hover → indigo-strong; active → indigo-deep, scale 0.98, 100ms. *Secondary* — surface fill, 1px outline, ink text. *Ghost* — no fill/border, ink-muted text, used for "reset/clear." Disabled drops to ink-faint with no fill.
- **Option Group**: The core of the settings panel. A labeled column (label in Label style with an info "ⓘ" affordance) containing radios, checkboxes, or a select. Groups sit in a multi-column grid separated by hairline dividers. A disabled/irrelevant group (e.g. DXF compatibility when DXF isn't selected) dims to ~45% opacity and is non-interactive — present but clearly inert.
- **Radio / Checkbox**: 18px control, 6px radius (checkbox) / circle (radio), 1px outline default; checked → indigo fill + white glyph. Label is Body, ink. Generous 8px gap; whole row is clickable. Multi-line labels wrap with the control top-aligned.
- **Segmented Control**: For 2–4 mutually exclusive choices (e.g. light/dark, mono/posterized). Surface track, 8px radius, the active segment gets a white elevated chip with the small popover shadow and ink text; inactive segments are ink-muted.
- **Slider**: Used for quality, threshold, stroke width, tolerance. 4px track (outline), indigo fill left of the thumb, 16px indigo thumb with a 1px white ring. The current value sits to the right in **Mono Data** style with its unit (e.g. `2.0px`, `82`).
- **Select / Dropdown**: 1px outline trigger, surface fill, 6px radius, chevron in ink-subtle; menu is surface-elevated with the popover shadow, selected row tinted indigo-soft with an indigo check.
- **File Row**: One row per queued file. Filename in Body (truncating middle), then per-format status tags. Tags: pending (ink-subtle, "svg…"), success (success text + check, success-soft tint), error (error text + ×, error-soft tint, hover shows the message). A trailing "Reveal" / "Download" ghost button.
- **Info Popover**: Triggered by the "ⓘ" next to a setting label. Surface-elevated, 10px radius, popover shadow, max-width ~280px, Body text explaining the option in one or two sentences. Opens on click and on keyboard focus — never hover-only.
- **Tag / Pill**: 999px, Caption text. Format tags (SVG, PDF, DXF) use surface fill + ink-muted; an "unsupported / coming later" tag uses warning text on a warning-soft fill.
- **Preview Pane**: A surface-sunken panel showing the rendered result with a subtle checkerboard behind transparency; zoom controls and the output dimensions in Mono Data.
- **Toast**: Bottom, surface-elevated, 10px radius, popover shadow, an accent/success/error left bar, auto-dismiss 4s, with an explicit close.
- **Inputs (text/number)**: 1px outline, surface fill, 6px radius, 8×12px padding, Body text; numeric inputs use Mono. Focus → indigo border + 3px indigo-soft ring. Error → error border + inline message below, never blocking typing.

## Spacing
- Base unit: 4px
- Scale: 4, 8, 12, 16, 20, 24, 32, 48, 64px
- Control density is moderate-tight: 10–12px vertical rhythm inside option groups, 8px between a control and its label.
- Settings grid: multi-column (4–5 columns on desktop) separated by 1px dividers with 24–32px gutters; collapses to a single column under ~720px.
- Container max-width: 1100px for the app shell, 760px for marketing/reading content; 24px horizontal padding desktop, 16px mobile.
- Tap/click target minimum: 32px (pointer) / 44px (touch).

## Motion
Motion is fast and functional — feedback, not flourish. Standard transition is 120ms ease-out (cubic-bezier(0.2, 0, 0, 1)); hovers and color shifts 100ms; popovers/menus fade+scale from 0.98 over 120ms. Sliders and toggles track the pointer 1:1 with no easing. Conversion progress is a determinate bar that fills as files complete — no spinners-for-spinners' sake. There are no celebratory animations (no confetti, no badges) — this is an instrument. The system respects prefers-reduced-motion: all transitions drop to 0–80ms and transform-based motion is removed.

## Iconography
Lucide icon set (already in use), 1.5px stroke, rounded caps/joins, 20px default in ink-muted, 16px in dense rows, 24px in feature contexts. Active/selected icons use indigo. The vocabulary is utilitarian: upload/download, file, image, folder, layers, sliders, check, x, info, chevron, copy, external-link, sun/moon (theme). Icons are geometric and consistent — never illustrated or hand-drawn.

## Accessibility
WCAG AA minimum (4.5:1 body, 3:1 large/UI); primary text targets AAA where feasible. Full keyboard operability: every control reachable and operable by keyboard, visible focus ring (indigo on neutral, outline-strong on indigo) on all interactive elements, logical tab order through the settings grid. Color is never the only signal — success/error states pair color with an icon (check/×) and text. Info popovers open on focus, not hover. Dark mode and a high-contrast variant are supported. Respect prefers-reduced-motion. Form controls have real labels; sliders expose value + unit to assistive tech.

## Voice and Tone
- Precise and calm. "Drop PNGs to convert." Not "Let's get started!"
- Plain, technical, unhyped. "Lossless WebP" — not "Perfect quality, guaranteed!"
- Errors are specific and blameless: "Couldn't read that file — is it a valid PNG?" Not "Oops! Something went wrong."
- Numbers carry meaning: surface dimensions, sizes, and tolerances rather than vague adjectives.
- Explain trade-offs honestly: "EPS is supported; arc-based DXF isn't yet." Never fake a capability.
- Empty states are direct: "No files yet — drop a PNG to begin."

## Do's and Don'ts
- Do reserve indigo for actions and active state — neutrals carry everything else
- Do set every number (size, dimension, tolerance, hex) in the mono face
- Do support light and dark from day one — this audience expects it
- Do keep advanced options grouped and let irrelevant groups dim rather than vanish
- Do pair success/error color with an icon and text
- Do keep motion under ~120ms; it should feel instant
- Don't use gradients, glows, confetti, or reward/badge motifs — this is a tool, not a game
- Don't drop UI text below 12px, or numeric data out of the mono face
- Don't rely on hover-only affordances (info, actions) — keyboard and touch need them too
- Don't overstate capabilities in copy; omit what the engine can't do (see docs/features.md)
- Don't hardcode color/size values in any app — consume the generated tokens (see design/)
