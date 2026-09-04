# Public & Interaction Polish — Design

Date: 2026-09-04
Status: approved-pending-review

Four pieces of polish, grouped into three independent implementation tracks (no file
overlap between tracks, so they can run in parallel):

- **Track A — Conviction vote interaction** (`conviction_controller.js`, `_vote_hero.html.erb`, specs)
- **Track B — Dismissible dropdowns everywhere** (5 ERB call sites + system spec)
- **Track C — Public static-page redesign + em-dash removal** (5 page ERBs + shared chrome/partials + specs)

The em-dash removal (originally a separate ask) is folded into Track C because the
redesign re-authors the exact copy that contains the em-dashes — doing them separately
would double-edit the same lines and conflict.

---

## Track A — Conviction vote interaction

### Current behaviour (baseline)
`app/javascript/controllers/conviction_controller.js` drives a **press-and-hold** charge
over the three stance `<form>`s in `app/views/hujahs/_vote_hero.html.erb`:

- One controller on the `#…_vote_hero` wrapper; three stance forms inside.
- `data-conviction-duration-value="900"` — a 900 ms hold window.
- `pointerdown → start`: begins a RAF `tick` loop + a `setTimeout(commit(true), 900)`.
- `tick` fills the ring (`--charge` 0→1) and sets the countdown digit `ceil((1-pct)*3)` → 3→0.
- `pointerup → end`: if the timer hasn't fired, `commit(false)` — a **normal vote** (quick tap).
- `pointerleave → leave`: cancels the charge, **no vote**.
- With JS off, each form is a plain POST casting a normal vote.

### Target behaviour (approved: "Hold; release = cancel")
A conviction (locked, irreversible) vote must now take a deliberate ~7-second hold:

1. **Quick tap** (press + release within a short tap threshold) → **normal vote** for that
   stance, exactly as today.
2. **Hold past the tap threshold** → the charge engages: a **2-second silent arm phase**
   (overlay shown, no countdown digit yet), then a **5-second countdown** showing digits
   **5 → 4 → 3 → 2 → 1**, each visible for exactly one second. Holding all the way to the
   end (~7 s) commits the **conviction vote**.
3. **Release (`pointerup`) or leave (`pointerleave`) at any point after the charge has
   engaged and before the lock** → **cancel, no vote at all** (not even a normal vote).

The one-gesture model is preserved: a genuine quick tap still casts a normal vote; only a
sustained hold locks; letting go mid-hold now aborts cleanly.

### Timing model (measured from `pointerdown` at t=0)
| Phase | Window | Digit shown | Release behaviour |
|---|---|---|---|
| Quick-tap zone | `[0, tap)` (default **200 ms**) | none | normal vote |
| Arm (silent) | `[tap, armDelay)` (armDelay default **2000 ms**) | none | cancel |
| Countdown | `[armDelay, armDelay+countdown)` (countdown default **5000 ms**) | `ceil((total−elapsed)/1000)` = 5,4,3,2,1 | cancel |
| Lock | `elapsed ≥ total` (total = armDelay+countdown = **7000 ms**) | — | conviction committed |

Digit formula, evaluated only while `elapsed ≥ armDelay`:
`digit = ceil((total − elapsed) / 1000)` → 5 for `[2000,3000)`, 4 for `[3000,4000)`, …,
1 for `[6000,7000)`. Each digit is on screen for exactly 1000 ms. Below `armDelay` the
digit element is blank (or hidden) so nothing counts during the arm phase.

Ring fill (`--charge`): reflects **countdown progress only** —
`charge = clamp((elapsed − armDelay) / countdown, 0, 1)`. During the arm phase the ring
sits at 0 and the overlay shows an "arming / hold to lock" affordance.

### Controller changes (`conviction_controller.js`)
- Replace `duration` value with three values:
  `static values = { armDelay: {type:Number, default:2000}, countdown: {type:Number, default:5000}, tap: {type:Number, default:200}, locked: Boolean }`.
- `start`: record `t0`, show overlay, start RAF. Schedule the lock with a single
  `setTimeout(() => { this.held = true; this.commit(true) }, armDelay + countdown)`.
- `tick`: compute `elapsed`. Set ring `--charge` from countdown progress; set the digit
  only when `elapsed ≥ armDelay` (blank otherwise).
- `end` (pointerup): if `held` → return (already locked). Else if
  `performance.now() − t0 < tapValue` → `cancelCharge(); commit(false)` (**normal vote**).
  Else → `cancelCharge()` only (**cancel, no vote**) — this is the key change from today,
  where any pre-threshold release cast a normal vote.
- `leave` (pointerleave): unchanged — `cancelCharge()`, no vote.
- `cancelCharge`: also blank the digit and reset the arming state.
- Keep `commit`, `noMenu`, `setChargeColor`, `setChargeLabel` (label may read
  "hold to lock…" during arm and "locking <stance>" during countdown — copy is
  non-critical, keep it token-coloured).

