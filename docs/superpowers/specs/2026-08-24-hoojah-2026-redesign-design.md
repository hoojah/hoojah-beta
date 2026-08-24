# Hoojah 2026 — New-post & Single-hujah redesign

**Date:** 2026-08-24
**Source design:** Claude Design project `9e95c0a1-b6b7-409b-8bce-3b4a95143877`, file `Hoojah 2026.dc.html`
**Scope surfaces:** the new-post composer and the single-hujah "argument" view.
**Status:** approved for planning.

This is a deliberate **rebrand**. It overrides the previous design-system rules ("neutral is
PINK", "no dark mode", "codify not redesign"). Those rules stood for the *old* palette; this spec
replaces the palette and adds theming. `docs/design-system/` will need re-mirroring afterward (out
of scope here — tracked as follow-up).

---

## 1. Goals & non-goals

**Goals**
- Restyle the new-post composer and the single-hujah page to the Hoojah 2026 look, as **responsive,
  mobile-first web** (no fake phone chrome — the phone frame in the mockup is presentation only).
- Introduce a runtime **theme** (light/dark) and **scheme** (Signal / Spectrum / Ballot) system that
  retints existing Tailwind utilities.
- Ship the net-new mechanics: per-post visibility, 8-char minimum (top-level only), per-post
  "Allow debates" toggle, conviction voting (as a lock flag), and a real hashtag system.

**Non-goals (this pass)**
- Other screens from the mockup (auth, profile, notifications, debate room, settings). They inherit
  the new tokens for free but are not re-laid-out here.
- Re-mirroring `docs/design-system/` (follow-up).
- Conviction as a *weight*. Conviction is a boolean lock only; tallies and percentages are unchanged.

---

## 2. Theming architecture

### 2.1 Token bridge
Keep Tailwind v4 utilities working but make them theme-aware by chaining `@theme` onto runtime CSS
variables.

In `app/assets/tailwind/application.css`:
- Add semantic runtime tokens to `@theme` as indirections, e.g.
  `--color-agree: var(--agree); --color-neutral: var(--neutral); --color-disagree: var(--disagree);
  --color-primary: var(--primary);` plus surface tokens `--color-card`, `--color-card-2`,
  `--color-ink`, `--color-ink-2`, `--color-faint`, `--color-hairline`, `--color-field`,
  `--color-surface`, `--color-agree-soft`, `--color-neutral-soft`, `--color-disagree-soft`,
  `--color-primary-soft`.
- Define the actual values on plain `:root` (Spectrum/light — the default), then override under
  `:root[data-theme="dark"]`, `:root[data-scheme="signal"]`, `:root[data-scheme="ballot"]`, and the
  dark×scheme combinations. **Values are taken verbatim from the mockup** (see 2.4).
- Retain the existing safelist and extend it to any new interpolated utilities:
  `@source inline("{bg,text,border}-{agree,neutral,disagree,primary}")` stays; add soft/surface
  utilities actually built by interpolation if any (most surface tokens are used as fixed utility
  names, so no new safelist rows unless an interpolation is introduced).

**Consequence:** `bg-agree`, `text-ink`, `border-hairline`, etc. compile once and resolve per
theme/scheme at runtime. Views change only to *use* the new surface utilities; stance utilities are
unchanged in name.

### 2.2 Root attributes & no-FOUC
- `data-theme` and `data-scheme` live on `<html>` (`app/views/layouts/application.html.erb`).
- A tiny **inline `<head>` script** (before the stylesheet) reads `localStorage["hoojah-theme"]` /
  `["hoojah-scheme"]` and sets the attributes before first paint. Defaults: theme = `light`,
  scheme = `spectrum` (absence of `data-scheme` also means spectrum, since spectrum is the `:root`
  base). The script is a static literal (no user data) — safe inline.
- Because it is raw JS in an inline `<script>`, remember Tailwind scans it: it must contain **no bare
  utility-class strings** (it won't — it only touches attributes and storage keys).

### 2.3 Controls
- `theme_controller` (Stimulus): toggles `data-theme`, persists to localStorage, swaps the toggle
  knob. Placed in the navbar (a compact pill) — reachable on every page.
- Scheme is switchable too, but a full switcher UI is **not** required on these surfaces; expose it
  minimally (e.g. a three-dot/settings affordance or reuse the theme pill's menu). A dedicated
  scheme picker screen is a non-goal. Persist to localStorage the same way.
- Both controllers must fail safe with JS off: the server renders `data-theme="light"
  data-scheme="spectrum"` defaults and the page is fully usable.

### 2.4 Token values (verbatim from the mockup)

Base = **Spectrum**, light (`:root`):
```
--primary:#415de6; --primary-soft:#eaeeff;
--agree:#0ea5a4; --neutral:#e8930c; --disagree:#8b5cf6;
--agree-soft:#e0f5f4; --neutral-soft:#fdf1de; --disagree-soft:#efeafe;
--surface:#f4f5f9; --card:#ffffff; --card-2:#f6f7fb;
--ink:#191c22; --ink-2:#5b616e; --faint:#a2a9b6;
--hairline:#edeef3; --field:#e6e8ef; --read:#d4d8e2; --unread:var(--neutral);
--nav:rgba(255,255,255,0.82); --shadow:0 8px 30px -12px rgba(20,24,54,.28);
--stance-shadow:0 10px 26px -12px;
```
Dark (`:root[data-theme="dark"]`):
```
--primary:#7d92ff; --primary-soft:#1c2140;
--agree:#2dd4cf; --neutral:#fbbf24; --disagree:#a78bfa;
--agree-soft:#0c2a29; --neutral-soft:#2c2410; --disagree-soft:#221b3a;
--surface:#0d0e13; --card:#16181f; --card-2:#1c1f28;
--ink:#f3f4f7; --ink-2:#a7adba; --faint:#6a7180;
--hairline:#242732; --field:#2a2e39; --read:#39404e; --unread:var(--neutral);
--nav:rgba(18,20,26,0.82); --shadow:0 12px 34px -14px rgba(0,0,0,.7);
--stance-shadow:0 12px 30px -12px;
```
Scheme **Signal** — light: `--agree:#12b981;--neutral:#f59e0b;--disagree:#f43f5e;
--agree-soft:#e6f7f0;--neutral-soft:#fdf2df;--disagree-soft:#fdeaed;` · dark:
`--agree:#2ee6a6;--neutral:#fbbf24;--disagree:#ff6b83;--agree-soft:#0e2b22;
--neutral-soft:#2e2611;--disagree-soft:#33141b;`
Scheme **Ballot** — light: `--agree:#4c956c;--neutral:#c98a3c;--disagree:#b5546a;
--agree-soft:#e9f1ec;--neutral-soft:#f6efe4;--disagree-soft:#f3e7ea;` · dark:
`--agree:#7cc79a;--neutral:#e0a95e;--disagree:#d97e93;--agree-soft:#16241c;
--neutral-soft:#2a2214;--disagree-soft:#2c1a1f;`

Animations to port (keyframes): `hpop`, `hfloat`, `hboom`, `hray`, `hbar`, `hbreathe`, `hrise`.

---

## 3. Data model changes

All additive and strong_migrations-safe on Postgres (nullable / defaulted column adds, new tables).

| # | Change | Detail |
|---|--------|--------|
| 3.1 | `hujahs.visibility` | integer, not null, default 0. Rails `enum visibility: { visible_public: 0, followers: 1, private_only: 2 }` (avoid the reserved word `public`/`private` as bare enum keys — use safe key names, expose `.public?`-style helpers via custom methods if needed). Applies to **top-level claims**; replies inherit parent. |
| 3.2 | `hujahs.allow_debates` | boolean, not null, default true. |
| 3.3 | `hujahs.conviction_count` | integer, not null, default 0. Denormalized aggregate for the badge. |
| 3.4 | `votes.conviction` | boolean, not null, default false. Per-voter lock. |
| 3.5 | `hashtags` | table: `name` (citext or lower-cased string, unique index), `hujahs_count` integer default 0. |
| 3.6 | `hashtag_hujahs` | join: `hashtag_id`, `hujah_id`, unique composite index. |

Backfill: none required (all defaults). Migrations follow the `strong_migrations` split pattern if
any table is large; these are plain adds so a single migration each is fine.

### 3.7 Model behavior
- **Visibility scoping.** `Hujah#visible_to?(viewer)` extends the current account-level check with
  per-post visibility: `private_only` → author only; `followers` → author + accepted followers;
  `visible_public` → existing account-privacy rule. Feed (`Hujah` scopes used by `HujahsController#index`
  and `#show` children) filters accordingly. `HujahPolicy#show?` mirrors it.
- **Allow-debates.** `DebatePolicy#create?` additionally requires `hujah.allow_debates?`. The
  challenge dialog is hidden when `!allow_debates?`.
- **Conviction lock.** `cast_vote(by:, choice:, conviction: false)`:
  - If the voter's existing `Vote.conviction` is true → raise/return a domain error ("vote locked");
    controller renders an unobtrusive alert, no state change.
  - Otherwise append `choice` to the array as today, adjust counters as today, and if
    `conviction` is true set `vote.conviction = true` and increment `hujahs.conviction_count` — all
    in the existing transaction. A conviction vote counts as **exactly 1** toward its stance.
  - Secret ballot preserved: `conviction` is never exposed per-voter to others; the `new_vote`
    notification still carries no `subject_user_id`; only `conviction_count` (aggregate) is shown.
- **Hashtags.** Add `HASHTAG_RE = /(?<!\w)#([\p{L}0-9_]+)/` parsing on `after_save`/commit, mirroring
  `notify_mentions`. Upsert `Hashtag` rows, sync the join, maintain `hujahs_count`. Case-insensitive
  match, canonical stored form lower-cased, display form preserved from first use or normalized —
  decide in plan (recommend: store lower-cased canonical, display with a leading `#` + original-case
  cache column OR just canonical). Chips link to `tag_path(name)`.
- **Body length.** `validates :body, length: { minimum: 8 }, if: -> { parent_id.nil? }`. Replies keep
  presence-only.

---

## 4. Routes

New:
- `GET /t/:name` → `TagsController#show` (hujahs carrying a hashtag; countless pagy like the feed),
  named `tag_path`. Hand-written path with a comment, per the routes-file convention.

Reused (unchanged): `new_hujah_path`, `respond_hujah_path`, `POST /hoojah`, `hujah_path`,
`hujah_votes_path`, `POST /hoojah/:slug/debates`, debate routes.

Vote POST (`hujah_votes_path`) gains an optional `conviction` param (`"1"`), permitted in
`VotesController`.

---

## 5. Surface 1 — New post

### 5.1 Full-page composer (`hujahs/new` + `_compose_form`)
Rebuild to the mockup's "New hoojah" screen, responsive (max-width column, centered, full-bleed on
mobile):
- **Sticky header:** ✕ (back), title "New hoojah", **Post** pill. Post is disabled (faint) until the
  body is ≥8 chars for a top-level claim; enabled state uses `bg-primary` text-white.
- **Author row:** avatar + name + **visibility dropdown** (Public / Followers / Private) — a real
  control writing `hujah[visibility]`. Reuses `ui/_menu`. Only shown for top-level claims; on replies
  the parent card + stance picker take this slot (existing reply behavior preserved).
- **Textarea:** borderless, large (≈21px), auto-grows.
- **Suggested hashtags:** a row of chips = top trending/recent `Hashtag`s (simple query, limit ~3–6).
  Tapping a chip inserts `#Name ` into the textarea (Stimulus). Static empty state if none.
- **"How people will weigh in":** static stance-preview card (agree/neutral/disagree rings). Purely
  decorative.
- **Bottom bar:** image button (non-functional placeholder unless cloudinary is trivially wired —
  default: visual only), **"Allow debates"** toggle writing `hujah[allow_debates]`, "Draft" label
  (visual).
- **Stimulus `composer_controller`:** char count → Post enable/disable, visibility menu open/close +
  selection, hashtag chip insertion, allow-debates toggle state. Progressive enhancement: with JS
  off, the form still submits; Post is not disabled server-side beyond the model validation, and
  visibility/allow-debates render as native `<select>`/checkbox fallbacks.

### 5.2 Inline feed composer (`hujahs/index`)
Add the collapsed→expanded inline composer at the top of the feed:
- **Collapsed:** a pill "What's your hoojah?" with avatar + inert Post.
- **Expanded (on tap):** in-place card with author + visibility pill, textarea, "Min 8 characters to
  post", Post button; a **maximize** button routes to the full-page composer (`new_hujah_path`,
  carrying any typed text via query param or a Turbo action — recommend simple `new_hujah_path` with
  the text preserved client-side into the full-page textarea via a param).
- Same `composer_controller`, `collapsed`/`expanded` handled with a Stimulus value. Posts to the same
  `POST /hoojah`. Turbo: on success, prepend the new hujah card to the feed stream (reuse existing
  create response or add a turbo_stream).

---

## 6. Surface 2 — Single hujah argument (`hujahs/show`)

### 6.1 Header & hero
- Contextual header: back / center label ("Trending in #Tag · N votes" when applicable, else
  "Hoojah") / share / more. Reuse existing share + more (`_share_menu`, dialog controllers).
- Author + claim hero: 46px avatar, name + verified tick (if `user.verified?` exists; else omit tick),
  `@handle · date`, **Follow** button (reuse existing follow control), claim body at ~23px via
  `format_body` (which also renders `@mentions`; extend to linkify `#hashtags`), hashtag chips linking
  to `tag_path`.

### 6.2 Vote hero (`_vote_bars` reworked, or a new `_vote_hero`)
- "Where do you stand?" + aggregate **conviction badge** (`conviction_count`).
- Three tall (~104px) tap targets (agree/neutral/disagree), each with %+count below, and a combined
  results bar. Existing `button_to` remains the no-JS fallback (tap = normal vote).
- **`conviction_controller` (Stimulus, progressive enhancement):**
  - `pointerdown` starts a charge timer + ring animation (`hbar`/stroke-dashoffset), showing the
    "charging {stance}" overlay.
  - Release before threshold → cancel (no vote). Tap (quick press/release under a small threshold)
    → submit a **normal** vote (`conviction` absent).
  - Hold to completion → play boom (`hboom`/`hray`/`hpop`) and submit the vote with `conviction=1`.
  - Submission goes through the existing votes endpoint (fetch/Turbo) so the `_vote_bars` turbo-stream
    replacement still works. Guard: if the voter is already conviction-locked, the controller shows
    the lock state and does not re-post.
- Turbo stream response updates counts, percentages, the results bar, conviction badge, and the
  "your vote" state.

### 6.3 Debates, responses, composer
- **Debates section:** restyle existing `_debate_card` list to the mockup (Live pill w/ breathing dot,
  concluded rows, "See all N concluded"). Hidden entirely when `!allow_debates?` **and** no debates
  exist; otherwise show existing debates read-only.
- **Responses:** keep `response_filter_controller` (all/agree/neutral/disagree). Restyle `_child_card`
  to the 6px stance-left-border card with upvote/reply counts and a **Challenge** action (or
  **"In debate"** badge when the response already has a live debate). Challenge hidden when parent
  `!allow_debates?`.
- **Argument composer bar** (sticky bottom) — new `argument_composer_controller` with three states:
  - `locked`: "Vote to join the argument" + 3 stance mini-buttons that cast a vote first. **Enforced**:
    `HujahPolicy#create?` for a reply now requires the viewer has voted on the parent. Server-side
    guard + client-side lock.
  - `collapsed`: "Make your argument…" pill + mini stance picker + send → expands.
  - `expanded`: stance row (defaults to the viewer's current stance) + textarea + send; maximize opens
    the full-screen **Respond** overlay (mockup's `argOverlay`): parent-claim quote, big stance
    picker, large textarea, "Posting as {stance}". Submits `POST /hoojah` with `body`+`parent_id`+
    `vote`.
  - No-JS fallback: the existing "Add hoojah" → `respond_hujah_path` full-page flow stays as the
    baseline; the composer bar is the enhanced inline version.

---

## 7. Testing & acceptance

Each track ships with specs; whole thing gated by `bin/ci`.
- **Models:** visibility scoping (`visible_to?` matrix), allow-debates gate, conviction lock
  (second change after conviction raises; counters unchanged; `conviction_count` increments once),
  hashtag parse/sync (`hujahs_count`, idempotent re-save, unicode/underscore), 8-char validation
  (top-level only).
- **Requests:** composer create with visibility + allow_debates; vote with/without conviction; tag
  feed; reply blocked before voting (policy).
- **System (Cuprite, `js: true`):** inline feed composer expand + post; conviction hold-to-charge
  commits a locked vote and quick tap casts a normal vote; theme toggle persists across reload;
  argument composer locked→collapsed→expanded→post; respond overlay.
- **Tailwind gotchas:** md5 the built bundle before/after comment-only edits; every new interpolated
  utility safelisted; a spec asserting compiled CSS uses `TailwindBuild.once!`. Verify dark/scheme
  tokens actually emit.
- **Quality gates:** `standardrb`, `brakeman`, `bundler-audit`, prosopite N+1 count not regressed
  beyond baseline.

## 8. Rollout / build tracks (subagent-driven, Fable-architected)

Independent tracks, parallelizable, each TDD + independent review:
1. **Theming & tokens** — `application.css` bridge, root attrs, no-FOUC script, `theme_controller`.
2. **Migrations & models** — visibility, allow_debates, conviction (+count), validations, `cast_vote`.
3. **Hashtags** — model, join, parser, `TagsController`, `format_body` linkify, suggested-tags query.
4. **Surface 1** — full-page composer + inline feed composer + `composer_controller`.
5. **Surface 2** — hero, vote hero + `conviction_controller`, responses/debates restyle, argument
   composer + `argument_composer_controller` + respond overlay.

Ordering: track 1 and 2 first (foundational), 3 alongside, then 4 and 5 consume them. Final
integration + `bin/ci` + independent code-review pass before merge on a feature branch.

## 9. Open items to confirm during planning
- Hashtag canonicalization (store lower-cased canonical + display cache vs. canonical-only).
- Whether a verified tick exists on `User` (else omit).
- Image-attach button: visual-only vs. wire to existing cloudinary controller (default visual-only).
- Scheme switcher surface (navbar menu vs. settings) — minimal exposure required, not a full screen.
