# Hoojah 2026 — Full-App Redesign (design spec)

_Date: 2026-08-24. Status: approved scope, pending spec review._

Source of truth: the Claude Design project **"UI/UX modernization 2026"**
(`Hoojah 2026.dc.html`, project `9e95c0a1-b6b7-409b-8bce-3b4a95143877`). A decoded copy of
the canvas and the three extraction reports that fed this spec are the working references.

## 1. Goal & context

Bring the **whole** Hoojah app onto the 2026 visual language. The prior "Hoojah 2026 redesign"
(already merged to `master`) shipped the **theming groundwork** — the `data-theme`×`data-scheme`
token bridge, dark mode, Spectrum/Signal/Ballot schemes, the no-FOUC head script, the
`theme_controller` — plus three surfaces: the **compose (new-post)**, **single-hujah**, and
**respond** screens. This spec covers the **remaining ~11 screens** across five design sections:

| Section | Screens | Prior status |
|---|---|---|
| Get started | Auth (sign in / sign up / reset) | new |
| The feed | Feed home, Single hoojah, Respond, Compose | Single/Respond/Compose ✅; **Feed new** |
| Discover | Trending, Discover (search + hashtags) | new |
| Debates | create, challenge (accept/decline), transcript, spectator, verdict | new |
| You | Notifications, Profile, Analytics dashboard | new |

This is fundamentally a **restyle** of already-functional surfaces, **plus one approved net-new
feature (full-text search)**, plus a set of derivable-data additions. It is explicitly **not** a
re-platform: the mockups depict several net-new *systems* that are DEFERRED (§3).

## 2. Design foundations (already shipped — consume, don't rebuild)

- **Token bridge** (`app/assets/tailwind/application.css`): every `bg-agree`/`bg-card`/`text-ink`/
  `border-hairline`/`bg-*-soft`/`text-ink-2`/`text-faint`/`bg-surface`/`bg-card-2` utility
  resolves through the runtime `--*` vars and **retints per theme×scheme** because the bridge is
  `@theme inline`. New screens compose these utilities; they must **never** hardcode stance hex.
- **Keyframes** `hpop hfloat hboom hray hbar hbreathe hrise` exist for vote FX, bar fills,
  live-dot pulse, and composer expand.
- **Stimulus** controllers present: `composer`, `conviction`, `argument_composer`, `theme`,
  `dialog`, `response_filter`, `share`, `debate_composer`, `cloudinary_upload`.
- **Helpers** `DesignSystemHelper`: `ds_button_classes`, `ds_card_classes`, `ds_avatar_classes`,
  `ds_menu_item_classes`, `ds_initials`, `ds_debate_state_color`.
- **UI primitives** `ui/_card` (layout partial — `render layout:`), `_avatar`, `_divider`,
  `_empty_state`, `_menu`.
- Request pipeline: Pundit per-action `authorize`/`skip_authorization` (enforced), pagy
  `:countless`, HTML/Turbo surfaces keep CSRF on (`Api::V1` is the only `null_session` surface).

### 2.1 Deliberate house-style overrides for 2026

1. **Rounding.** The shipped DS mandates *square* cards. **2026 supersedes this**: cards are
   rounded (`rounded-2xl` ≈16px for cards, `rounded-3xl` ≈24px for heroes, `rounded-xl` ≈12px for
   chips/tiles/inputs, `rounded-full` for pills). These are Tailwind static utilities (no safelist
   needed). Update the DS mirror note (deferred) rather than treating this as drift.
2. **Avatar treatment.** 2026 uses a **rounded-square gradient initials tile**
   (`linear-gradient(135deg,var(--primary),#7d92ff)`, white initials) as the default actor mark,
   alongside real photos where present. Add a `variant: :tile` path to `ui/_avatar` /
   `ds_avatar_classes` (gradient via an `@layer components` class, e.g. `.avatar-tile`), so photo
   and tile variants share one call site. Circular photos remain valid where a real photo exists.
3. **Vote widget.** The feed's per-stance 3-row circular widget (`hujahs/_vote_bars`) is replaced
   by the 2026 form: **(a)** one segmented aggregate bar (all three stances in a single 9px track,
   2px gaps, widths = %) + a stance-coloured percent legend, and **(b)** three pill vote buttons
   (icon + label, 1.5px stance border, `active:scale-95`). The single-hujah `_vote_hero` (already
   shipped) is the reference; the feed adopts a compact sibling. Stance-name interpolation stays
   safelisted.

