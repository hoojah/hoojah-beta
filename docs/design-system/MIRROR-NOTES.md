# Mirror notes

Local mirror of the Claude Design project **Hoojah Design System**
(`d6e14421-12ce-483a-af8f-b25e58f4852e`), pulled 2026-08-14.

The design system was generated **from this repository** — `readme.md` names
`hoojah-beta/` as its source and `app/assets/tailwind/application.css` +
`app/views/**` as ground truth. Treat it as a codification of conventions this
app already has, not as an external redesign.

## What is mirrored

| Path | Status |
| --- | --- |
| `readme.md` | full — the design law, read this first |
| `styles.css`, `tokens/*.css` | full — all 72 custom properties |
| `components/**/*.prompt.md` | full (all 40) — intent, variants, verbatim product copy |
| `components/core/*.jsx`, `components/debate/*.jsx` | full — the primitives with no ERB equivalent |
| `assets/logo.svg`, `pinned-tab.svg`, `loading.svg` | full |
| `ui_kits/web/README.md` | full — the component→ERB-view mapping table |

## What is NOT mirrored (fetch on demand via the `DesignSync` MCP tool)

- `components/**/*.d.ts` (40) — TypeScript types, no bearing on ERB
- `components/{navigation,voting,hujah,social,forms,analytics,overlays}/*.jsx` — React
  translations of this app's own ERB; the ERB is the better reference
- `components/**/*.card.html`, `thumbnail.html` — Design-pane preview shells
- `guidelines/*.html` (16) — foundation specimen cards; content is summarised in `readme.md`
- `ui_kits/web/*.jsx` (9 screens) — composition demos; the README table above maps them to views
- `_ds_bundle.js`, `_ds_manifest.json`, `_adherence.oxlintrc.json` — build artifacts
- `assets/app-icon-512.png` — binary, only needed for Project 3 (native)

`DesignSync` is a **main-loop-only** tool. Subagents cannot call it and must read
this directory instead.

## Defects found in the source assets

1. **`assets/logo.svg` renders solid black, not the gradient wordmark.** The paths carry
   `class="st0"`…`class="st6"` but the file has no `<style>` block and no `fill` attribute,
   so the seven `radialGradient` definitions are never referenced. `readme.md` claims the
   fills were "restored here by mapping each class to its sibling gradient id" — that
   restoration is **not present in the file**. Rendering the mirror copy gives pure greyscale
   (`#000000`…`#E8E8E8`).

   **The app's own `app/assets/images/logo.svg` is authoritative — do NOT overwrite it with this
   one.** It predates the mirror (committed in `e9fcf3a`, the React-SPA era) and is the pristine
   Illustrator export: it still carries the `<style>` block, so `.st0`…`.st6` always resolved and
   it always rendered the green→blue radial. The mirror copy additionally has its path data
   mangled into `&#xA;` entities and has lost the encoding declaration.

   Slice 9 Task 1.2 hardened the app copy by adding seven explicit `fill="url(#…)"` attributes so
   the gradients no longer depend on the `<style>` block surviving a future export. They mirror
   that block exactly — `st0→XMLID_18_`, `st1→XMLID_148_`, `st2→XMLID_149_`, `st3→XMLID_150_`,
   `st4→XMLID_151_`, `st5→XMLID_152_`, `st6→XMLID_153_` — and the render is byte-identical to
   the pre-slice file (ImageMagick `compare -metric AE` = **0**).

   `st4` (`XMLID_8_`) is a `<line>`, and a `fill` on a line does nothing. That is deliberate: the
   element is a vestigial 0.3-unit artifact (`x1="84.5"` → `x2="84.8"`) that the original export
   left invisible via `stroke:none`. Giving it a `stroke` instead would switch it on — a visible
   hairline, and the sole cause of a 6-pixel diff during implementation before it was corrected.
   **Mirror the `<style>` block; do not "fix" this into a stroke.**
2. **`assets/pinned-tab.svg` is a filled black square**, not a monochrome Hoojah mark —
   the potrace output degenerated to the full viewBox rectangle. Do not wire it as a
   Safari `mask-icon`; it would render as a black square in the tab strip.
