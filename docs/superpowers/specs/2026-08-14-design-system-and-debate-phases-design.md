# Design System Adoption + Debate Structured Phases — Design

_Status: approved 2026-08-14. Supersedes nothing; extends the completed Project 2 program._

## Context

Project 2 ("React SPA → Hotwire") is complete — all 8 slices shipped, suite at **271 examples /
0 failures / 2 pending**, brakeman 0, `standardrb` and `bundler-audit` clean. See
`docs/superpowers/HANDOVER.md`.

Two inputs drive this slice:

1. **The Hoojah Design System** (Claude Design project `d6e14421-12ce-483a-af8f-b25e58f4852e`),
   mirrored to `docs/design-system/` — see `docs/design-system/MIRROR-NOTES.md` for what is and
   isn't mirrored, and why.
2. **The Hoojah project write-up** (https://rudzainy.github.io/work/2020-09-01-the-hoojah-project.html),
   which describes debate as an exchange of "opening statements, counter-arguments, responses, and
   closing statements".

### The framing that matters

**The design system was generated from this codebase.** Its `readme.md` names `hoojah-beta/` as its
source and `app/assets/tailwind/application.css` + `app/views/**` as ground truth. This is therefore
a **codification** pass — turning implicit conventions into an explicit system and fixing what the
extraction exposed as broken — **not a redesign**. No screen changes its layout, information
architecture, or copy except where this document says so.

**Debate is already built.** Slice 4 shipped challenge → accept/decline → alternating turns →
conclude → public transcript. Slice 8 shipped the spectator verdict, Action Cable real-time turns,
and the 7-day timeout auto-conclude. Measured against the write-up, the app already exceeds it
(the post describes no verdict mechanism at all). The one genuine gap is that **turns are unnamed** —
there is no Opening / Counter / Response / Closing structure. That gap is Part E below. Debate
mechanics are otherwise untouched.

## Goals

- Every one of the 72 design tokens available to the views; no view hand-rolling a value the system
  names.
- The four DS primitives with no ERB equivalent (`Card`/`Divider`, `EmptyState`, `Avatar`, `Button`)
  exist once and are used everywhere the markup is currently copy-pasted.
- The latent defects the DS extraction exposed are closed.
- Debate turns carry a named phase, with a default 4-round structure and an explicit opt-in to
  continue past it.

## Non-goals

- No dark mode, no webfonts, no animation beyond the existing `transition` + `active:scale-95`
  (the DS is explicit on all three).
- No new gem. No ViewComponent.
- No change to debate authorization, broadcasting, verdict, or timeout behaviour beyond what Part E
  states.
- Not closing the deferred items carried in HANDOVER.md (vote array→scalar, serializer N+1 /
  prosopite, `Api::V1` visibility/block parity, `require_master_key` L4, `rack-cors` M1).

---

## Part A — Token foundation

**File:** `app/assets/tailwind/application.css`

Today's `@theme` defines **7** colors. The DS defines **72** custom properties. Port all of them,
preserving Tailwind v4 `@theme` semantics (so `bg-*` / `text-*` / `border-*` / `fill-*` utilities
generate).

- **Colors** — the existing 7, plus `white`, `gray-50/100/200`, `red-50/700`, and — closing the
  latent gap — **`read`** (`--color-light-grey`) and **`unread`** (`--color-neutral`).
- **Semantic aliases** — `--surface-{page,card,menu,nav,profile}`, `--text-{body,muted,faint,link,inverse}`,
  `--border-{hairline,field}`, `--track-bar`, `--backdrop`.
- **Typography** — the size/line-height pairs actually used (`xs` 12/16, `sm` 14/20, `base` 16/24,
  `lg` 18/1.375, `xl` 20/1.375, `2xl` 24/32), `--leading-snug`, weights, `--tracking-wide`.
- **Layout** — `--space-1..6`, radii (`none` for cards — feed cards are square, `4px`, `8px`, `full`),
  the three shadows, `--border-stance` (8px), `--border-pill` (2px), and the fixed sizes
  `--nav-h` 56, `--content-max` 576, `--sidebar-w` 256, `--vote-btn` 44, `--bar-h` 8, and the five
  avatar sizes (96/44/40/36/32).

**Safelist.** The existing `@source inline("{bg,text,border,fill}-{agree,neutral,disagree,primary}")`
covers interpolated stance utilities. `_notification_card` interpolates `border-<read|unread>` the
same way, so add `@source inline("border-{read,unread}")`.

**Base layer.** Port `docs/design-system/tokens/base.css` into an `@layer base` block: `body` gets
the font stack, `--text-body` color and `--surface-page` background; `a` gets `--text-link` and no
underline. This is what makes `<body class="body">` in the layout meaningful — **`.body` is
currently defined nowhere in the app**, so it is inert today.

### Verification

`bin/rails tailwindcss:build` succeeds and the compiled `app/assets/builds/tailwind.css` contains
`border-read` and `border-unread` rules. Note the existing CI/deploy constraint: that file is
gitignored and built by the `assets:precompile` hook.

---

## Part B — Brand assets

Vendor into `app/assets/images/` and wire into `app/views/layouts/application.html.erb`.

- **`logo.svg`** — replaces the navbar's plain text "Hoojah" wordmark.

  **Corrected during implementation (Task 1.2):** this section originally said to vendor the
  mirror's copy after repairing it. That would have been a regression. `app/assets/images/logo.svg`
  **already existed** — committed in `e9fcf3a` during the React-SPA era, unused since the navbar
  rendered a text brand — and it is the pristine Illustrator export with its `<style>` block
  intact, so its gradients always resolved. It is the *mirror* copy that is degraded (no `<style>`,
  path data mangled into `&#xA;` entities, encoding declaration lost), rendering pure greyscale.

  What actually shipped: the app's copy was kept and hardened with seven explicit `fill="url(#…)"`
  attributes, so the gradients no longer depend on the `<style>` block surviving a future export.
  They mirror that block exactly — `st0→XMLID_18_`, `st1→XMLID_148_`, `st2→XMLID_149_`,
  `st3→XMLID_150_`, `st4→XMLID_151_`, `st5→XMLID_152_`, `st6→XMLID_153_` — which independently
  confirms the sibling mapping derived here. Render is byte-identical to the pre-slice file
  (`compare -metric AE` = 0).

  One correction worth recording: this section first said to give `st4` (`XMLID_8_`) a `stroke=`,
  since a `fill` does nothing on a `<line>`. That reasoning was backwards. The element is a
  vestigial 0.3-unit artifact the original export deliberately left invisible via `stroke:none`;
  adding a stroke switched it on and produced a 6-pixel visual change. In a slice that is a
  codification pass rather than a redesign, that is precisely the defect class to avoid.
- **`loading.svg`** — vendor as-is, but note it is **static**: the `<animate>` children were
  stripped upstream, so it is three coloured bars, not a spinner. Do not present it as a loading
  indicator until animation is restored. Nothing currently depends on it.
- **`pinned-tab.svg`** — **do not wire.** The potrace output degenerated to a filled black rectangle
  covering the whole viewBox; as a Safari `mask-icon` it would render a black square. Kept in the
  mirror for the record only.
- **`app-icon-512.png`** — not mirrored (binary, large, only needed for Project 3). Fetch on demand.

Favicon and apple-touch-icon therefore wait on real assets; only the wordmark lands this slice.

### Verification

Navbar renders the gradient wordmark at 56px nav height; a system spec asserts the `<img>`/inline
SVG is present and the accessible name is still "Hoojah".

---

## Part C — ERB primitives

**Partials + helpers, no new gem.** The app is partial-based throughout; ViewComponent would add a
dependency and a second idiom for no gain.

| DS component | Rails form | Replaces |
| --- | --- | --- |
| `Card` / `Divider` | `app/views/ui/_card.html.erb`, `_divider.html.erb` | the `shadow bg-white` + `border-gray-100` idiom repeated across the feed, debate, notification and profile views |
| `EmptyState` | `app/views/ui/_empty_state.html.erb` | the same faint-icon + one-sentence markup in **six** views |
| `Avatar` | `app/views/ui/_avatar.html.erb` | bare `image_tag user.photo` — **which raises when `photo` is blank** (reachability note below); the partial adds the DS initials-on-indigo fallback |
| `Button` | `DesignSystemHelper#ds_button_classes(variant:, tone:, size:)` | the hand-repeated `rounded-full border-2 … shadow active:scale-95` string |
| `Icon` / `STANCE_COLOR` | extend the existing `IconsHelper` (already holds `STANCE_ICON`) | interpolated `text-#{stance}` / `fill-#{stance}` strings |

`ds_button_classes` variants mirror the DS exactly: `outline` (the house pill), `solid` (primary
submit), `rect` (auth screens + signup CTA), `onPrimary` / `onPrimaryOutline` (white-on-blue, profile
header only), `link` (bare text control).

**Blank-photo reachability — corrected during implementation.** This section originally implied the
`image_tag user.photo` crash was routinely hit. It is not, but it is genuinely reachable, and the
distinction is worth recording:

- `User#assign_random_photo` is `after_create` **only**, so it backfills once and never again.
- `photo_from_cloudinary` opens with `return if photo.blank?` — blank **passes** validation.
- `:photo` is permitted in `UsersController#user_params`.

So an update carrying `user[photo]=""` succeeds and leaves the account permanently photo-less, after
which every surface rendering that avatar 500s — the profile, every feed card, every debate turn.
The normal UI does not produce it, because `_profile_edit`'s `f.hidden_field :photo` submits the
current value. `_avatar` is therefore a fix for a latent crash, not a routine one. Note also that a
`create`d user in specs can never exercise the branch (the callback fills it); tests must use
`build`.

The `Card` partial takes an optional `stance:` local for the **8px stance-coloured left border** —
the signature motif — and an optional `as:` for `article` / `a`.

### Verification

Helper unit specs for `ds_button_classes` (every variant, tone fallback) and for `Avatar` initials
derivation including the blank-photo path. Existing view specs must stay green unchanged.

---

## Part D — View refactor

All ~75 views under `app/views/**`, refactored family by family in the DS's own nine groups. The
component→view mapping is recorded in `docs/design-system/ui_kits/web/README.md`.

| Family | Views |
| --- | --- |
| navigation | `shared/_navbar`, `hujahs/_feed_tabs` |
| voting | `hujahs/_vote_bars`, `_stance_picker`, `_response_filter` |
| hujah | `hujahs/_hujah_card`, `_hujah_header`, `_child_card`, `_parent_card`, `_compose_form`, `_share_menu`, `_load_more`, `index`, `show`, `new` |
| social | `users/*` (10), `notifications/*`, `trending/*`, `shared/_pinned`, `blocks/*` |
| debate | `debates/*` (8), `debate_turns/*`, `debate_verdicts/*` |
| forms | `devise/**`, `users/_profile_edit` |
| analytics | `analytics/*` |
| overlays | `hujahs/_flag_dialog`, `_challenge_dialog` |

Each family is one subagent task, with `docs/design-system/readme.md` plus that family's
`*.prompt.md` as the contract.

**Also fixed here:** `shared/_navbar` links "Your profile" to `"#"` — a dead link. Point it at
`profile_path(current_user.username)`.

**Rule for every task:** markup and classes may change; **rendered copy, `dom_id`s, `data-*`
attributes, form actions, and Turbo Stream targets may not.** The Slice 8 broadcast contract depends
on `dom_id(debate, :transcript|:composer|:status|:actions)` and on `_debate_actions` /
`_turn_composer` taking an explicit `viewer:` local rather than `current_user`. The response filter
depends on `data-response-filter-target` / `data-response-filter-vote`. Breaking any of these
breaks real-time or filtering silently.

### Verification

The full suite after each family, plus `standardrb`. The 24 Cuprite system specs are the real
guard — they drive voting, debate, private accounts, blocks and analytics end to end.

---

## Part E — Debate structured phases

### Model

**Migration:** add `debates.rounds_limit` integer, NOT NULL, default `4`.

**Backfill is the risk.** A blanket default would retroactively put already-long debates past their
cap. Backfill instead:

- `active` debates → `GREATEST(4, current_round + 1)`, so no live debate is cut off mid-flight
- every other status → `4`

**Phase derivation — no column on `debate_turns`:**

```
DebateTurn#round     = ((position - 1) / 2) + 1     # positions are 1-based
Debate#phase_for(r)  = :opening              if r == 1
                       :closing              if r == rounds_limit
                       :counter              if r.even?
                       :response             otherwise
DebateTurn#phase     = debate.phase_for(round)
```

With the default `rounds_limit = 4` this yields exactly the write-up's sequence: Opening (R1) →
Counter (R2) → Response (R3) → Closing (R4), two turns per round, 8 turns total.

**Cap:** at the end of `post_turn`, when `turn.position == rounds_limit * 2`, call
`conclude!(by: nil)` and **skip the `debate_your_turn` notification** — there is no next turn. The
`by: nil` path already notifies both participants and awards `first_debate`, which is the correct
behaviour for a structural end.

**Extension:** `Debate#extend_rounds!(by:)` — increments `rounds_limit` by 1. Guards: `active?`,
`participant?(by)`, `rounds_limit < 10` (hard ceiling), and **`turns.count == (rounds_limit - 1) * 2`**
— that is, the closing round has been reached but no closing turn has been posted into it yet.
Broadcasts via the existing `broadcast_state_change`.

That last guard is not cosmetic. Because phase is **purely derived**, bumping `rounds_limit` while a
closing-round turn already exists would silently relabel that posted turn from CLOSING STATEMENT to
COUNTER-ARGUMENT in every viewer's transcript. Restricting extension to the boundary — after round
`rounds_limit - 1` completes, before round `rounds_limit` begins — makes derivation stable: a label,
once rendered, never changes. The window belongs to whichever participant moves first in the closing
round, and the other participant retains `conclude!` throughout.

Extension is **unilateral by design.** It needs no proposal/accept state because `conclude!` is
already available to *either* participant at any time while active — a participant who does not
want to continue simply concludes. Adding negotiation state would buy nothing and would introduce a
new stall mode.

### Authorization, routing, throttling

- `DebatePolicy#extend?` — `record.participant?(user) && record.active?`
- `POST /debates/:slug/extend` → `DebatesController#extend_rounds`
- rack-attack `debate_extend/user`, 10/min — consistent with the existing challenge/turn/verdict throttles

Follows the established controller shape: derive the actor from `current_user`, `authorize` the
instance, respond with a Turbo Stream that replaces `dom_id(@debate, :status)` **and**
`dom_id(@debate, :actions)`. The Slice 8 review catch applies — the actor's own synchronous button
update must be in the controller response, because the async broadcast never fires in dev (no worker).

### Views

- `debates/_debate_turn` — phase micro-label above the byline: **12px, uppercase, `tracking-wide`**,
  per the DS micro-label rule (the same treatment as the debate state label and the verdict heading).
- `debates/_debate_status` — round progress, e.g. `ROUND 2 OF 4`, in the same micro-label style.
- `debates/_debate_actions` — "Extend by one round" button, shown only to a participant during the
  closing round with `rounds_limit < 10`. Takes the existing explicit `viewer:` local.

### Verification

- Model specs: `phase_for` across `rounds_limit` 4 and extended values; `DebateTurn#round` at
  positions 1–8; auto-conclude fires at exactly `rounds_limit * 2`; the your-turn notification is
  **not** created on the capping turn; `extend_rounds!` guard matrix (non-participant, non-active,
  too early, ceiling, and — the case the guard exists for — **rejected once a closing-round turn is
  already posted**, with an assertion that no already-rendered phase label changes).
- Policy + request specs for `extend?` including a non-participant 403 and the double-replace
  Turbo Stream response.
- Migration spec: an `active` debate with 10 existing turns is backfilled above its current round
  and does **not** auto-conclude on the next turn.
- System spec: drive 8 turns → auto-conclude → verdict appears; plus an extend flow at the closing
  round.

---

## Sequencing

A → B → C are prerequisites for D. E is independent of A–D and can run in parallel.

Landing order: **A+B** (foundation, small, low-risk) → **C** (primitives + their specs) → **E**
(debate phases, self-contained) → **D** (the wide refactor, family by family).

Putting D last means the widest diff lands against a foundation that is already proven green.

## Gates

Unchanged from the program: **271 examples / 0 failures / 2 pending** as the floor (new specs raise
it), brakeman **0**, `standardrb` clean, `bundler-audit` clean. Per the environment quirks in
HANDOVER.md, the canonical command is:

```bash
source .mise-build-env.sh
RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec
```

## Risks

| Risk | Mitigation |
| --- | --- |
| Refactor silently breaks a Turbo Stream target or Stimulus hook | `dom_id`/`data-*`/form-action freeze rule in Part D; the 24 Cuprite specs exercise them |
| Tailwind v4 `@theme` rejects a non-color token shape | Land Part A alone and build before anything depends on it |
| `rounds_limit` backfill truncates a live debate | `GREATEST(4, current_round + 1)` for actives, with a migration spec |
| Auto-conclude double-notifies | The capping turn skips `debate_your_turn`; `conclude!(by: nil)` owns the notification |
| Unilateral extension used to stall | Bounded by the 10-round ceiling, the per-user throttle, and either party's existing `conclude!` |
| Derived phase labels mutate under an extension | Extension only allowed at the closing-round boundary, before any closing turn exists |