### View changes (`_vote_hero.html.erb`)
- Replace `data-conviction-duration-value="900"` with
  `data-conviction-arm-delay-value="2000" data-conviction-countdown-value="5000" data-conviction-tap-value="200"`.
- Change the charge overlay's initial digit from `3` to `5` (line ~123) and start it
  blank/hidden until the countdown phase (the controller manages it after connect).
- Copy already reads "Release to cancel · reaches 0 to lock it in" and "Tap to vote ·
  hold to charge a conviction vote" — both remain accurate under release=cancel; keep them
  (optionally soften "reaches 0" → "hold to lock it in").
- No server/model changes — the POST payload (`conviction` hidden field) is unchanged.

### Testing (`spec/system/vote_hero_spec.rb`, `spec/support/pointer_helpers.rb`)
The Stimulus timing is read live from the `data-*` attributes, so **system specs override
the timing to short values** (e.g. set `data-conviction-arm-delay-value` and
`data-conviction-countdown-value` on the wrapper via `page.execute_script` before the
hold) to keep the suite fast instead of sleeping 7 s. Cases:
- **Quick tap → normal vote**: existing instant `.click` on a stance still records
  `agree_count == 1`, `conviction_count == 0` (a `.click` is well under the 200 ms tap
  threshold). Keep as-is.
- **Full hold → conviction**: with timing shrunk (arm≈100, countdown≈250), `hold(...)`
  past `arm+countdown` records the conviction vote (`conviction_count == 1`,
  `votes.last.conviction == true`).
- **Release mid-hold → cancel (NEW)**: with timing shrunk, hold past the tap threshold but
  release before `arm+countdown` → assert **no vote recorded** (all counts 0). This is the
  behaviour the "release = cancel" decision introduces and must be locked by a test.

`pointer_helpers.rb`'s `hold(selector, seconds)` stays the sanctioned single sleep; it may
gain the ability to release early for the cancel case.

---

## Track B — Dismissible dropdowns everywhere

`app/javascript/controllers/dropdown_controller.js` already implements
"click/tap outside or press Escape closes this `<details>`", attached via
`data-controller="dropdown"` on the `<details>` element itself (added in commit `0923c4f`
for the two hujah-show menus). There is **no single choke point**: `ui/_menu` is the panel
only; the `<details>` lives at each call site. So the fix is per-call-site.

Add `dropdown` to the `data-controller` of the five remaining menus:

| Call site | File:line | Change |
|---|---|---|
| Feed hujah-card action menu | `app/views/hujahs/_card_menu.html.erb:41` | `data-controller="share"` → `"share dropdown"` |
| Navbar user/avatar menu | `app/views/shared/_navbar.html.erb:45` | add `data-controller="dropdown"` |
| Debate verdict share menu | `app/views/debates/_verdict.html.erb:158` | `data-controller="share"` → `"share dropdown"` |
| Profile header share menu | `app/views/users/_profile_header.html.erb:61` | `data-controller="share"` → `"share dropdown"` |
| Notification card more-options | `app/views/notifications/_notification_card.html.erb:188` | add `data-controller="dropdown"` |

Merging `dropdown` into an existing `share` controller list is safe (independent
controllers). No markup, layout, or JS-off contract changes; the `<details>`/`<summary>`
still toggle natively without JS.

### Testing (`spec/system/dropdown_dismiss_spec.rb`)
Extend the existing spec to cover at least the **navbar user menu** (present on every
authenticated page) and one **feed card menu** (on `hujahs#index`): open, click outside,
assert closed; press Escape, assert closed. Mirror the assertion style already used for the
show-page menus.

---

## Track C — Public static-page redesign + em-dash removal

### Scope (approved)
Redesign the **five static informational pages** — About, Tutorials, FAQ, Privacy, Terms
(`app/views/pages/*.html.erb`, served by `PagesController`, all `skip_authorization`) — to
the imported design **`Public Pages - Redesign.dc.html`**. **Keep the existing site
navbar** (`shared/_navbar`) and the app layout; **do not** introduce the design's separate
minimal public nav, its theme/scheme toggles, or restyle the Devise auth screens. The
redesign is the page **body** layout only.

### Layout (from the design, mapped to house tokens)
The design renders on `var(--surface)` in a centred **576 px** column (= `max-w-xl`):

**Header** (centred, with a bottom hairline border):
- A per-page **hero illustration** (unique inline SVG per page, stroked with token vars
  `--ink`/`--primary`/`--faint`/`--agree`/`--neutral`/`--disagree`/`--primary-soft`).