### 2.2 Safelist additions (`@source inline`)

The soft-tint icon tiles (notifications, search results, debate stance chips) interpolate
`bg-#{stance}-soft text-#{stance}`. The bare stance utilities are safelisted but the **`-soft`
variants are not**. Add:

```
@source inline("{bg,text,border}-{agree,neutral,disagree,primary}-soft");
```

Verify with the CLAUDE.md md5-before/after discipline (comment-only edits must not move the bundle;
positive control confirms the harness works). No other interpolated families are introduced —
`rounded-*` and the gradient tile are static/`@layer`.

## 3. Scope boundary (the core decision)

### 3.1 BUILD now
Restyle every surface + build search + the derivable-data additions listed per-screen in §5.

### 3.2 Real-data SUBSTITUTES (render honestly, never fake)
Where a mockup element needs a deferred system, render a truthful substitute:
- **Watcher/“N watching” counts, typing indicators** → omit.
- **Turn countdowns ("1:42 left")** → omit; turns stay untimed.
- **Conviction "Lvl 7 / 70% to Lvl 8 / 12-day streak"** → show real **votes cast** (count of the
  user's votes) and **conviction count** (existing aggregate); no level/streak.
- **Analytics 7-day chart + WoW deltas** → KPI pair (votes received, followers) + Top-hoojah
  stacked distribution bar; **no time series** (preserves the `UserAnalytics` no-`votes`-read
  privacy guarantee).
- **Trending period toggle / %-deltas / category chips** → ranked cards with **real vote counts** +
  hashtag chips linking to `/t/:name`.
- **Verdict during an active debate / live lean-bar** → verdict stays **concluded-only** (secret
  ballot); active spectator view is styled read-only.

### 3.3 DEFERRED systems (tracked follow-ups, out of scope this program)
Turn timers + expiry job; live presence/typing/watcher counts; verdict-during-active + live
lean-bar; conviction levels/streaks gamification; analytics time-series + deltas; trending
period/category/delta data; per-tag vote-delta ranking. Each is logged in §7.

### 3.4 Confirmed product decisions
- **Auth Google button**: rendered per mockup but **visual-only / inert** (no OmniAuth). Keep the
  existing `devise/shared/_links` omniauth block behaviour (no providers → nothing wired).
- **Debate rounds picker**: offers **2 / 3 / 5**; `rounds_limit ≥ 2` validation and derived
  phase math untouched.
- **Password reveal**: small `password_visibility` Stimulus controller (progressive enhancement).
- **Remember-me**: retained (below the primary action), though the mockup omits it.
- **Verified badge**: no "verified" concept exists → omitted (not faked).

## 4. Navigation & chrome

There is **no bottom tab bar** in the mockups — navigation is a sticky blurred **top** header
(logo + actions) plus a segmented **"For you / Following / Discover"** tab row on the feed, plus
per-screen contextual headers (back/close + title + action). This maps onto the existing paradigm:

- **`shared/_navbar`** stays the single global nav. Restyle to 2026: logo, a filled `flame`
  trending icon-button, the **theme/scheme pill kept** (it drives the very themes the design
  demonstrates — the mockup omits it but the app needs it), avatar (tile variant) with the pink
  unread dot + `<details>` menu, `New Claim`. Blurred `bg-nav`, hairline.
- **`hujahs/_feed_tabs`** gains a **third tab, "Discover"**, routing to the new search/discover
  surface (`For you` = global, `Following` = following feed, `Discover` = `search_path`).
- **Contextual headers**: each inner screen (debate, profile, dashboard, search) renders its own
  sticky header partial (back link + title + optional action), styled `bg-nav`/blur/hairline.
  Device chrome (status bar, notch, home indicator) is **always dropped**.

## 5. Per-screen design specs

Each screen: **translation** (visual notes) + **files** (touched/new) + **data** (new needs).
Progressive-enhancement baseline: every write works JS-off via `button_to`/form; Stimulus/Turbo
enhance.

### Phase 0 — Chrome & foundation
- Restyle `shared/_navbar`; add `ui/_avatar` tile variant + `.avatar-tile` component class;
  add the `-soft` safelist line; introduce shared **contextual header** partial
  (`shared/_screen_header` with `title:`, `back:`, `action:` locals).
- Update `_feed_tabs` (3 tabs). Rounding sweep helper: confirm `ds_card_classes` emits
  `rounded-2xl` for 2026 card consumers (audit call sites so the shipped square-card screens
  either adopt rounding intentionally or stay as-is — decide per §2.1).

### Phase 1 — Get started + The feed

**Auth · sign in / sign up / reset** — `app/views/devise/{sessions,registrations,passwords}/new.html.erb`,
`devise/shared/_links`, `_error_messages`.
- Translation: stance-dot brand row + logo + hero headline (`text-2xl`/800) + subhead; 52px
  icon-shell fields (`rounded-xl`, `bg-card-2`, `border-field`, leading Lucide `mail`/`lock`,
  trailing `eye` on password); full-width primary button (`rounded-xl`, `bg-primary`, shadow);
  inline "Forgot password?"; "or" divider; inert styled "Continue with Google"; footer sign-up
  strip. All three screens share the panel treatment; update in lockstep.
- **Freeze** field names (`user[email/password/password_confirmation/remember_me]`) and
  `invisible_captcha :subtitle` on registration.
- Data: none. New: `password_visibility` Stimulus controller.

**Feed · home** — `hujahs/index`, `_feed_tabs`, `_inline_composer`, `_hujah_card`,
`_hujah_header`, `_vote_bars` (→ redesign), + new `_live_debate_strip`.
- Translation: sticky top nav (§4); 3 feed tabs; inline composer restyle (keep the JS-off-safe
  native `<select>` visibility control, add `hrise` expand, `maximize-2` → `new_hujah_path`);
  hujah cards `rounded-2xl` with tile avatar, name, `@handle · date`, `more-vertical` menu, claim
  body (`text-lg`/650, primary-highlighted phrase optional/skipped — no highlight data);
  **vote-widget redesign** (§2.1.3); counts footer (`bar-chart-3` total, `message-circle`
  responses, `swords` + debate count, "Jump in →" pill when a debate exists); optional
  **live-debate strip** beneath a card that has an active debate.
- Data: **active-debate lookup per feed hujah** — a scoped query (`Debate.active` joined to the
  hujah/argument) exposed to the feed without N+1 (preload; watch prosopite). No watcher counts.

### Phase 2 — Discover

**Discover · search & hashtags** — **NEW** `SearchController` + `search#index` + views;
route `GET /search` (HTML/Turbo, CSRF on, `skip_authorization` — public read). Compose existing
`Tag` (`/t/:name`, `hujahs_count`) and `Hujah.trending`.
- Translation: "Discover" header + search field (`rounded-xl`, focus `border-primary`, `search`
  icon); **"Top matches"** result cards for three types — hashtag (`hash` tile, count), hujah
  (`message-circle` tile, `format_body` snippet, author), user (avatar tile, handle, follower
  count, outline Follow pill reusing `_follow_button`); **"Trending hashtags"** grouped card;
  **"Browse hashtags"** chip cloud linking to `/t/:name`.
- Search impl: Postgres `ILIKE` (beta scale) over `hujahs.body` (visible-to-viewer only — reuse
  `Hujah#visible_to?`/policy scope), `users.username`/`full_name` (exclude private per
  `User#visible_to?` + block filter `hidden_user_ids`), `hashtags.name`. Pagy `:countless`.
  **Live-suggest**: a Stimulus `search` controller + Turbo Frame (`src` on debounced input),
  degrading to a normal GET submit JS-off. **Reuse the block/private gates** — search must not
  become a visibility bypass (a `rails-security-auditor`/Fable audit item).
- Data: new controller/policy-free read; matched-substring highlight; result counts.

**Trending** — `trending/index`, `_trending` (the DS-minimal partial is **forked**, not mutated,
because it doubles as the feed sidebar).
- Translation: `flame`/`--neutral` header; **rank-1 gradient hero** (rank, vote count, claim);
  rank 2–4 `rounded-2xl` cards (faint rank numeral, claim, vote count); "Rising fast" micro-label.
  Period toggle / %-delta / category chips → **substitute** (§3.2): drop toggle+delta, category
  chips = top hashtags linking to `/t/:name`. **Sidebar keeps the minimal list** (new
  `_trending_rich` partial for the full page only).
- Data: vote counts from denormalized counters (exist). No deltas.

### Phase 3 — Debates
All ride `debates/show` + partials; pinned `dom_id`s (`:transcript`,`:composer`,`:status`,
`:actions`,`:verdict`) and derived round/phase/turn logic are **load-bearing — preserve**.

**Debate · create** — supersede `hujahs/_challenge_dialog` with a real `debates/new` page
(`debates#new` + route `GET /hoojah/:slug/debates/new`).
- Translation: close `x` → back to hoojah; "New debate" `swords` header + "Step 1 of 2" pill;
  "Challenging" opponent card; "The motion" blockquote; **Format** panel — rounds `2/3/5`
  segmented picker (§3.4), **timer + spectators-toggle rendered as static info** (deferred:
  spectators always-on, no timer); "Your opening argument" textarea + char counter
  (`argument_composer` style). Sticky footer primary CTA "Send challenge to @handle".
- Controller: `debates#create` permits `:argument_id, :challenger_stance, :rounds_limit` and an
  optional **opening argument body**. **Decision (no ambiguity):** add a nullable
  `debates.opening_argument` text column; `accept!` posts it as the challenger's opening turn when
  present, so an empty field reproduces today's exact flow (opening posted as the first turn after
  accept). This is the only new debate column and is validated for length like a turn body.
  Validate argument belongs to the hoojah (existing 422 path). rack-attack challenge throttle
  unchanged.
