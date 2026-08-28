# UI polish: spacing · feed-card · Jump in · navbar · microanimations

_Spec date: 2026-08-28. Branch: `ui-polish-2026`. Built via brainstorm → spec → plan →
subagent-driven development, each slice gated by a **Fable architecture/leak audit**, using
**find-animation-opportunities** to catalog motion and **better-stimulus** for controller work.
`bin/ci` green per slice._

## Goal

An app-wide polish pass: consistent spacing across every surface (cards, forms, dropdowns),
feed-card interaction changes (un-linked title, persistent "Jump in" CTA, conviction count), a
navbar mobile tweak, and an expressive-but-safe microanimation layer. Design reference: the 2026
feed-card mockup (Image #1) — the live app is already close; this closes the gaps.

## Decisions (locked in brainstorming)

- **Jump in**: on every feed card, right-aligned primary pill. Smart target — active live debate →
  `debate_path(active_debate)`; otherwise → the hujah thread (`hujah_path`). Primary way into the
  thread now that the body is un-linked.
- **Feed-card body**: not a link. `#hashtag`/`@mention` anchors from `format_body` stay clickable.
- **Conviction count**: show `💜 <conviction_count>` in the footer stats when `> 0` (aggregate-only,
  secret-ballot-safe), matching the mockup.
- **Spacing**: consistency pass — codify one scale, adjust spacing tokens if warranted.
- **Animation**: expressive set (restrained base + playful accents), reduced-motion safe, Stimulus
  authored per better-stimulus.

## Slices

### Slice A — Navbar mobile (tiny)
`app/views/shared/_navbar.html.erb` L148 mobile Trending button: keep the `flame` icon +
`aria-label: "Trending"`; the label `<span>Trending</span>` becomes `hidden min-[420px]:inline`
(icon-only below ~420px; label returns on larger phones/tablets). The button stays `lg:hidden`.
Add `min-[420px]:inline` to the `@source inline(...)` safelist only if the arbitrary-breakpoint
utility isn't otherwise emitted (verify via built-bundle check).

### Slice B — Feed card (`app/views/hujahs/_hujah_card.html.erb`)
1. **Un-link the body** — remove the `link_to hujah_path` wrapper (L52-54) around `.hujah-body`;
   render `<div class="hujah-body …"><%= format_body(hujah.body) %></div>` directly. This also fixes
   the current **nested-anchor invalid HTML** (`format_body` injects `<a>` for tags/mentions inside
   that outer `<a>`). Body becomes selectable, non-navigating; tags/mentions still link.
2. **Persistent "Jump in →"** — move the pill out of the `if hujah.active_debate` guard so it renders
   on every card, right-aligned (`ml-auto`), `ds_button_classes(variant: :outline, tone: "primary")`.
   Target: `hujah.active_debate ? debate_path(hujah.active_debate.slug) : hujah_path(hujah.slug)`.
   The `swords` live indicator stays additive (only with an active debate).
3. **Conviction count** — in the footer stats, after `📊 total_votes · 💬 responses`, add
   `💜 <conviction_count>` when `hujah.conviction_count.to_i > 0` (Lucide `heart`, primary/`--conviction`
   tint). Keep the 💬 responses count linking to the thread (secondary entry). `📊`/`💬` counts stay.
4. **Scope**: only the feed `_hujah_card` title. Compact cards (`_child_card`, `users/_user_hujah`)
   keep their whole-card overlay link (navigational by design). The show page hero is already the
   thread, so no self-link to remove there.

Regression tests (system, js): body text is present but NOT a link to `hujah_path`; a `#hashtag`
and `@mention` inside the body ARE links; "Jump in" is present on a plain card (→ `hujah_path`) and
on an active-debate card (→ `debate_path`); conviction count renders when `> 0`.

### Slice C — Spacing/padding/margin consistency pass
Fable-architected audit produces a concrete per-surface diff before edits. Normalize to the existing
`--space-1..6` (4px) scale; adjust the token scale only with an explicit, documented reason.
Surfaces: card padding (`ui/_card`, `ds_card_classes` `padded:`), forms (`hujahs/_compose_form`,
`hujahs/_inline_composer`, devise auth, `users/_profile_edit`), dropdowns/menus (`ui/_menu`,
`ds_menu_item_classes`), navbar, profile header, debate room (`debates/show` + partials),
notifications (`_notification_card`). Guardrails: interpolated classes need `@source inline(...)`;
same-family utilities resolve by bundle order (don't fight `ui/_card`/`ui/_menu` baked paddings —
use their locals). Before/after screenshots per surface; md5 the bundle around comment-only edits.

### Slice D — Microanimations (expressive, reduced-motion safe)
Run **find-animation-opportunities** to catalog; implement the approved set. Motion tokens/keyframes
in `application.css` (reuse `hbreathe`/`hrise` where they exist). Set:
- **Press feedback** on pills/buttons (extend the existing `active:scale-95` with a settle).
- **Turbo-Stream enter transitions** — new debate turns, new replies, vote-bar replace, notifications:
  fade + rise in (`hrise`-style), via `@starting-style`/CSS animation on insert.
- **Menu/dropdown + `<dialog>` open/close** — quick ease/scale.
- **Tab-underline slide** — feed tabs + profile tabs.
- **Vote-cast accent** — wire the existing conviction charge-ring/boom markup for an optimistic pulse.
- **Number roll-up** on counts (expressive tier).
- **Gate everything** behind `@media (prefers-reduced-motion: reduce)` (off). CSS-first; any Stimulus
  per better-stimulus (single responsibility, values API, no leaked timers — `disconnect` cleanup).

## Order & method
A → B → D-foundation (motion tokens) → C (spacing) → D (animations), so spacing settles before motion
is tuned on top. Each slice: Fable audit → subagent-driven TDD (implementer + spec/quality review) →
`design-review` pass + screenshots → `bin/ci` green. Invariants preserved: secret-ballot
(conviction_count is aggregate-only), per-post visibility, block/private gates — no new read surface.

## Out of scope
Impression counts (no tracking in this app — the mockup's "2,537" maps to `total_votes`); watcher
counts on the live strip (no data — already omitted); a full design-system re-mirror of `docs/`.
