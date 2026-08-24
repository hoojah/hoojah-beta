# Hoojah 2026 Full-App Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the remaining ~11 app surfaces (Auth, Feed home, Trending, Discover, 5 Debate
screens, Notifications, Profile, Dashboard) onto the Hoojah 2026 visual language, plus build one
net-new feature (full-text search); render honest real-data substitutes for six deferred systems.

**Architecture:** Server-rendered Hotwire (Turbo + Stimulus over importmap, no Node build for JS).
The 2026 token bridge (`data-theme`×`data-scheme` → `bg-agree`/`bg-card`/`text-ink`…) is already
shipped; screens compose those utilities and never hardcode stance hex. Progressive-enhancement
baseline: every write works JS-off via `button_to`/`form`; Stimulus/Turbo enhance. Pundit per-action
`authorize`; every restyled reader keeps its private/block visibility gate unchanged. Build in five
dependency-ordered phases, each gated on `bin/ci` green.

**Tech Stack:** Rails 8.1 / Ruby 3.4.9 (mise), Hotwire, Devise, Pundit, Pagy `:countless`,
Tailwind v4 (`tailwindcss-rails`), lucide-rails, RSpec + FactoryBot + Cuprite, prosopite.

**Spec:** `docs/superpowers/specs/2026-08-24-hoojah-2026-full-app-redesign-design.md`.
**Design source:** Claude Design project `9e95c0a1-b6b7-409b-8bce-3b4a95143877` (`Hoojah 2026.dc.html`);
decoded copy for this session at `…/scratchpad/Hoojah-2026.dc.html` (section→line map in the spec).

---

## Conventions for every task

- **Run tests** (mise + warnings-off):
  ```bash
  source .mise-build-env.sh
  RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec <path>
  ```
  System specs are `js: true` (Cuprite). Skip them in the inner loop with
  `--exclude-pattern "spec/system/**/*"`. Phase gate = `bin/ci` (all quality gates + full suite +
  tailwind build).
- **Never hardcode stance hex.** Use `bg-agree`/`text-neutral`/`bg-disagree-soft` etc. Interpolated
  class families must be safelisted in `app/assets/tailwind/application.css` (`@source inline`).
- **Rounding (2026):** `rounded-2xl` cards, `rounded-3xl` heroes, `rounded-xl` chips/tiles/inputs,
  `rounded-full` pills. These are Tailwind static utilities (no safelist).
- **Preserve** the debate pinned `dom_id`s (`:transcript`,`:composer`,`:status`,`:actions`,
  `:verdict`) and the derived (never-stored) round/phase/turn logic.
- **Visibility is load-bearing.** Any query that reads hujahs/users for display MUST keep the
  existing private (`visible_to?`) + block (`hidden_user_ids`) filters. New readers (search) get
  named leak specs.
- **Commit** after each task with a `Slice 2026 Phase N.M: <what>` subject. No Claude/Anthropic
  branding in commit messages.
- Icons: `lucide_icon("name", class: "w-4 h-4")`.

---

## Phase 0 — Foundation (chrome, tokens, shared partials)

### Task 0.1: Safelist the `-soft` stance utilities

**Files:**
- Modify: `app/assets/tailwind/application.css` (after line 102, the existing `@source inline` block)
- Test: `spec/helpers/design_system_helper_spec.rb` (or the existing tailwind-build spec file)