- Data: `rounds_limit` already exists (default 4); **new nullable `debates.opening_argument`**.
  No timer/spectator columns (deferred).

**Debate · challenge (accept/decline)** — new `pending` layout for `debates/show`
(`_debate_pending` partial) composing existing `accept!`/`decline!`.
- Translation: back header + "Pending" pill; avatar trio with center `swords` badge; headline;
  stance subtext; motion blockquote; **rules card** (rounds — real; "spectators decide" — static;
  timer row **omitted**); Accept (primary) + Decline (outline) via existing `button_to`s
  (`accept_debate_path`/`decline_debate_path`).

**Debate · transcript (participant, live)** — `debates/show`, `_debate_transcript`,
`_debate_turn`, `_debate_status`, `_turn_composer`.
- Translation: back + `swords` "@x vs @y / On '…'" + Live pill (`hbreathe` dot); **VS scoreboard**
  card (challenger | Round N of M · VS · phase | opponent) from `current_round`/`current_phase`/
  `rounds_limit`; turn banner "@x's turn" (**no countdown**); **chat-bubble turns** — alternating
  alignment, speaker-stance-coloured "Phase · @handle" label (this **reverses** the DS
  `DebateTurn` byline-only rule — a deliberate 2026 override, note it in the partial); pill
  composer + circular `send` (shown to `current_turn_user`; else waiting note). Spectator-lean bar
  → **omit while active** (§3.2). Real-time append rides the existing Cable broadcast.