3. **`assets/loading.svg` has no animation.** The three stance-coloured bars are there but
   the `<animate>` children were stripped, so it is a static graphic, not a spinner.

Note also `readme.md`'s own flagged inference: the `border-read` / `border-unread` classes
used by `app/views/notifications/_notification_card.html.erb` have **no colour definition**
anywhere in the app, so those 8px borders currently render as nothing. The tokens supply
`--notif-unread` (neutral pink) and `--notif-read` (light-grey) to close that gap.

## Deviations in the app

Where the app intentionally departs from the mirror — `app/assets/tailwind/application.css`
against `tokens/*.css`, and `app/views/**` against `components/**/*.prompt.md`. The app is
authoritative; this table exists so the mirror and the app do not silently disagree, and so
that a later agent reading a prompt file does not "restore" something the app moved past
on purpose.

| DS artifact | In the app | Why |
| --- | --- | --- |
| `--text-body`, `--text-muted`, `--text-faint`, `--text-link`, `--text-inverse` | renamed to `--fg-body`, `--fg-muted`, `--fg-faint`, `--fg-link`, `--fg-inverse` | `--text-*` **is** Tailwind v4's font-size namespace — the same one `--text-xs`…`--text-2xl` use. Colours under those names are a trap: promote one into `@theme` and you emit `.text-muted{font-size:#8e8e8e}`. `fg-` is not a v4 namespace, so the collision cannot happen. |
| `--notif-unread`, `--notif-read` | `--color-unread`, `--color-read` (in `@theme`) | They must generate the `border-unread` / `border-read` utilities the notification card interpolates, so they have to sit in the `--color-*` namespace. |
| `--shadow-sm` | **omitted** | Its value is the Tailwind *v3* number while the DS prose says "Tailwind defaults". Under v4 that value is `shadow-xs`, so declaring it silently lightens every `shadow-sm`. Nothing reads it via `var()`. |
| `--radius-none` | **omitted** | v4's `rounded-none` is a static utility that ignores the token. |
| `--space-1`…`--space-6` | **omitted** | They are the 4px steps Tailwind's default `--spacing` already ships. |
| `--font-medium`, `--font-semibold`, `--font-bold` | `--font-weight-medium`, `--font-weight-semibold`, `--font-weight-bold` | v4's namespace for weights is `--font-weight-*`. Under the DS spelling `font-semibold` would generate nothing. |
| `--text-xs-lh`…`--text-2xl-lh` | `--text-xs--line-height`…`--text-2xl--line-height` | v4 pairs a line-height to a size with the `--text-<size>--line-height` suffix, not a separate `-lh` token. |
| `--font-sans` | **omitted** | `@layer base` sets `body { font-family: var(--font-sans) }`, so the live stack is Tailwind v4's default — `-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", "Noto Sans", Arial, sans-serif, …`. That is **not** what `tokens/typography.css` specifies (`ui-sans-serif, system-ui, sans-serif, …`); the two agree on macOS and Windows but diverge on Linux and Android. The omission is deliberate — restoring the DS value would change rendering on those platforms and needs a visual pass first. |
| `components/navigation/Navbar.prompt.md` — "The brand is the bold indigo *text* lockup, not the SVG wordmark." | `shared/_navbar.html.erb` ships `image_tag "logo.svg"` | **The prompt line is stale, not a spec.** It describes the navbar as it stood when the mirror was pulled; Slice 9 **Task 1.2** deliberately replaced the text lockup with the gradient wordmark asset, and `readme.md`'s own **Assets** section lists `assets/logo.svg` as a real artifact ("gradient 'hoojah' wordmark (green→blue radial)") — so the mirror contradicts itself, and the readme half is the current one. `spec/system/branding_spec.rb` pins the asset (`nav a[href='/'] img[alt='Hoojah']`) and a second example fails if the seven `radialGradient` defs ever go unreferenced. Do **not** revert the navbar to text on the strength of the prompt line. |