- [ ] **Step 1 — failing test.** Add an example asserting the soft tiles compile:
```ruby
it "emits the interpolated soft-tint tile utilities" do
  TailwindBuild.once!
  %w[bg-agree-soft text-agree bg-neutral-soft bg-disagree-soft text-disagree bg-primary-soft].each do |u|
    expect(TailwindBuild.emitted?(u)).to be(true), "expected #{u} in the bundle"
  end
end
```
- [ ] **Step 2 — run, expect FAIL** (`bg-agree-soft` etc. not yet emitted; they're only used via
  interpolation which the scanner can't see):
  `… rspec spec/helpers/design_system_helper_spec.rb -e "soft-tint"`
- [ ] **Step 3 — implement.** Add after the existing stance safelist line:
```css
@source inline("{bg,text,border}-{agree,neutral,disagree,primary}-soft");
```
- [ ] **Step 4 — run, expect PASS.**
- [ ] **Step 5 — md5 discipline check.** Confirm a comment-only edit does not move the bundle and a
  positive control does (per CLAUDE.md gotcha #1). Then **commit.**

### Task 0.2: `ui/_avatar` gains a gradient `:tile` variant

**Files:**
- Modify: `app/views/ui/_avatar.html.erb`, `app/helpers/design_system_helper.rb` (`ds_avatar_classes`)
- Modify: `app/assets/tailwind/application.css` (add `.avatar-tile` in `@layer components`)
- Test: `spec/helpers/design_system_helper_spec.rb`, `spec/views/ui/_avatar_spec.rb` (create if absent)

- [ ] **Step 1 — failing test.** `ds_avatar_classes(size: :tile)` returns a class string containing
  `avatar-tile rounded-xl` and the initials render white; a spec that renders
  `render "ui/avatar", user: user, variant: :tile` shows `ds_initials(user)` on a `.avatar-tile`.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement.**
  - `.avatar-tile { background: linear-gradient(135deg, var(--primary), #7d92ff); color: #fff; }`
    in `@layer components`.
  - `_avatar.html.erb`: accept `variant:` local (`:photo` default, `:tile`). When `:tile` OR the
    user has no photo, render a `rounded-xl avatar-tile` box with `ds_initials(user)`; keep the
    circular photo path for `:photo` + present photo. Preserve the existing `role="img"`/aria label.
  - `ds_avatar_classes`: add a `:tile` size/variant returning `avatar-tile rounded-xl` sizing.
- [ ] **Step 4 — run, expect PASS.** **Step 5 — commit.**

### Task 0.3: Shared contextual header partial

**Files:**
- Create: `app/views/shared/_screen_header.html.erb`
- Test: `spec/views/shared/_screen_header_spec.rb`

- [ ] **Step 1 — failing test.** Rendering with `locals: {title: "Your dashboard", back: root_path}`
  shows the title, a back link (`arrow-left`) to `back`, and (with `action:` block) a right slot.
  With `back: nil` no back link renders.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement.** Sticky `bg-nav backdrop-blur border-b border-hairline` header:
  optional back `link_to` (lucide `arrow-left`, 40px hit box), `title` (`text-base font-bold
  text-ink`), optional right `action` via `content_for`/block local. Use
  `local_assigns.fetch(:back, nil)` and `local_assigns[:action]`.
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 0.4: Restyle `shared/_navbar` to 2026

**Files:**
- Modify: `app/views/shared/_navbar.html.erb`
- Test: `spec/views/shared/_navbar_spec.rb` (create) + existing request specs that assert nav links

- [ ] **Step 1 — failing test.** Signed-in render shows: logo→root; a filled `flame` trending
  icon-button; the theme/scheme pill (`data-controller="theme"`, `sun-moon` + `palette`); avatar
  **tile** menu with the unread pink dot when `unread_notifications_count > 0`; `New Claim`. Signed
  out: Login + Sign up. Assert the theme controller + trending link + `bg-nav` wrapper survive.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement.** Keep structure/links/`<details>` menu and the theme pill; restyle to
  `bg-nav backdrop-blur border-b border-hairline` (was `bg-card/90 … border-gray-100`), render the
  avatar via `variant: :tile`, make trending a filled `bg-card-2 text-neutral rounded-xl` icon
  button. Preserve `render "ui/avatar"` (nil-photo safety), the unread-dot aria rules, and the
  `<div class="h-14">` spacer.
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 0.5: `_feed_tabs` gains the Discover tab

**Files:**
- Modify: `app/views/hujahs/_feed_tabs.html.erb`
- Test: `spec/requests/hujahs_spec.rb` (or feed request spec) — assert 3 tabs + the Discover link

- [ ] **Step 1 — failing test.** The feed renders three tabs — "For you" (`?filter=` global,
  active by default), "Following" (`?filter=following`), "Discover" (`search_path`). Active tab has
  the `text-primary` underline.
- [ ] **Step 2 — run, expect FAIL** (`search_path` undefined yet — stub the link as `"#"` in this
  task's implementation and switch to `search_path` in Task 2.1; OR order Task 2.1 first. **Do
  0.5 after 2.1** to avoid the undefined route.) Mark this task **blocked-by 2.1**.
- [ ] **Step 3 — implement.** Three tabs, 15px, indigo underline on active; labels For you /
  Following / Discover; Discover → `search_path`.
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 0.6: Phase 0 gate

- [ ] Run `bin/ci --skip-system-specs` then `bin/ci --only-system-specs`; both green. Commit any
  tailwind rebuild. **Fable/leak audit** of Phase 0 diff before merge.

---

## Phase 1 — Get started + The feed

### Task 1.1: `password_visibility` Stimulus controller

**Files:**
- Create: `app/javascript/controllers/password_visibility_controller.js`
- Modify: `app/javascript/controllers/index.js` (register) — or confirm eager autoload
- Test: `spec/system/auth_redesign_spec.rb` (create; covers the eye toggle in Task 1.2's system spec)

- [ ] **Step 1 — implement** (better-stimulus reviewed): a controller with a `field` target and a
  `toggle()` action flipping `type` between `password`/`text` and swapping the `eye`/`eye-off`
  icon. No values needed beyond targets.
- [ ] **Step 2 — register** in `index.js` if the app uses manual registration (check the file).
- [ ] **Step 3 — commit** (system assertion lands with Task 1.2).

### Task 1.2: Auth screens (sign in / sign up / reset)

**Files:**
- Modify: `app/views/devise/sessions/new.html.erb`, `app/views/devise/registrations/new.html.erb`,
  `app/views/devise/passwords/new.html.erb`, `app/views/devise/shared/_links.html.erb`
- Test: `spec/system/auth_redesign_spec.rb`, `spec/requests/devise_auth_spec.rb` (create if absent)

- [ ] **Step 1 — failing tests.** (a) Request spec: `GET /login` renders `user[email]`,
  `user[password]`, `user[remember_me]`, the hero headline text, and an inert
  "Continue with Google" control; `GET /signup` still renders the `invisible_captcha` subtitle field
  and `user[password_confirmation]`. (b) System spec: on `/login`, clicking the eye toggle changes
  the password field `type` to `text`.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement** (mockup lines ~102–137): stance-dot brand row (`bg-agree/neutral/
  disagree` 12px dots) + `image_tag "logo.svg"` + hero (`text-2xl font-extrabold`) + subhead; the
  two/three fields as 52px `rounded-xl bg-card-2 border border-field` rows with leading `mail`/`lock`
  and a trailing `eye` wired to `password_visibility`; full-width primary submit
  (`rounded-xl bg-primary text-white shadow`); inline "Forgot password?"; "or" divider; inert
  Google button (`rounded-xl border border-field bg-card`, no href/disabled — NOT a live link);
  footer sign-up/sign-in strip. **Freeze** all field names + `invisible_captcha :subtitle`. Keep
  `remember_me` below the primary action. Apply the same panel to all three screens.
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 1.3: Vote widget redesign — `_vote_bars` (feed)

**Files:**
- Modify: `app/views/hujahs/_vote_bars.html.erb`
- Test: `spec/views/hujahs/_vote_bars_spec.rb`, existing votes request/system specs

- [ ] **Step 1 — failing test.** The partial renders (a) a single segmented aggregate bar with three
  stance segments whose inline widths equal the agree/neutral/disagree percentages, (b) a stance-
  coloured percent legend, and (c) three `button_to` vote buttons (agree/neutral/disagree) with
  `thumbs-up`/`minus`/`thumbs-down` icons and `active:scale-95`, each posting to the existing vote
  path. Assert the existing vote POST params/target are unchanged (Turbo Stream still replaces
  `dom_id`). Keep the existing counts semantics.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement** (mockup lines ~228–247): compute percentages from
  `agree_count/neutral_count/disagree_count` (guard divide-by-zero → 0). Segmented bar =
  `flex h-2 rounded-full overflow-hidden gap-[2px]` with three `bg-agree/neutral/disagree` divs at
  `style="width: N%"`. Legend row `text-xs font-bold` per stance. Three vote pill buttons
  (`rounded-xl border-[1.5px] border-agree text-agree` … white fill) via `button_to`, preserving the
  current form action, method, and Turbo target. Interpolated `border-#{stance}`/`text-#{stance}`
  already safelisted.
- [ ] **Step 4 — run, expect PASS.** Confirm the existing votes system spec still passes (in-place
  Turbo replace). **Step 5 — commit.**

### Task 1.4: Feed hujah card + header restyle

**Files:**
- Modify: `app/views/hujahs/_hujah_card.html.erb`, `app/views/hujahs/_hujah_header.html.erb`
- Test: `spec/views/hujahs/_hujah_card_spec.rb`, feed request spec

- [ ] **Step 1 — failing test.** A feed card renders as `rounded-2xl bg-card shadow` with a tile
  avatar, name, `@handle · <date>`, a `more-vertical` menu, the claim body (`text-lg`), the new
  `_vote_bars`, and a counts footer containing total votes (`bar-chart-3`), responses
  (`message-circle`), and — when the hujah has a debate — a `swords` count and a "Jump in →" pill
  linking to the hujah. No verified badge is rendered (no such data).
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement** (mockup lines ~217–247). Use `ds_card_classes` updated for
  `rounded-2xl` (or inline). Header via `_hujah_header` (tile avatar + name + `@handle · date` +
  `more-vertical` → existing share/flag menu). Footer counts + conditional `swords`/Jump-in using a
  debate-count value provided by the controller/preload (Task 1.6). Do NOT add a live-debate strip
  here (Task 1.5).
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 1.5: Live-debate strip partial

**Files:**
- Create: `app/views/hujahs/_live_debate_strip.html.erb`
- Modify: `app/views/hujahs/_hujah_card.html.erb` (render the strip when an active debate exists)
- Test: `spec/views/hujahs/_live_debate_strip_spec.rb`

- [ ] **Step 1 — failing test.** Given a hujah with an `active` debate, the strip renders under the
  card (bottom-rounded, `bg-disagree-soft`/accent) showing "@challenger vs @opponent · Round N", a
  "Live" pill (no watcher count — deferred), and a `chevron-right` link to the debate. Given no
  active debate, nothing renders.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement** (mockup lines ~248–252) using `debate.current_round` and participant
  handles. **No "N watching" count.**
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 1.6: Feed active-debate preload (no N+1)

**Files:**
- Modify: `app/controllers/hujahs_controller.rb` (`index`), `app/models/hujah.rb` (assoc/scope if needed)
- Test: `spec/requests/hujahs_spec.rb` (prosopite clean), `spec/models/hujah_spec.rb`

- [ ] **Step 1 — failing test.** Rendering a feed of N hujahs each with an active debate issues no
  per-card debate query (assert via a query-count/prosopite expectation). A helper
  `hujah.active_debate` returns the active debate or nil.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement.** Add a `has_many :debates`-style path or a preloaded lookup: in
  `index`, preload active debates for the feed hujahs (e.g. a single
  `Debate.active.where(hujah_id: ids)` indexed by hujah_id, exposed through a memoized reader passed
  to the card). Keep the existing visibility/block feed filters intact.
- [ ] **Step 4 — run, expect PASS (prosopite log shows no new N+1). Step 5 — commit.**

### Task 1.7: Inline composer polish

**Files:**
- Modify: `app/views/hujahs/_inline_composer.html.erb`, `app/javascript/controllers/composer_controller.js`
- Test: existing composer system spec (`spec/system/**`), request spec

- [ ] **Step 1 — failing test.** Collapsed pill expands on click (Stimulus), keeps the JS-off-safe
  native `<select>` visibility control, shows "Min 8 characters to post", and the `maximize-2` link
  targets `new_hujah_path`. Card is `rounded-2xl`; expand uses the `hrise` animation.
- [ ] **Step 2 — run, expect FAIL** (mostly styling deltas; keep behavioural asserts green).
- [ ] **Step 3 — implement** (mockup lines ~177–214): restyle to `rounded-2xl`, add `hrise` on
  expand, restyle the visibility select as the primary-soft pill (native select retained for JS-off).
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 1.8: Phase 1 gate

- [ ] `bin/ci` green (gates + system). **Fable/leak audit** of the Phase 1 diff — confirm the feed's
  new active-debate preload respects private/block filters and no vote-privacy regression.

---

## Phase 2 — Discover (search) + Trending

### Task 2.1: Search route + controller + policy-free read

**Files:**
- Modify: `config/routes.rb` (add `get "/search", to: "search#index", as: :search`)
- Create: `app/controllers/search_controller.rb`
- Test: `spec/requests/search_spec.rb`

- [ ] **Step 1 — failing test.** `GET /search?q=transport` returns 200, is public (works signed
  out), and calls `skip_authorization` (no Pundit failure). Empty `q` renders the browse/trending
  state without error.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement.**
```ruby
class SearchController < ApplicationController
  def index
    @query = params[:q].to_s.strip
    skip_authorization
    if @query.present?
      @hujahs   = Search.hujahs(@query, viewer: current_user)
      @users    = Search.users(@query, viewer: current_user)
      @hashtags = Search.hashtags(@query)
    end
    @browse_hashtags = Hashtag.order(hujahs_count: :desc).limit(20)
  end
end
```
- [ ] **Step 4 — run, expect PASS** (with a `Search` service stub returning `[]` until Task 2.2).
  **Step 5 — commit.** Then unblock and finish **Task 0.5** (feed Discover tab → `search_path`).

### Task 2.2: `Search` service — visibility-safe ILIKE

**Files:**
- Create: `app/models/search.rb`
- Test: `spec/models/search_spec.rb` (**named leak specs — hard gate**)

- [ ] **Step 1 — failing tests (leak-focused).**
  - `Search.hujahs("q", viewer:)` matches `body ILIKE %q%` but **excludes** private-author hujahs
    the viewer can't see and **excludes** hujahs by blocked/blocking users (`hidden_user_ids`).
  - `Search.users("q", viewer:)` matches `username`/`full_name` but **excludes** private accounts
    not visible to the viewer and blocked pairs.
  - `Search.hashtags("q")` matches `hashtags.name ILIKE`.
  - Anonymous viewer sees only public/non-private results.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement.** Parameterized `ILIKE` (never string-built SQL — brakeman stays 0):
  `sanitize_sql_like(q)` wrapped `%…%`. Reuse the existing feed visibility predicate for hujahs
  (private → `users.private = false OR user_id IN (viewer.following_ids + [viewer.id])`) and the
  block filter (`where.not(user_id: viewer&.hidden_user_ids || [])`). Users: exclude private not
  visible + blocked. Return limited relations (e.g. 8 each).
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 2.3: Search views + live-suggest Stimulus

**Files:**
- Create: `app/views/search/index.html.erb`, `_result_hashtag`, `_result_hujah`, `_result_user`,
  `_hashtag_chips`; `app/views/search/index.turbo_stream.erb` (suggest frame)
- Create: `app/javascript/controllers/search_controller.js` (debounced frame reload)
- Modify: `app/views/users/_follow_button.html.erb` (add `surface:` local — see Task 4.3)
- Test: `spec/system/search_spec.rb`, view specs

- [ ] **Step 1 — failing tests.** Request/view: results render three typed cards (hashtag `hash`
  tile, hujah `message-circle` tile + `format_body` snippet, user avatar tile + follower count +
  outline Follow pill via `_follow_button surface: :card`). Browse-hashtags chip cloud links to
  `/t/:name`. System: typing debounced-reloads a Turbo Frame of suggestions; with JS off a plain GET
  submit returns the same results.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement** (mockup lines ~881–935). Search `<form>` GET to `search_path` wrapping
  a Turbo Frame (`id="search-results"`); Stimulus `search` controller debounces input and sets the
  frame `src` (`search_path(q:)`); JS-off falls back to submit. Matched-substring highlight in
  `text-primary`.
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 2.4: Trending rich view (full page) + minimal sidebar kept

**Files:**
- Create: `app/views/trending/_trending_rich.html.erb`
- Modify: `app/views/trending/index.html.erb` (use rich partial for the page; sidebar frame keeps
  `_trending`)
- Test: `spec/requests/trending_spec.rb`, view spec

- [ ] **Step 1 — failing test.** `/trending` renders a rank-1 gradient hero (`rounded-3xl`, rank,
  vote count, claim) + rank 2–4 `rounded-2xl` cards (faint rank numeral, claim, vote count from the
  denormalized counters). The feed sidebar frame still renders the minimal `_trending`
  (unchanged). No period toggle / %-delta / category data (deferred).
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement** (mockup lines ~816–878). Vote count = `agree+neutral+disagree` totals.
  Category chips → top hashtags linking to `/t/:name`. Keep `_trending` for the sidebar.
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 2.5: Phase 2 gate

- [ ] `bin/ci` green. **rails-security-auditor + Fable/leak audit** focused on `Search` — verify no
  private/blocked leakage, parameterized SQL, brakeman 0.

---

## Phase 3 — Debates

### Task 3.1: `debates.opening_argument` column

**Files:**
- Create: `db/migrate/XXXX_add_opening_argument_to_debates.rb`
- Modify: `app/models/debate.rb` (validate length like a turn body; consume in `accept!`)
- Test: `spec/models/debate_spec.rb`

- [ ] **Step 1 — failing test.** A debate created with `opening_argument` present posts it as the
  challenger's opening turn on `accept!`; absent → today's flow (no auto turn) is unchanged. Length
  validated.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement.** Nullable `text` column (`add_column :debates, :opening_argument,
  :text`); `accept!` (inside its existing transaction/lock) creates the challenger's first turn from
  it when present. Validate `length` matching turn-body rules.
- [ ] **Step 4 — run, expect PASS (incl. the existing derived-phase specs). Step 5 — commit.**

### Task 3.2: Debate create page (supersede the dialog)

**Files:**
- Modify: `config/routes.rb` (`get "/hoojah/:slug/debates/new" … as: :new_hujah_debate`),
  `app/controllers/debates_controller.rb` (`new`, extend `create` params),
  `app/views/debates/new.html.erb` (create), remove reliance on `hujahs/_challenge_dialog`
- Modify: `app/javascript/controllers/argument_composer_controller.js` (reuse for char counter) or a
  small `debate_format_controller.js` for the segmented pickers
- Test: `spec/requests/debates_spec.rb`, `spec/system/debate_create_spec.rb`

- [ ] **Step 1 — failing tests.** `GET …/debates/new?argument_id=` renders the opponent card, motion
  blockquote, a rounds **2/3/5** segmented picker (default 3), a static "spectators decide" info row
  (no toggle behaviour) and a static timer info row (deferred, no persisted value), and an opening-
  argument textarea with a char counter. `POST` with `rounds_limit=5` + `opening_argument` creates a
  pending debate; `rounds_limit=1` or `6` is rejected (422, existing validation).
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement** (mockup lines ~945–1019). `create` permits `:argument_id,
  :challenger_stance, :rounds_limit, :opening_argument`; keep the argument-belongs-to-hoojah 422 and
  rack-attack throttle. Segmented pickers are Stimulus-enhanced radios (JS-off = native radios).
  Sticky footer submit.
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 3.3: Debate pending (accept/decline) screen

**Files:**
- Create: `app/views/debates/_debate_pending.html.erb`
- Modify: `app/views/debates/show.html.erb` (render pending layout when `@debate.pending?`)
- Test: `spec/system/debate_spec.rb` (extend), view spec

- [ ] **Step 1 — failing test.** For the opponent on a pending debate, `show` renders the avatar trio
  (center `swords`), headline, motion blockquote, a rules card (rounds — real; "spectators decide" —
  static; **no timer row**), and Accept (primary) + Decline (outline) via the existing
  `accept_debate_path`/`decline_debate_path` `button_to`s.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement** (mockup lines ~1023–1064). Compose `_debate_actions` (existing
  accept/decline). Preserve pinned `dom_id(:actions)`/`dom_id(:status)`.
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 3.4: Transcript scoreboard + chat bubbles

**Files:**
- Modify: `app/views/debates/_debate_status.html.erb` (VS scoreboard), `app/views/debates/_debate_transcript.html.erb`,
  `app/views/debates/_debate_turn.html.erb` (bubble variant), `app/views/debates/_turn_composer.html.erb`
- Test: `spec/system/debate_spec.rb`, view specs

- [ ] **Step 1 — failing test.** Active debate `show` renders a VS scoreboard (challenger | "Round N
  of M · VS · <phase>" | opponent) from `current_round`/`current_phase`/`rounds_limit`, a Live pill
  (`hbreathe` dot), and turns as **alternating bubbles** with a speaker-stance-coloured "Phase ·
  @handle" label. The composer (shown to `current_turn_user`) is the pill + circular `send`. **No
  countdown, no lean bar.** Real-time append still lands in `dom_id(:transcript)`.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement** (mockup lines ~1068–1148). `_debate_turn` gains a bubble variant with
  a `side` derived from author vs viewer/challenger; stance-coloured phase label (a deliberate
  override of the DS byline-only rule — note it in the partial comment). Preserve pinned dom_ids and
  the existing broadcast path.
- [ ] **Step 4 — run, expect PASS (Cable broadcast test still green). Step 5 — commit.**

### Task 3.5: Spectator view (styled read-only)

**Files:**
- Modify: `app/views/debates/show.html.erb` (spectator branch), reuse scoreboard + bubbles
- Test: `spec/system/debate_spec.rb` (spectator asserts), request spec

- [ ] **Step 1 — failing test.** A non-participant on an **active** debate sees the scoreboard +
  bubbles read-only and a "verdict opens when the debate concludes" note (verdict stays
  concluded-only). **No watcher stack, no typing indicator** (deferred).
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement** (mockup lines ~1152–1214, minus deferred live features).
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 3.6: Verdict winner-hero (concluded)

**Files:**
- Modify: `app/views/debates/_verdict.html.erb`
- Test: `spec/system/debate_verdict_spec.rb`, `spec/models/debate_spec.rb` (winner derivation)

- [ ] **Step 1 — failing tests.** For a concluded debate, `_verdict` renders a gradient winner-hero
  (`rounded-3xl`) with a crown over the winner avatar, "Winner" chip, dimmed loser, a single result
  bar from `verdict_tally`, and "Decided by N spectators over M rounds"; closing statements (two
  cards from the final closing turns); and a Share button (reuse `share`). A tie renders a "Draw"
  hero (no crown). Secret ballot preserved (no per-voter data). Eligible spectators still see the
  vote buttons before they vote.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement** (mockup lines ~1216–1275). Winner = max `verdict_tally` (explicit draw
  handling); closings via `final_position`/closing-phase turns; crown as inline SVG. Reuse the
  existing `debate_verdicts#create` path + `dom_id(:verdict)`.
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 3.7: Phase 3 gate

- [ ] `bin/ci` green. **Fable/leak audit** — verify verdict secret-ballot invariant, pinned dom_ids
  intact, derived phase math unaffected by the 2/3/5 picker and the opening-argument turn.

---

## Phase 4 — You

### Task 4.1: Notifications — filter tabs + mark-all-read

**Files:**
- Modify: `config/routes.rb` (`patch "/notifications/read_all" … as: :read_all_notifications`),
  `app/controllers/notifications_controller.rb` (`read_all`, `index` filter scope),
  `app/policies/notification_policy.rb` (scope), `app/views/notifications/index.html.erb`
- Test: `spec/requests/notifications_spec.rb`

- [ ] **Step 1 — failing tests.** `PATCH /notifications/read_all` marks only the current user's
  unread notifications read (own-rows only — `policy_scope`), returns a Turbo Stream. `GET
  /notifications?filter=mentions` scopes to mention categories; `?filter=debates` to debate
  categories; default = all. Sticky header shows title + "Mark all read"; three filter pills.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement.** `read_all` = `policy_scope(Notification).unread.update_all(read: true)`
  (+ Turbo Stream refreshing the list/nav dot); `authorize`/`skip_authorization` consistent with the
  controller's existing pattern. `index` maps `filter` → category sets.
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 4.2: Notification card restyle (tiles, avatars, inline actions)

**Files:**
- Modify: `app/views/notifications/_notification_card.html.erb`
- Test: `spec/views/notifications/_notification_card_spec.rb`

- [ ] **Step 1 — failing test.** Rows are `rounded-2xl` with the 5px read/unread accent (existing
  `border-read`/`border-unread`), a 36px soft-tint icon tile (`bg-#{stance}-soft text-#{stance}`) or
  an avatar tile for user-actor categories, stance-word inline colouring, a trailing unread dot on
  unread rows, and inline Accept/Decline for `debate_challenge`. Trash moves to overflow (not a
  visible per-row button).
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement** (mockup lines ~1284–1367). Map categories → icon/tint. `new_vote`
  still carries no `subject_user_id` (secret ballot). Inline debate accept/decline via existing
  paths.
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 4.3: `_follow_button` `surface:` local + white-pill state

**Files:**
- Modify: `app/views/users/_follow_button.html.erb`
- Test: `spec/views/users/_follow_button_spec.rb`

- [ ] **Step 1 — failing test.** `surface: :gradient` → solid-white pill (`bg-white text-primary`);
  `surface: :card` (default) → outline-primary pill. All existing states (Follow / Following /
  Requested / Unblock / Block secondary) preserved under both.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement.** `surface = local_assigns.fetch(:surface, :card)`; branch the class
  strings only; keep the `button_to` targets/states identical.
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 4.4: Profile header + conviction card + count tabs + live-debate

**Files:**
- Modify: `app/views/users/show.html.erb`, `app/views/users/_profile_header.html.erb`,
  `app/views/users/_gated_header.html.erb`; reuse `_live_debate_strip`
- Modify: `app/controllers/users_controller.rb` (`show` provides tab counts + active debate + tab param)
- Test: `spec/requests/users_spec.rb`, `spec/system/profile_redesign_spec.rb`

- [ ] **Step 1 — failing tests.** Profile header is the gradient treatment (back/share/settings
  action bar; ring tile avatar; Follow white pill via `surface: :gradient`; round secondary; badge
  chips). Body renders a conviction card showing **real votes-cast** (`user.votes.count`) and
  **conviction count** (existing aggregate) — **no level/streak**; count tabs (Hoojahs / Responses /
  Debates) with derivable counts switching the list via `?tab=` (JS-off) / Turbo Frame; a live-debate
  card when an active debate exists. Gated header keeps its strict whitelist unchanged.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement** (mockup lines ~1368–1455). Counts: hoojahs = top-level count, responses
  = child hujahs, debates = participant debates. Keep the owner edit `<dialog>` (surfaced via the
  settings gear). No new columns.
- [ ] **Step 4 — run, expect PASS (prosopite clean on the tab counts). Step 5 — commit.**

### Task 4.5: Analytics dashboard restyle + Followers KPI

**Files:**
- Modify: `app/views/analytics/show.html.erb`, `app/views/analytics/_stat.html.erb`,
  `app/views/analytics/_distribution_bar.html.erb` (stacked variant), `app/models/user_analytics.rb`
- Test: `spec/models/user_analytics_spec.rb` (SQL-provenance), `spec/requests/analytics_spec.rb`

- [ ] **Step 1 — failing tests.** `UserAnalytics#followers_count` returns the user's follower count
  and the SQL-provenance test still shows **no `votes` table read / no JOIN to votes** across the
  analytics SELECTs. `show` renders a KPI pair (Total votes received, Followers) via restyled `_stat`
  (value `text-ink`, **no delta**) + a Top-hoojah card using a **stacked** distribution bar (from
  `distributions`, k=5 suppression kept). Per-hoojah list retained below. **No 7-day chart.**
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement** (mockup lines ~1456–1510). `followers_count` reads `follows`/`users`
  only. Stacked `_distribution_bar` variant = single track, three stance segments; keep the 3-row
  form where still used. Header gets a back arrow via `shared/_screen_header`.
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 4.6: Phase 4 gate + program close

- [ ] `bin/ci` green (full 5-min run). **Fable/leak audit** of Phase 4. Update
  `docs/superpowers/HANDOVER.md` with the redesign status + the deferred backlog (§7 of the spec).
  Re-run prosopite; confirm no new N+1 beyond baseline.

---

## Self-review notes (author)

- **Spec coverage:** every §5 screen maps to a task; search (§5 Phase 2) = Tasks 2.1–2.3; deferred
  systems appear only as static/omitted substitutes (no task builds them). ✅
- **Ordering fix:** Task 0.5 (feed Discover tab) is **blocked-by Task 2.1** (`search_path`); execute
  2.1 before finalizing 0.5. Noted in both tasks.
- **Type consistency:** `Search.hujahs/users/hashtags(…, viewer:)`, `hujah.active_debate`,
  `debates.opening_argument`, `_follow_button surface:`, `UserAnalytics#followers_count`,
  `read_all_notifications_path` used consistently across tasks.