- Data: none new; watcher/lean/countdown omitted.

**Debate · spectator view** — same `debates/show` for non-participants.
- Translation: watcher avatar stack + typing indicator → **omit** (deferred); styled read-only
  scoreboard + bubbles; footer = **concluded-only** verdict affordance styled (during active:
  a "verdict opens when the debate concludes" note, matching current concluded-only rule).

**Debate · verdict (concluded)** — `_verdict`.
- Translation: "Concluded" pill; **winner-hero** gradient card (crown SVG over winner avatar,
  "Winner" chip, dimmed loser, single result bar from `verdict_tally`, "Decided by N spectators
  over M rounds"); **closing statements** (two cards from the final closing turns via
  `final_position`/closing phase); **Share** button (reuse `share` controller / share menu).
  Winner derivation = highest tally (draw handling explicit). Secret ballot preserved.
- Data: reuse `verdict_tally`, `rounds_limit`, final turns. Winner is derived, not stored.

### Phase 4 — You

**Notifications** — `notifications/index`, `_notification_card`; new bulk mark-all-read action +
filter scope.
- Translation: sticky header "Notifications" + **"Mark all read"** (new `PATCH
  /notifications/read_all` bulk action, `policy_scope`d to own rows); **filter tabs**
  All/Mentions/Debates (server `?filter=` scope → categories); rows = `rounded-2xl` card + 5px
  read/unread accent (existing `border-read`/`border-unread` via `ui/_card` stance) + **36px
  soft-tint icon tile** (`bg-#{stance}-soft`/`text-#{stance}`) or **avatar tile** for user-actor
  categories + copy (stance word inline-coloured) + trailing unread dot; inline Accept/Decline for
  `debate_challenge` (currently only follow-request is inline). Keep trash in an overflow, not a
  visible per-row button.
- Data: category→filter mapping; bulk update. Secret ballot: `new_vote` still carries no
  `subject_user_id`.

