# Hoojah 2026 Full-App Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the remaining ~11 app surfaces (Auth, Feed home, Trending, Discover, 5 Debate
screens, Notifications, Profile, Dashboard) onto the Hoojah 2026 visual language, plus build one
net-new feature (visibility-safe full-text search); render honest real-data substitutes for six
deferred systems.

**Architecture:** Server-rendered Hotwire (Turbo + Stimulus over importmap, no Node build for JS).
The 2026 token bridge (`data-theme`×`data-scheme` → `bg-agree`/`bg-card`/`text-ink`…) is already
shipped; screens compose those utilities and never hardcode stance hex. Progressive-enhancement
baseline: every write works JS-off via `button_to`/`form`; Stimulus/Turbo enhance. Pundit per-action
`authorize`; every restyled reader keeps its private/block visibility gate unchanged. Build in five
dependency-ordered phases, each gated on `bin/ci` green + a Fable/leak audit.

**Tech Stack:** Rails 8.1 / Ruby 3.4.9 (mise), Hotwire, Devise, Pundit, Pagy `:countless`,
Tailwind v4 (`tailwindcss-rails`), lucide-rails, rack-attack, RSpec + FactoryBot + Cuprite, prosopite.

**Spec:** `docs/superpowers/specs/2026-08-24-hoojah-2026-full-app-redesign-design.md`.
**Design source:** Claude Design project `9e95c0a1-b6b7-409b-8bce-3b4a95143877` (`Hoojah 2026.dc.html`);
decoded copy for this session at `…/scratchpad/Hoojah-2026.dc.html` (section→line map in the spec).

> **This plan incorporates three specialist reviews** (rails-simplifier, better-stimulus,
> rails-security-auditor). Their load-bearing corrections are baked into the tasks below — most
> importantly the `Hujah.visible_to(viewer)` SQL scope (Task 2.1) that search MUST reuse, because the
> per-post `visibility` enum is a second visibility axis on top of account privacy and there is no
> reusable SQL gate today.

---

## Conventions for every task

- **Run tests** (mise + warnings-off):
  ```bash
  source .mise-build-env.sh
  RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec <path>
  ```
  Inner loop: add `--exclude-pattern "spec/system/**/*"`. Phase gate = `bin/ci`.
- **Never hardcode stance hex.** Use `bg-agree`/`text-neutral`/`bg-disagree-soft`. Interpolated
  class families need `@source inline` in `app/assets/tailwind/application.css`.
- **Rounding (2026):** `rounded-2xl` cards, `rounded-3xl` heroes, `rounded-xl` chips/tiles/inputs,
  `rounded-full` pills (Tailwind static utilities, no safelist).
- **Visibility is load-bearing.** `Hujah#visible_to?` (hujah.rb:35-45) gates BOTH account privacy
  (`user.visible_to?`) AND the per-post `visibility` enum (`visible_public`/`followers_only`/
  `private_only`), and replies recurse through the parent. Any SQL that lists hujahs/users for display
  MUST reproduce this exactly (Task 2.1 builds the canonical scope) and keep the block filter
  (`hidden_user_ids`). New readers get **named leak specs**.
- **SQL search is ILIKE with `sanitize_sql_like`.** FORBIDDEN: `where("body ILIKE '%#{q}%'")` (raw
  interpolation) and `where("body ILIKE ?", "%#{q}%")` **without** `sanitize_sql_like` (unescaped
  `%`/`_` wildcards → `%` matches everything). REQUIRED form:
  `where("body ILIKE ?", "%#{sanitize_sql_like(q)}%")`.
- **CSRF/route placement:** all new routes are top-level main routes (CSRF on), never under
  `Api::V1` (which is `null_session`). Gate check each phase.
- **Preserve** debate pinned `dom_id`s (`:transcript`,`:composer`,`:status`,`:actions`,`:verdict`)
  and the derived (never-stored) round/phase/turn logic.
- **Registration:** controllers autoload via `eagerLoadControllersFrom` in `index.js` — **no manual
  `application.register`**; creating a controller at the conventional path is sufficient.
- **Commit** per task, subject `Slice 2026 Phase N.M: <what>`. No Claude/Anthropic branding.
- Icons: `lucide_icon("name", class: "w-4 h-4")`.

---

## Phase 0 — Foundation (chrome, tokens, shared partials)

### Task 0.1: Safelist the `-soft` stance utilities
**Files:** Modify `app/assets/tailwind/application.css` (after the `@source inline` block ~line 102);
Test `spec/helpers/design_system_helper_spec.rb`.
- [ ] **Step 1 — failing test:** assert `bg-agree-soft text-agree bg-neutral-soft bg-disagree-soft
  text-disagree bg-primary-soft` each `TailwindBuild.emitted?` after `TailwindBuild.once!`.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement:** add `@source inline("{bg,text,border}-{agree,neutral,disagree,primary}-soft");`
