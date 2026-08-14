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
   restoration is **not present in the file**. Before vendoring into `app/assets/images/`,
   add `fill="url(#…)"` to each path using the sibling mapping:
   `st0→XMLID_18_`, `st1→XMLID_148_`, `st2→XMLID_149_`, `st3→XMLID_150_`,
   `st4→XMLID_151_`, `st5→XMLID_152_`, `st6→XMLID_153_`.
2. **`assets/pinned-tab.svg` is a filled black square**, not a monochrome Hoojah mark —
   the potrace output degenerated to the full viewBox rectangle. Do not wire it as a
   Safari `mask-icon`; it would render as a black square in the tab strip.
3. **`assets/loading.svg` has no animation.** The three stance-coloured bars are there but
   the `<animate>` children were stripped, so it is a static graphic, not a spinner.

Note also `readme.md`'s own flagged inference: the `border-read` / `border-unread` classes
used by `app/views/notifications/_notification_card.html.erb` have **no colour definition**
anywhere in the app, so those 8px borders currently render as nothing. The tokens supply
`--notif-unread` (neutral pink) and `--notif-read` (light-grey) to close that gap.