- An **eyebrow**: `Last updated {date}` — 12 px, uppercase, letter-spaced, `text-faint`.
- **h1** — ~32 px, extrabold, `tracking-tight`, `text-wrap:balance`, centred.
- Optional **lede** — ~18 px, `text-ink-2`, centred, `text-wrap:pretty` (About & Tutorials only).

**Sections** — two variants (mutually exclusive, exactly as the design's `renderVals`):
- **Spots variant** (About, Tutorials): each section is a 2-col grid `56px 1fr` with a
  rounded 56 px **spot icon box** (`bg-card-2`, `rounded-[14px]`) on the left and
  `h2`(~20 px)/body on the right. **No dividers.** Section gap ~40 px. Spot SVG keyed by a
  `spot` name: `claim / votes / mission / compose / responses / debate`.
- **Dividers variant** (FAQ, Privacy, Terms): single-column sections, `h2`(~18 px)/body,
  a hairline **border-bottom between sections**, gap ~28 px. No spots.

**Body prose**: `text-ink-2`, ~16 px, line-height 1.7; `<em>`/`<strong>` → `text-ink`;
lists as `ul` with `text-faint` markers. (The design's `.prose` rules.)

**Footer** (new, part of the page body — this is *not* the navbar, so it's in scope):
centred row of the five site links (About/Tutorials/FAQ/Privacy/Terms) with the current
page in `text-ink` and the rest in `text-ink-2`, plus `© 2026 Hoojah` in `text-faint`.

Dark mode and colour schemes work automatically — everything is token-driven; no concrete
hex, so no new `@source inline(...)` safelist entries are needed (illustrations use
`var(--…)` inline in SVG, not utility classes).

### File structure
- **`app/views/pages/_legal_chrome.html.erb`** — rewritten shell (keep the name to limit
  blast radius; update its comment). Renders `shared/navbar`, the 576 px column, the header
  (art + eyebrow + h1 + optional lede), a `yield` region for the sections, and the footer.
  New locals: `title:`, `updated:`, `lede: nil`, `art:` (page key), `variant:` (`:spots`
  or `:dividers`).
- **`app/views/pages/_page_art.html.erb`** — hero illustration; `case art` → the per-page
  SVG (about/tutorials/faq/privacy/terms), lifted from the design.
- **`app/views/pages/_section.html.erb`** — one section; locals `heading:`, `spot: nil`,
  `variant:`; renders the grid (spots) or single column (dividers) and yields the body.
- **`app/views/pages/_spot.html.erb`** — the section spot icon box; `case spot` → the SVG
  (claim/votes/mission/compose/responses/debate), lifted from the design.
- **The five page ERBs** — rewritten to call `legal_chrome` with the right locals and
  render their sections via `_section`, using the **rephrased, em-dash-free** copy.

### Copy: em-dash removal
Every em-dash (`—`, U+2014) in the five pages must go — **rephrase the sentence**, don't
just swap the glyph. Inventory (~25 occurrences): About ×3, Tutorials ×4, FAQ ×6,
Privacy ×7, Terms ×5. No en-dashes present. Rephrasing keeps meaning and tone; prefer
recasting into separate clauses, colons, parentheses, or "such as"/"like"/"including".
Examples:
- `the Malay word hujah — an argument you're prepared to defend` →
  `the Malay word hujah, meaning an argument you're prepared to defend`.
- `voted on in three ways — agree, neutral, or disagree — and neutral is a real stance` →
  `voted on in three ways (agree, neutral, or disagree), and neutral is a real stance`.
- `Account details — your email address, username, …` →
  `Account details: your email address, username, …`.

Keep the existing "Last updated" dates (About/Tutorials 30 August 2026; FAQ/Privacy/Terms
26 August 2026) — this is a copy-editing + layout pass, not a substantive legal revision.

### Testing
- Keep `PagesController` request/system specs green. Any existing spec that asserts an
  exact sentence containing an em-dash must be updated to the rephrased wording.
- Add a guard that the five rendered pages contain **no `—`** (a request spec asserting
  `response.body` excludes U+2014 for each page) so the em-dash policy can't silently
  regress.
- Confirm each page still renders (200, correct h1) logged-out and logged-in.

---

## Cross-cutting: quality gates
All work must keep `bin/ci` green: StandardRB, Brakeman, bundler-audit, the full RSpec
suite (request + headless-Chrome system specs), and the Tailwind build. No new interpolated
Tailwind classes are introduced (Track C uses `var(--…)` inline in SVG and static
utilities), so no `@source inline(...)` changes are expected — verify with the md5 bundle
check if any utility looks interpolated.

## Out of scope / deferred
- Devise login/signup redesign (design includes it; not this pass).
- The design's minimal public nav and theme/scheme toggle chrome.
- Collapsing the legacy `votes.vote` array column; conviction model/schema changes.
- The `_vote_hero` "BOOM" celebration overlay (still parked for a future optimistic pass).