**Profile** — `users/show`, `_profile_header`, `_gated_header`, `_follow_button`, `_profile_edit`;
new count-tabs + live-debate card.
- Translation: **gradient** header (`160deg` primary→#5b74f0) with header action bar (back /
  share / settings-gear → owner edit `<dialog>`); rounded-square ring avatar; name/handle/bio/
  meta (`map-pin`/`globe`); **Follow = solid white pill** + round secondary (lock/notify) reusing
  `_follow_button` states (Following/Requested/Unblock); badge chips (`bg-white/18`).
  **`_follow_button` takes a `surface:` local** (`:gradient` → solid-white pill for the profile
  header; `:card` → outline-primary pill for search-result rows), so the same partial+states serve
  both contexts without divergence.
  Body: **conviction card** rendering real **votes cast** + **conviction count** (no level/streak
  — §3.2); **count tabs** Hoojahs/Responses/Debates (derivable counts; each switches the list via
  Turbo Frame, JS-off = separate `?tab=` requests); live-debate card if an active debate exists;
  hujah cards with stance accent. Gated header keeps its strict whitelist.
- Data: votes-cast (`user.votes.count` or a counter), responses count (child hujahs), debates
  count; active-debate lookup. All derivable — no new columns.

**Analytics · dashboard** — `analytics/show`, `_stat`, `_distribution_bar`, `UserAnalytics`.
- Translation: back header "Your dashboard"; **KPI pair** — Total votes received (exists) +
  **Followers** (new metric, from `User`) with `_stat` restyle (value `text-ink`, label,
  **no delta** — §3.2); **Top-hoojah** card with a **stacked distribution bar** (new
  `_distribution_bar` stacked variant) from `distributions` (order by votes; k=5 suppression
  kept); keep the existing per-hoojah list below. **7-day chart → omitted** (privacy).
- Data: add `followers_count` to `UserAnalytics` (reads `users`/`follows`, never `votes` — keeps
  the SQL-provenance test green: assert it still touches no `votes`/JOIN-to-votes). No time series.

## 6. Testing strategy

- **Restyle screens**: request specs assert the new structural affordances render (tabs, buttons,
  tiles, states) and that **visibility/authorization gates are unchanged** — every reader keeps its
  private/block gate (feed, show, profile, search, trending, debate transcript). Named leak specs
  for the **new** search surface (must not surface private/blocked hujahs or users) — a hard gate.
- **Search**: model/query spec (ILIKE over visible-only), request spec (results + pagination +
  visibility exclusions), a Cuprite system spec (type → suggestions → navigate; JS-off GET).
- **New actions**: `notifications#read_all` (own-rows only), debate `new`/create with
  `rounds_limit` (2/3/5 valid; 1 and 6 rejected), verdict winner derivation (incl. draw).
- **Tailwind**: `-soft` safelist reaches the bundle (`TailwindBuild.emitted?`); comment-only edits
  don't move md5.
- **prosopite**: no new N+1 from the feed active-debate lookup, search, or profile tabs (preload).
- Gate each phase on **`bin/ci`** green (all StandardRB/brakeman/bundler-audit + full suite +
  tailwind build). Keep brakeman at 0 (search input → parameterized ILIKE, never string-built SQL).

## 7. Deferred backlog (tracked, out of scope)

Turn timers + expiry job (+ rounds/phase re-derivation); live presence/typing/watcher counts;
verdict-during-active + live lean-bar; conviction levels/streaks gamification; analytics
time-series + WoW deltas; trending period toggle + %-deltas + category-tag data; per-tag vote-delta
ranking; verified-account concept; re-mirror `docs/design-system/` to the 2026 rounded/schemed
language; the pre-existing carried items (votes array→scalar, `require_master_key`, `rack-cors`).

## 8. Orchestration plan

Build via **subagent-driven development with Fable orchestration**, phase by phase (§5). Per phase:
1. **Fable architecture/visibility audit** of the phase's planned changes (as the prior redesign's
   Fable-5 audit caught 5 visibility-leak surfaces pre-implementation) — special focus on the
   **search** surface and every restyled reader keeping its private/block gate.
2. Parallel **subagent implementers** per screen/partial (isolated files where possible).
3. **Independent code-review** pass (`superpowers:code-reviewer`), batched fixes.
4. **`bin/ci`** green before the phase merges.

Phase order: **0 Chrome → 1 Feed+Auth → 2 Discover(search)+Trending → 3 Debates → 4 You.**