- [ ] **Step 4 — run, expect PASS.** **Step 5 — md5 before/after a comment-only edit doesn't move;
  positive control does (CLAUDE.md gotcha #1). Commit.**

### Task 0.2: `ui/_avatar` gains a gradient tile `variant:` (NOT a size key)
**Files:** Modify `app/views/ui/_avatar.html.erb`, `app/helpers/design_system_helper.rb`,
`app/assets/tailwind/application.css` (`.avatar-tile` in `@layer components`);
Test `spec/helpers/design_system_helper_spec.rb`, `spec/views/ui/_avatar_spec.rb`.
- [ ] **Step 1 — failing test:** `render "ui/avatar", user:, variant: :tile, size: :md` renders a
  `rounded-xl avatar-tile` box with white `ds_initials(user)`, still sized by `size:`. `variant:`
  and `size:` are **orthogonal** (a tile can be any size); `AVATAR_SIZES` is untouched.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement:** `.avatar-tile { background: linear-gradient(135deg, var(--primary),
  #7d92ff); color:#fff; }`. `_avatar` accepts `variant:` (default `:photo`); `:tile` (or no photo)
  renders the gradient initials box at the requested `size:`; keep circular-photo path for
  `:photo` + present photo; preserve the `role="img"`/aria label. Do **not** add `:tile` to
  `AVATAR_SIZES`; add a `variant:` param path in `ds_avatar_classes`.
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 0.3: Shared contextual header partial
**Files:** Create `app/views/shared/_screen_header.html.erb`; Test
`spec/views/shared/_screen_header_spec.rb`.
- [ ] **Step 1 — failing test:** `locals: {title:, back: root_path}` shows the title + a back link
  (`arrow-left`) to `back`; `back: nil` renders no back link; an `action:` block renders in a right
  slot.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement:** sticky `bg-nav backdrop-blur border-b border-hairline`; optional back
  `link_to` (40px hit box), `title` (`text-base font-bold text-ink`), optional right `action` via
  `local_assigns[:action]`; `back = local_assigns.fetch(:back, nil)`.
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 0.4: Restyle `shared/_navbar` to 2026
**Files:** Modify `app/views/shared/_navbar.html.erb`; Test `spec/views/shared/_navbar_spec.rb`.
- [ ] **Step 1 — failing test:** signed-in nav shows logo→root, a filled `bg-card-2 text-neutral
  rounded-xl` `flame` trending button, the theme/scheme pill (`data-controller="theme"`, `sun-moon`
  + `palette`), the tile avatar menu with the pink unread dot when
  `unread_notifications_count > 0`, and `New Claim`; signed-out shows Login + Sign up. Wrapper is
  `bg-nav backdrop-blur border-b border-hairline`.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement:** restyle only; keep links/`<details>` menu/theme pill; avatar via
  `variant: :tile`; preserve nil-photo safety, unread-dot aria rules, `<div class="h-14">` spacer.
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 0.5: Phase 0 gate
- [ ] `bin/ci --skip-system-specs` then `--only-system-specs`; both green (commit any tailwind
  rebuild). **Fable/leak audit** of the Phase 0 diff. (The feed's "Discover" tab is added in Phase 2
  once `search_path` exists.)

---

## Phase 1 — Get started + The feed

### Task 1.1: Auth screens (sign in / sign up / reset) + inline password-reveal
**Files:** Modify `app/views/devise/{sessions,registrations,passwords}/new.html.erb`,
`devise/shared/_links.html.erb`; Create
`app/javascript/controllers/password_visibility_controller.js`; Test
`spec/requests/devise_auth_spec.rb`, `spec/system/auth_redesign_spec.rb`.
- [ ] **Step 1 — failing tests:** (a) `GET /login` renders `user[email]`, `user[password]`,
  `user[remember_me]`, the hero headline text, and an **inert** "Continue with Google" control (not
  a live link); `GET /signup` still renders the `invisible_captcha` subtitle field and
  `user[password_confirmation]`. (b) System: clicking the eye toggle flips the password field `type`
  to `text`.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement** (mockup ~102–137): stance-dot brand row + `image_tag "logo.svg"` + hero
  (`text-2xl font-extrabold`) + subhead; fields as 52px `rounded-xl bg-card-2 border border-field`
  rows with leading `mail`/`lock` icons and a trailing eye button (`type="button"`,
  `data-action="password_visibility#toggle"`, icon names supplied via `data-*` attributes / `static
  classes`, **not** hardcoded in the controller); full-width primary submit
  (`rounded-xl bg-primary text-white shadow`); inline "Forgot password?"; "or" divider; inert Google
  button (`rounded-xl border border-field bg-card`, no href, `type="button"`); footer strip.
  **Freeze** all field names + `invisible_captcha :subtitle`; keep `remember_me` below the primary
  action; apply the same panel to all three screens. `password_visibility_controller`: `field`
  target, `toggle()` flips `type` + swaps the icon named in markup; **no manual registration**.
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 1.2: Vote widget redesign — `_vote_bars` (feed)
**Files:** Modify `app/views/hujahs/_vote_bars.html.erb`; Test `spec/views/hujahs/_vote_bars_spec.rb`
+ existing votes request/system specs.
- [ ] **Step 1 — failing test:** renders (a) a single segmented aggregate bar (three stance segments,
  inline `width:N%` = agree/neutral/disagree %), (b) a stance-coloured percent legend, (c) three
  `button_to` vote buttons (`thumbs-up`/`minus`/`thumbs-down`, `rounded-xl border-[1.5px]
  border-<stance> text-<stance>`, `active:scale-95`) posting to the **unchanged** vote path with the
  **unchanged** Turbo target (`dom_id` replace still works).
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement** (mockup ~228–247): percentages from the denormalized counters
  (guard 0/0 → 0). Preserve the current form action/method/Turbo target exactly.
- [ ] **Step 4 — run, expect PASS (existing votes system spec still green). Step 5 — commit.**

### Task 1.3: Feed hujah card + header restyle
**Files:** Modify `app/views/hujahs/_hujah_card.html.erb`, `app/views/hujahs/_hujah_header.html.erb`;
Test `spec/views/hujahs/_hujah_card_spec.rb`, feed request spec.
- [ ] **Step 1 — failing test:** card is `rounded-2xl bg-card shadow` with tile avatar, name,
  `@handle · date`, a `more-vertical` menu, claim body (`text-lg`), the new `_vote_bars`, and a
  counts footer (total votes `bar-chart-3`, responses `message-circle`, and — when the hujah has an
  active debate — a `swords` count + a "Jump in →" pill to the hujah). No verified badge.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement** (mockup ~217–247). Debate presence from Task 1.5's preload. `_hujah_header`
  = tile avatar + name + `@handle · date` + `more-vertical` → existing share/flag menu.
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 1.4: Live-debate strip partial
**Files:** Create `app/views/hujahs/_live_debate_strip.html.erb`; render from `_hujah_card` when an
active debate exists; Test `spec/views/hujahs/_live_debate_strip_spec.rb`.
- [ ] **Step 1 — failing test:** given a hujah with an `active` debate, renders under the card
  (`bg-disagree-soft` accent) with "@challenger vs @opponent · Round N", a "Live" pill (**no watcher
  count**), and a `chevron-right` link to the debate; no active debate → renders nothing.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement** (mockup ~248–252) using `debate.current_round` + participant handles.
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 1.5: Feed active-debate preload (no N+1)
**Files:** Modify `app/controllers/hujahs_controller.rb` (`index`), `app/models/hujah.rb`; Test
`spec/requests/hujahs_spec.rb` (prosopite clean), `spec/models/hujah_spec.rb`.
- [ ] **Step 1 — failing test:** a feed of N hujahs each with an active debate issues no per-card
  debate query; `hujah.active_debate` (fed by the preload) returns the active debate or nil.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement:** one `Debate.active.where(hujah_id: ids)` indexed by hujah_id, exposed
  via a memoized reader passed to the card. Keep the existing visibility/block feed filters intact.
- [ ] **Step 4 — run, expect PASS (prosopite: no new N+1). Step 5 — commit.**

### Task 1.6: Inline composer polish
**Files:** Modify `app/views/hujahs/_inline_composer.html.erb`,
`app/javascript/controllers/composer_controller.js`; Test existing composer system + request specs.
- [ ] **Step 1 — failing test:** collapsed pill expands on click, keeps the JS-off-safe native
  `<select>` visibility control, shows "Min 8 characters to post", `maximize-2` → `new_hujah_path`;
  card `rounded-2xl`; expand adds the `hrise` class.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement** (mockup ~177–214): restyle; apply the animation via `static classes =
  ["hrise"]` / `classList.add`, **not** a hardcoded literal; native select retained.
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 1.7: Phase 1 gate
- [ ] `bin/ci` green. **Fable/leak audit** of the Phase 1 diff — confirm the active-debate preload
  respects private/block filters; no vote-privacy regression.

---

## Phase 2 — Discover (search) + Trending

### Task 2.1: `Hujah.visible_to(viewer)` + `User.visible_to(viewer)` SQL scopes (load-bearing)
**Files:** Modify `app/models/hujah.rb`, `app/models/user.rb`; Test `spec/models/hujah_spec.rb`,
`spec/models/user_spec.rb` (**leak-focused**).
- [ ] **Step 1 — failing tests** (must match `Hujah#visible_to?` exactly, top-level only):
  - `Hujah.visible_to(V)` includes a `visible_public` post by a public author; **excludes** a public
    author's `followers_only`/`private_only` post from a non-follower; includes them for an accepted
    follower and for the owner; excludes a private author's posts from a non-follower; excludes a
    blocked/blocking author's posts (`hidden_user_ids`); scope is `parent_id: nil` only.
  - `Hujah.visible_to(nil)` (anonymous) returns only `visible_public` posts by non-private authors;
    a `followers_only` post is excluded for anon.
  - `User.visible_to(V)` excludes private accounts not visible to V and blocked pairs; `visible_to(nil)`
    excludes all private accounts.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement (literal SQL — do NOT reconstruct the recursive reply check):**
```ruby
# Hujah — top-level visibility for list surfaces (search). Replies excluded on purpose:
# Hujah#visible_to? recurses through parent.visible_to?, which is not expressible here.
scope :visible_to, ->(viewer) {
  base = where(parent_id: nil).joins(:user)
  if viewer
    ids = viewer.following_ids # accepted-only
    base.where(
      "(users.private = FALSE OR hujahs.user_id = :s OR hujahs.user_id IN (:f)) AND " \
      "(hujahs.visibility = 0 OR hujahs.user_id = :s OR (hujahs.visibility = 1 AND hujahs.user_id IN (:f)))",
      s: viewer.id, f: ids.presence || [-1]
    ).where.not(user_id: viewer.hidden_user_ids)
  else
    base.where(visibility: :visible_public).where(users: {private: false})
  end
}
```
```ruby
# User — visibility for list surfaces (search).
scope :visible_to, ->(viewer) {
  if viewer
    where("users.private = FALSE OR users.id = :s OR users.id IN (:f)",
          s: viewer.id, f: viewer.following_ids.presence || [-1])
      .where.not(id: viewer.hidden_user_ids)
  else
    where(private: false)
  end
}
```
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 2.2: Search route + controller + rack-attack throttle + feed Discover tab
**Files:** Modify `config/routes.rb`, `config/initializers/rack_attack.rb`,
`app/views/hujahs/_feed_tabs.html.erb`; Create `app/controllers/search_controller.rb`; Test
`spec/requests/search_spec.rb`, `spec/requests/rate_limit_spec.rb`.
- [ ] **Step 1 — failing tests:** `GET /search?q=x` → 200, public (works signed out),
  `skip_authorization` (no Pundit failure); empty `q` renders the browse/trending state.
  The feed renders three tabs (For you / Following / **Discover** → `search_path`). A `search/ip`
  throttle limits anonymous requests (assert 429 past the limit, mirroring the existing rate specs).
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement:**
  - Route: `get "/search", to: "search#index", as: :search` (top-level, CSRF on).
  - `rack_attack.rb`: `SEARCH_PATH = throttled_path("search")` + `throttle("search/ip", limit: 30,
    period: 1.minute) { |req| req.ip if req.get? && req.path == SEARCH_PATH }` (use `throttled_path`,
    never a hand-rolled matcher — it handles the `(.:format)` suffix).
  - Controller: `@query = params[:q].to_s.strip; skip_authorization`; when present, set
    `@hujahs/@users/@hashtags` from the Task 2.3 scopes; always set `@browse_hashtags =
    Hashtag.order(hujahs_count: :desc).limit(20)`.
  - `_feed_tabs`: add the Discover tab → `search_path` (3 tabs, 15px, indigo underline active).
- [ ] **Step 4 — run, expect PASS (with Task 2.3 scopes stubbed to `none` until 2.3). Step 5 — commit.**

### Task 2.3: `Hujah.search` / `User.search` / `Hashtag.search` (reuse `visible_to`) + leak specs
**Files:** Modify `app/models/hujah.rb`, `app/models/user.rb`, `app/models/hashtag.rb`; Test
`spec/models/hujah_search_spec.rb`, `spec/models/user_search_spec.rb` (**hard leak gate**).
- [ ] **Step 1 — failing tests (leak-focused, from the security review C2):**
  - `Hujah.search("q", viewer:)` matches `body ILIKE %q%` **within `Hujah.visible_to(viewer)`** — so a
    public author's `followers_only`/`private_only` matching post is NOT returned to a non-follower or
    to anon; a private author's post is excluded; a blocked pair's post is excluded; **replies never
    appear** (scope is top-level).
  - `User.search("q", viewer:)` matches `username`/`full_name ILIKE` **within `User.visible_to(viewer)`**.
  - `Hashtag.search("q")` matches `name ILIKE`.
  - A query of `"%"` (wildcard) matches literally, not everything (proves `sanitize_sql_like`).
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement** (reuse Task 2.1 scopes; parameterized ILIKE only):
```ruby
# Hujah
scope :search, ->(q, viewer:) {
  visible_to(viewer).where("hujahs.body ILIKE ?", "%#{sanitize_sql_like(q)}%").limit(8)
}
# User
scope :search, ->(q, viewer:) {
  like = "%#{sanitize_sql_like(q)}%"
  visible_to(viewer).where("username ILIKE :l OR full_name ILIKE :l", l: like).limit(8)
}
# Hashtag
scope :search, ->(q) { where("name ILIKE ?", "%#{sanitize_sql_like(q)}%").order(hujahs_count: :desc).limit(8) }
```
  Wire `SearchController#index` to `Hujah.search(@query, viewer: current_user)` etc.
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 2.4: Search views + live-suggest Stimulus + `_follow_button surface:`
**Files:** Create `app/views/search/index.html.erb`, `_result_hashtag`, `_result_hujah`,
`_result_user`, `_hashtag_chips` (one consolidated chip partial), `index.turbo_stream.erb`;
`app/javascript/controllers/search_controller.js`; Modify `app/views/users/_follow_button.html.erb`
(add `surface:` — see Task 4.3, land it here if Phase 4 not yet reached); Test
`spec/system/search_spec.rb`, view specs.
- [ ] **Step 1 — failing tests:** results render three typed cards (hashtag `hash` tile, hujah
  `message-circle` tile + `format_body` snippet, user avatar tile + follower count + outline Follow
  pill via `_follow_button surface: :card`); one `_hashtag_chips` partial renders both the
  trending-hashtags list and the browse cloud, linking to `/t/:name`. System: typing debounced-reloads
  a Turbo Frame of suggestions; **JS-off** = a plain GET submit returns the same results.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement** (mockup ~881–935): a `<form>` GET to `search_path` **wrapping** a Turbo
  Frame (`id="search-results"`) so a native submit already targets the frame. `search_controller.js`:
  a `debounce` timer stored on the instance, cleared in `disconnect()`, that calls the form's
  `requestSubmit()` (NOT manual `frame.src` string-building). Matched-substring highlight in
  `text-primary`. One chip partial only (simplifier: don't triple-partial hashtags).
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 2.5: Trending rich view (full page) — reuse `Hujah.trending`
**Files:** Create `app/views/trending/_trending_rich.html.erb`; Modify
`app/views/trending/index.html.erb` (page uses rich partial; sidebar frame keeps `_trending`); Test
`spec/requests/trending_spec.rb`, view spec.
- [ ] **Step 1 — failing test:** `/trending` renders a rank-1 gradient hero (`rounded-3xl`, rank,
  vote count, claim) + rank 2–4 `rounded-2xl` cards from **`Hujah.trending`'s existing result set**
  (no second query, no new filter); vote count = `agree+neutral+disagree`. The feed sidebar frame
  still renders the minimal `_trending` unchanged. No period toggle / %-delta / category data.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement** (mockup ~816–878). Category chips = top hashtags → `/t/:name`.
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 2.6: Phase 2 gate
- [ ] `bin/ci` green (brakeman 0 — verify no raw-interpolated ILIKE). Confirm `search_path` is a main
  route, not under `Api::V1`. **rails-security-auditor + Fable/leak audit** focused on `Search`:
  every leak-spec case green; anonymous + `followers_only` excluded; throttle active.

---

## Phase 3 — Debates

### Task 3.1: `debates.opening_argument` column
**Files:** Create migration `add_opening_argument_to_debates`; Modify `app/models/debate.rb`; Test
`spec/models/debate_spec.rb`.
- [ ] **Step 1 — failing test:** a debate created with `opening_argument` present posts it as the
  challenger's opening turn inside `accept!` (mover then correctly flips to the opponent, round/phase
  derivation unchanged); absent → today's exact flow (no auto turn). `DebateTurn` has only a
  presence validation, so `opening_argument` needs **no length cap** — mirror presence only when it
  becomes a turn.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement:** `add_column :debates, :opening_argument, :text` (nullable); `accept!`
  (inside its existing lock/transaction, after it sets `active`) creates the challenger's position-1
  turn from it when present.
- [ ] **Step 4 — run, expect PASS (existing derived-phase specs still green). Step 5 — commit.**

### Task 3.2: Debate create page (supersede the dialog)
**Files:** Modify `config/routes.rb` (`get "/hoojah/:slug/debates/new", as: :new_hujah_debate`),
`app/controllers/debates_controller.rb` (`new`, extend `create`), Create `app/views/debates/new.html.erb`;
Test `spec/requests/debates_spec.rb`, `spec/system/debate_create_spec.rb`.
- [ ] **Step 1 — failing tests:** `GET …/debates/new?argument_id=` renders opponent card, motion
  blockquote, a rounds **2/3/5** segmented picker (default 3), a **static** "spectators decide" info
  row and a **static** timer info row (deferred — no persisted value, no toggle behaviour), and an
  opening-argument textarea + char counter. `POST rounds_limit=5` + `opening_argument` creates a
  pending debate; `rounds_limit=1` or `6` → 422 (existing model validation, **server-enforced**, not
  trusted from the UI); a forged `argument_id` (not on this hoojah) → 422 with `skip_authorization`
  before the return (existing invariant).
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement** (mockup ~945–1019): `create` authorizes the **built `@debate` instance**
  (`authorize @debate, :create?` — SECURITY-FINDINGS invariant #2, so Pundit resolves `DebatePolicy`
  on the instance) and permits a **flat** `.permit(:argument_id, :challenger_stance, :rounds_limit,
  :opening_argument)` (no nested `require(:debate)` that could widen keys). Keep the
  argument-belongs-to-hoojah 422 + rack-attack challenge throttle. **Rounds picker: try CSS-only
  first** — native radios styled via `peer-checked:` utilities (already safelisted pattern); only add
  a Stimulus controller if live cross-field state is truly needed. Char counter reuses
  `argument_composer_controller`.
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 3.3: Debate pending (accept/decline) screen
**Files:** Create `app/views/debates/_debate_pending.html.erb`; Modify `app/views/debates/show.html.erb`
(render when `@debate.pending?`); Test `spec/system/debate_spec.rb`, view spec.
- [ ] **Step 1 — failing test:** for the opponent on a pending debate, `show` renders the avatar trio
  (center `swords`), headline, motion blockquote, a rules card (rounds — real; "spectators decide" —
  static; **no timer row**), and Accept (primary) + Decline (outline) via the existing
  `accept_debate_path`/`decline_debate_path` `button_to`s. Preserve pinned `dom_id(:actions)`/`(:status)`.
- [ ] **Step 2 — run, expect FAIL. Step 3 — implement** (mockup ~1023–1064) composing `_debate_actions`.
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 3.4: Transcript scoreboard + chat bubbles
**Files:** Modify `app/views/debates/_debate_status.html.erb`, `_debate_transcript.html.erb`,
`_debate_turn.html.erb`, `_turn_composer.html.erb`; Test `spec/system/debate_spec.rb`, view specs.
- [ ] **Step 1 — failing test:** active `show` renders a VS scoreboard (challenger | "Round N of M ·
  VS · <phase>" | opponent) from `current_round`/`current_phase`/`rounds_limit`, a Live pill
  (`hbreathe` dot), turns as **alternating bubbles** with a speaker-stance-coloured "Phase · @handle"
  label; composer (for `current_turn_user`) = pill + circular `send`. **No countdown, no lean bar.**
  Real-time append still lands in `dom_id(:transcript)`.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement** (mockup ~1068–1148): `_debate_turn` bubble variant with a `side` derived
  from author vs challenger; stance-coloured phase label (deliberate override of the DS byline-only
  rule — note it in the partial comment). Preserve pinned dom_ids + the broadcast path.
- [ ] **Step 4 — run, expect PASS (Cable broadcast test still green). Step 5 — commit.**

### Task 3.5: Spectator view (styled read-only)
**Files:** Modify `app/views/debates/show.html.erb` (spectator branch); Test `spec/system/debate_spec.rb`.
- [ ] **Step 1 — failing test:** a non-participant on an **active** debate sees the scoreboard +
  bubbles read-only and a "verdict opens when the debate concludes" note (verdict stays
  concluded-only). **No watcher stack, no typing indicator.**
- [ ] **Step 2 — run, expect FAIL. Step 3 — implement** (mockup ~1152–1214 minus deferred live features).
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 3.6: Verdict winner-hero (concluded)
**Files:** Modify `app/views/debates/_verdict.html.erb`; Test `spec/system/debate_verdict_spec.rb`,
`spec/models/debate_spec.rb`.
- [ ] **Step 1 — failing tests:** for a concluded debate, `_verdict` renders a gradient winner-hero
  (`rounded-3xl`, crown over winner avatar, "Winner" chip, dimmed loser, single result bar from
  `verdict_tally`, "Decided by N spectators over M rounds"); closing statements (two cards from the
  final closing turns); a Share button (reuse `share`). A tie → "Draw" hero (no crown). Eligible
  spectators still see the vote buttons pre-vote. **Secret ballot:** the bar reuses the existing
  `verdict_tally` aggregate only (no per-voter data). **k=5 note:** the verdict bar reuses the
  existing public tally with **no new suppression** — this matches today's shipped `_verdict`
  behaviour (public percentages at any N); tightening it (small-N spectator de-anonymisation) is the
  pre-existing SECURITY-FINDINGS 2a item and stays out of scope. State this in the partial comment.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement** (mockup ~1216–1275): winner = max `verdict_tally` (explicit draw);
  closings via `final_position`/closing-phase turns; crown inline SVG; reuse `debate_verdicts#create`
  + `dom_id(:verdict)`.
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 3.7: Phase 3 gate
- [ ] `bin/ci` green. **Fable/leak audit** — verdict secret-ballot invariant, pinned dom_ids intact,
  derived phase math unaffected by the 2/3/5 picker and the opening-argument turn.

---

## Phase 4 — You

### Task 4.1: Notifications — filter tabs + mark-all-read (scope-only, no param row-selection)
**Files:** Modify `config/routes.rb` (`patch "/notifications/read_all", as: :read_all_notifications`),
`app/controllers/notifications_controller.rb`, `app/views/notifications/index.html.erb`; Test
`spec/requests/notifications_spec.rb`.
- [ ] **Step 1 — failing tests:** `PATCH /notifications/read_all` marks only the caller's unread rows
  read via `policy_scope` and returns a Turbo Stream refreshing the list + nav dot. **Negative case:**
  a request carrying a foreign/forged notification id in params still affects **only** the caller's
  rows (the action accepts **no** id/`ids[]` param — scope-only). `GET /notifications?filter=mentions`
  scopes to mention categories; `?filter=debates` to debate categories; default all. Header shows
  title + "Mark all read" + three filter pills.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement:** `read_all` = `policy_scope(Notification).unread.update_all(read: true)`
  (+ Turbo Stream), authorize consistent with the controller's existing pattern; **no param-driven
  row selection.** `index` maps `filter` → category sets.
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 4.2: Notification card restyle (tiles, avatars, inline actions)
**Files:** Modify `app/views/notifications/_notification_card.html.erb`; Test
`spec/views/notifications/_notification_card_spec.rb`.
- [ ] **Step 1 — failing test:** rows `rounded-2xl` with the 5px read/unread accent (existing
  `border-read`/`border-unread`), a 36px soft-tint icon tile (`bg-<stance>-soft text-<stance>`) or an
  avatar tile for user-actor categories, stance-word inline colouring, a trailing unread dot on
  unread rows, inline Accept/Decline for `debate_challenge` (existing paths). Trash moves to overflow
  (no visible per-row button). `new_vote` still carries no `subject_user_id` (secret ballot).
- [ ] **Step 2 — run, expect FAIL. Step 3 — implement** (mockup ~1284–1367): category→icon/tint map.
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 4.3: `_follow_button` `surface:` local (path unchanged across branches)
**Files:** Modify `app/views/users/_follow_button.html.erb`; Test `spec/views/users/_follow_button_spec.rb`.
- [ ] **Step 1 — failing test:** `surface: :gradient` → solid-white pill (`bg-white text-primary`);
  `surface: :card` (default) → outline-primary pill. All states (Follow / Following / Requested /
  Unblock / Block secondary) preserved under both. **The `button_to` path + method are byte-identical
  across both branches** (only CSS classes branch — no duplicated route, no `link_to`+JS POST that
  would bypass CSRF).
- [ ] **Step 2 — run, expect FAIL. Step 3 — implement:** `surface = local_assigns.fetch(:surface,
  :card)`; branch class strings only.
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 4.4: Profile header + conviction card + live-debate (visual restyle)
**Files:** Modify `app/views/users/show.html.erb`, `_profile_header.html.erb`, `_gated_header.html.erb`;
reuse `_live_debate_strip`; Modify `app/controllers/users_controller.rb` (`show` provides active
debate + votes-cast/conviction values); Test `spec/requests/users_spec.rb`,
`spec/system/profile_redesign_spec.rb`.
- [ ] **Step 1 — failing tests:** header is the gradient treatment (back/share/settings action bar
  via `_screen_header`; ring tile avatar; Follow white pill via `surface: :gradient`; round
  secondary; badge chips). Body renders a conviction card showing **real votes-cast**
  (`current-profile user.votes.count`) + **conviction count** (existing aggregate) — **no
  level/streak**; a live-debate card when an active debate exists. Gated header keeps its strict
  whitelist unchanged.
- [ ] **Step 2 — run, expect FAIL. Step 3 — implement** (mockup ~1368–1455, minus tabs — Task 4.5).
  Keep the owner edit `<dialog>` surfaced via the settings gear. No new columns.
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 4.5: Profile count tabs (Hoojahs / Responses / Debates) — Turbo Frame `?tab=`
**Files:** Modify `app/views/users/show.html.erb` (tab bar + framed list), `app/controllers/users_controller.rb`;
Create `app/javascript/controllers/…` only if a native `<a>`+frame can't do it; Test
`spec/requests/users_spec.rb`, `spec/system/profile_redesign_spec.rb`.
- [ ] **Step 1 — failing tests:** three tab links — Hoojahs (`user.hujahs.where(parent_id: nil).count`),
  Responses (`user.hujahs.where.not(parent_id: nil).count`), Debates
  (`challenged_debates.count + defended_debates.count`) — switch the list below via `?tab=` (works
  JS-off as separate requests) inside a Turbo Frame (no full reload with JS). Counts are plain
  association counts (no query object, no new columns). prosopite clean.
- [ ] **Step 2 — run, expect FAIL. Step 3 — implement:** frame-wrapped list keyed on `params[:tab]`
  (default hoojahs); tab links are `link_to … data: {turbo_frame: …}` (native, JS-off = plain nav).
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 4.6: Analytics dashboard restyle + Followers KPI (NOT in UserAnalytics)
**Files:** Modify `app/views/analytics/show.html.erb`, `_stat.html.erb`, `_distribution_bar.html.erb`
(stacked variant), `app/controllers/analytics_controller.rb`; Test `spec/models/user_analytics_spec.rb`
(provenance unchanged), `spec/requests/analytics_spec.rb`.
- [ ] **Step 1 — failing tests:** `show` renders a KPI pair — **Total votes received** (existing
  `UserAnalytics#total_votes_received`) + **Followers** (`current_user.followers.count`, computed in
  the controller/view, **NOT** added to `UserAnalytics` — that class's contract is "never touch votes
  **or users**") — via restyled `_stat` (value `text-ink`, **no delta**); a Top-hoojah card using a
  **stacked** distribution bar (from `distributions`, k=5 suppression kept); the per-hoojah list
  retained below; a back arrow via `_screen_header`. **No 7-day chart.** The `UserAnalytics`
  SQL-provenance test still shows no `votes` read / no JOIN to votes.
- [ ] **Step 2 — run, expect FAIL. Step 3 — implement** (mockup ~1456–1510): stacked
  `_distribution_bar` variant (single track, three stance segments); keep the 3-row form where used.
- [ ] **Step 4 — run, expect PASS. Step 5 — commit.**

### Task 4.7: Phase 4 gate + program close
- [ ] `bin/ci` green (full run). **Fable/leak audit** of Phase 4. Update
  `docs/superpowers/HANDOVER.md` with the redesign status + the deferred backlog (spec §7). Re-run
  prosopite; confirm no new N+1 beyond baseline.

---

## Self-review notes (author)

- **Spec coverage:** every §5 screen maps to a task; search = Tasks 2.1–2.4 (visibility scope →
  route/throttle/tab → search scopes → views). Deferred systems appear only as static/omitted
  substitutes.
- **Review corrections folded in:** (simplifier) query on models not a `Search` namespace, `visible_to`
  SQL scope, `variant:`≠size, one hashtag chip partial, split profile tabs (4.5), Discover tab moved
  to Phase 2, merged the trivial password task into 1.1, `followers_count` via `user.followers.count`;
  (better-stimulus) no manual registration, `search` `disconnect()` + `requestSubmit()` + frame-wraps-form,
  CSS-only rounds picker first, `static classes` for `hrise`, icon names in markup, `type="button"`;
  (security) literal visibility predicate incl. per-post enum + top-level-only (2.1/2.3), leak-spec
  cases (2.3), forbidden ILIKE anti-pattern (conventions + 2.3), `search/ip` throttle (2.2), instance-
  authorize + flat permit + server-side rounds bounds (3.2), `read_all` scope-only + negative spec
  (4.1), `_trending_rich` reuses `Hujah.trending` (2.5), follow path unchanged across surfaces (4.3),
  k=5 verdict decision stated (3.6), route-placement gate checks (2.6/4.x).
- **Type consistency:** `Hujah.visible_to(viewer)`, `User.visible_to(viewer)`, `Hujah.search(q,
  viewer:)`, `User.search(q, viewer:)`, `Hashtag.search(q)`, `hujah.active_debate`,
  `debates.opening_argument`, `_follow_button surface:`, `search_path`, `read_all_notifications_path`
  used consistently.
