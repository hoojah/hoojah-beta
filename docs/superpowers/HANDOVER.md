# Hoojah — Session Handover

_Last updated: 2026-08-05. Read this first when resuming._

## TL;DR

**Project 1 (Rails 6.0 → 8.1 upgrade + backend modernization) is DONE and merged to `master`.**
The app runs **Rails 8.1.3.1 on Ruby 3.4.9**, suite is **24 examples / 0 failures / 2 pending**,
boots in dev + test. Merge commit: `93a3ff2`. **Not pushed** — run `git push origin master` when ready
(remote is Bitbucket).

Next up: **Project 2 (React SPA → Hotwire)**, then **Project 3 (Hotwire Native)**. Neither started.

---

## Project 2 Slice 1 — Hotwire Foundation — DONE

_Branch: `project-2-hotwire-foundation`. Suite: **50 examples / 0 failures / 2 pending**
(includes request + Cuprite system specs). brakeman **0**; `standardrb` clean;
`bundler-audit` clean (no ignores)._

**What shipped:**
- **Asset/JS foundation:** retired Webpacker/shakapacker/React/Node. Now **importmap-rails +
  Propshaft + Tailwind (`tailwindcss-rails`)** with Turbo + Stimulus. `bin/dev` (Procfile.dev)
  runs Puma + `tailwindcss:watch`.
- **Auth:** hand-rolled sessions replaced with **Devise 5.0.4** (`/login` `/signup` `/logout` +
  password reset). `password_digest` → `encrypted_password`; existing bcrypt `$2a$12$` hashes
  round-trip (stretches=12, no pepper). Emails downcased + unique index. `paranoid=true`.
- **Screens:** server-rendered **feed + single-hujah + threaded responses**, with **Turbo-Stream
  in-place voting** (`button_to` → thin votes controller → `Hujah#cast_vote` → `_vote_bars` replace).
  Client-side response filter + local-time via Stimulus/importmap.
- **Security hardening:** closed the **votes IDOR** (voter derived from `current_user`, not
  `params[:user_id]`), the **hujah-destroy IDOR** (authenticate + owner-only), and the users-`:id`
  **mass-assignment**. Added **rack-attack** throttles (login/signup/password/votes),
  **invisible_captcha** honeypot on signup, and an explicit **CSP with a nonce** (Cloudinary + Drift
  hosts; no `unsafe-inline` on `script-src`). API controllers use `null_session` CSRF via
  `Api::V1::BaseController`.

**Still open / deferred — carry these forward:**
- **Slice 2 scope:** compose/new-hujah form (+ Cloudinary upload + parent-reply), user profile,
  **notifications index + its IDOR fix**, flag modal, social-share menu.
- **Pundit** (Slice 1 authorizes with `before_action`, not policies).
- **prosopite** N+1 detection; the feed/show queries were not yet audited for N+1.
- **Vote model:** `vote` is still an **array** column appended per cast — collapse to a scalar
  (latest stance) in a dedicated migration.
- **Cloudinary URL host validation** on user-supplied photo/link fields.
- **`config.require_master_key`** still commented (finding **L4**) — enable once the deploy provides
  `config/master.key`.
- **`rack-cors` origin tightening** (finding **M1**) — currently permissive; tighten before Project 3
  (native clients).

**Prod-migration awareness (flagged in Phase 1 review):** on a LARGE populated `users` table the
Devise migration's `change_column_null` backfill and the (here **non-concurrent**)
`reset_password_token` unique index would take heavy locks. Fine on this dataset, but re-plan these as
concurrent/batched before a big-table production deploy. (The `email` unique index is already
`algorithm: :concurrently`.)

**Faithfulness note (flagged in Phase 4 review):** feed cards now use the per-stance `_vote_bars`
layout (denser, inline-votable) rather than the old compact 3-segment feed bar — a deliberate
single-partial consolidation (feed and show share one widget). Confirm with the owner whether the
compact feed bar should be restored for the feed later.

**CI/deploy note:** `app/assets/builds/tailwind.css` is **gitignored**; `tailwindcss:build` runs via
the `assets:precompile` hook — every deploy must run `assets:precompile` so the compiled bundle exists.

---

## Project 2 Slice 2 — Features + Pundit — DONE

_Branch: `project-2-slice-2-features`. Suite: **95 examples / 0 failures / 2 pending**
(request + Cuprite system specs). brakeman **0**; `standardrb` clean; `bundler-audit` clean;
`grep -rniE "react|params[:user_id]" app config` clean._

**What shipped:**
- **Compose / respond** — `HujahsController#new/#create` at `/hoojah/new` and
  `/hoojah/:slug/respond`; stance picker; a `Hujah` `after_create_commit` callback notifies the
  parent owner on a reply (replaces the old inline `Notification.create!`), and `has_children?`
  was fixed (`children.exists?`, was always-true).
- **Profile view + edit** — public `/u/:username` + owner edit via a native `<dialog>`;
  `update.turbo_stream.erb` refreshes the header and fires `close_dialog`. Photo upload via a
  **Cloudinary** Stimulus controller (hidden field the widget fills), host-validated server-side.
- **Notifications** — HTML `/notifications` (mark-read → redirect to the hoojah; Turbo-Stream
  delete) and the hardened `Api::V1` endpoint.
- **Flag** — a `<dialog>` reason picker (spam / abusive / irrelevant) → `create.turbo_stream.erb`
  closes the dialog and confirms in place.
- **Share** — server-rendered social intent links (WhatsApp / X / Telegram / Reddit / Facebook /
  Email) that work JS-off, plus a progressively-enhanced Web Share button.
- **Pundit adopted** — `ApplicationPolicy` + `{hujah,notification,user,flag}` policies; app-wide
  `after_action :verify_authorized` (Devise-exempt); Slice 1's `before_action` IDOR checks
  migrated to per-action `authorize` / `policy_scope` / `skip_authorization` across HTML + API.

**Security closed:**
- **Notifications IDOR + leak** — index is now `policy_scope(Notification)` (own rows only);
  update/destroy `authorize` owner-only (was trusting `params[:user_id]`), on both HTML and API.
- **Flags hardened** — `authenticate_user!` + `authorize`; a posted `:user_id` is ignored (the
  flag records under `current_user`).
- **M7 link XSS** — the `link` validation is anchored end-to-end (`%r{\Ahttps?://\S+\z}i`), closing
  the newline-injection brakeman flagged as Format Validation.
- **Photo host validation** — user photo URLs must be `https://res.cloudinary.com/hoojah/…`
  (exact host; blocks `…evil.com`, userinfo `@`, and `http`).

**Still open / deferred — carry these forward:**
- **Vote model:** `vote` is still an **array** column appended per cast — collapse to a scalar
  (latest stance) in a dedicated migration.
- **Serializer N+1 + prosopite:** feed/show + notification serializers not yet N+1-audited; wire
  prosopite in test/dev.
- **ActionCable notification push:** the compose callback creates notifications synchronously; no
  real-time push yet.
- **`config.require_master_key`** still commented (finding **L4**) — enable once the deploy provides
  `config/master.key`.
- **`rack-cors` origin tightening** (finding **M1**) — still permissive; tighten before Project 3.
- **Project 3 — Hotwire Native** (mobile) — not started.

**System-suite note (Phase 6):** headless Chrome hung on the third-party **Cloudinary/Drift**
widget scripts (intermittent `Ferrum::PendingConnectionsError`), so those scripts are **skipped in
the test env** (layout guard) and their hosts are `url_blacklist`ed in the cuprite driver. **Rack::Attack
is disabled for system specs** — its user-keyed throttles read `warden.user` from upstream
middleware, which mis-deserializes the `Warden::Test::Helpers` stash under Devise 5 (a test-harness
artifact; the throttles are covered end-to-end by the request-level `rate_limit_spec`). The system
suite is reliably green across repeated runs (14 examples). No product-behaviour changes in dev/prod.

---

## Project 2 Slice 3 — Social Foundation — DONE

_Branch: `slice-3-social-foundation`. Suite: **113 examples / 0 failures / 2 pending**
(request + Cuprite system specs; system dir is **17 examples**, reliably green across repeated
runs). brakeman **0**; `standardrb` clean; `bundler-audit` clean._

**What shipped:**
- **Follow / unfollow (public)** — `Follow` join (owner forced from `current_user`, self-follow
  blocked at model validation **and** a DB check constraint, uniqueness index for idempotency).
  `FollowsController` (Pundit `FollowPolicy`) responds with a **Turbo Stream** that replaces the
  follow button + follower-count chip in place; `find_or_create_by` + a `RecordNotUnique` rescue
  make a double-click a no-op. A **rack-attack** `follow/user` throttle (20/min/user) caps
  follow↔unfollow churn (which would otherwise spam `new_follower` notifications). Each new follow
  fires a single `new_follower` notification (`after_create_commit`).
- **Followers / following lists** — public `/u/:username/followers` and `/u/:username/following`
  (signed-out viewable), plus counts on the profile header.
- **Following feed** — `Hujah#timeline_for(user)` (own + followed, top-level only); the feed index
  branches to it for a signed-in `?filter=following` request and **falls back to the global feed**
  for an anonymous following request (no 500). A **Following** tab (signed-in only) + empty-state.
- **@mentions** — injection-safe render in `HujahsHelper#format_body`: `@handle`s are **tokenized on
  the raw text BEFORE `simple_format`/`auto_link`**, then substituted as `ERB::Util`-escaped anchors
  keyed on private-use markers — so an `@` inside an auto-linked email/URL is never spliced into
  (email/URL stay intact, hostile handles can't inject a live tag). `Hujah#notify_mentions`
  (`after_create_commit`, create-only) notifies each existing mentioned user **once** (idempotency
  guard, skips self + unknown, caps at 10).

**Test-harness fix (important for future system specs):** `login_as_system` no longer uses
Warden::Test's `login_as`. That injection is **one-shot** (`Warden.on_next_request` is shifted off
after the first request), so the SECOND request in a browser flow lost the login and fell back to
Devise 5.0.4's session deserialiser, which **500s** (`serialize_from_session` wrong arity — "given
10, expected 2"). That is why the pre-existing authenticated system specs (profile owner-edit, votes)
only passed when an earlier example warmed the shared Chrome cookie jar — each fails in isolation on
the old helper. A real-form credential login is **also** rejected in this suite, so `login_as_system`
now registers a **persistent Warden `on_request` hook** (`spec/support/devise.rb`) that re-`set_user`s
the designated user with `store: false` on every request — the user stays authenticated for the whole
flow and the broken serialiser is never touched. No product change; request specs (which use
`sign_in`) are unaffected.

**Still open / deferred — per the program roadmap:**
- **Debate** — the structured debate/argument feature is not built.
- **Analytics** — plus the **`new_vote` voter-identity privacy fix** (vote records/serializers still
  expose voter identity; scope/redact before analytics ship).
- **Badges** — reputation/achievement badges.
- **Trending** — trending hoojahs/topics ranking.
- **Block / mute + private accounts** — no blocking, muting, or protected (approval-gated) follows
  yet; follow is unconditionally public this slice.
- Carried from earlier slices: **Vote array→scalar** migration, **serializer N+1 / prosopite**,
  **ActionCable** real-time push, **`config.require_master_key`** (L4), **`rack-cors`** tightening (M1),
  **Project 3 — Hotwire Native**.

---

## Project 2 Slice 4 — Debate (MVP) — DONE

_Branch: `slice-4-debate`. Suite: **141 examples / 0 failures / 2 pending** (request + Cuprite
system specs; system dir is **18 examples**, reliably green across repeated runs — the debate
system spec drives the full flow headless). brakeman **0**; `standardrb` clean; `bundler-audit`
clean._

**What shipped — the signature one-on-one, turn-based Debate (Increment 1):**
- **Data model** — two tables (`debates`, `debate_turns`) + a nullable `notifications.debate_id`,
  kept **outside** the `Hujah` tree (no feed/vote/slug/flag entanglement). Derived state, not
  columns: `current_turn_user` (challenger first, then whoever did NOT author the last turn; nil
  unless active) and `current_round`. The real concurrency guard is the **`unique [debate_id,
  position]`** index; a **partial-unique** `[hujah_id, challenger_id, opponent_id] WHERE status IN
  (pending, active)` index blocks a duplicate *live* challenge (directional).
- **Rich-model state machine** (thin controllers, mirroring `cast_vote`): `after_create_commit`
  challenge notify; `accept!` / `decline!` (opponent + pending only); `post_turn` (`with_lock`;
  only `current_turn_user`, only while active; assigns `position`); `conclude!` (either participant
  while active). Each transition creates **one** notification (4 new categories: `debate_challenge`,
  `debate_declined`, `debate_your_turn`, `debate_concluded`). Stance-opposition + distinct-participant
  validations.
- **Authorization (per-action Pundit)** — `DebatePolicy` (`show?` = concluded → anyone incl.
  logged-out, else participant; `accept?`/`decline?` = opponent + pending; `conclude?` = participant +
  active) + a **nil-safe `Scope`** (the Debates lens renders on the public hoojah page). **C1
  (security-critical):** `DebateTurnsController#create` authorizes a **`DebateTurn` instance**
  (`DebateTurnPolicy#create?` — only `current_turn_user` may post), NOT the debate — authorizing the
  debate would resolve `DebatePolicy#create? = user.present?` and let any signed-in user post any turn.
- **Controllers / routes** — RESTful member actions only (`create`, `show`, `accept`, `decline`,
  `conclude`, `turns#create`); every write derives the actor from `current_user`; strong params
  permit only `:argument_id`/`:challenger_stance` (challenge) and `:body` (turn). The challenge
  validates the argument belongs to the URL hoojah (→ 422 on a forged `argument_id`), rescues
  `RecordNotUnique` (dup-live race) and validation failure (→ 422, never 500). Two **rack-attack**
  throttles (challenge 10/min/user, turns 20/min/user).
- **Views + Hotwire (Phase 4)** — real Tailwind UI: debate `show` (`_debate_transcript` at the
  pinned `dom_id(@debate, :transcript)`, `_debate_turn` via `format_body` + `local-time`,
  `_turn_composer` at `dom_id(@debate, :composer)` shown only to the current-turn user else a
  waiting/concluded note), `_debate_status` accept/decline/conclude region, a **Debates lens** on
  `hujahs/show` (`dom_id(@hujah, :debates)`), and a **challenge `<dialog>`** on the argument card
  (`_challenge_dialog`, `dom_id(argument, :challenge_dialog)`, via the existing `dialog_controller`)
  shown only to a signed-in non-author. Request-driven Turbo Streams throughout (append the turn +
  replace the composer; replace the status region; append the debate card + `close_dialog`). New
  minimal `debate_composer_controller` (autofocus on connect — first paint + post-turn replace);
  CSS `field-sizing: content` for auto-grow (no JS). Pinned dom_ids so Increment 2b broadcasting
  drops in untouched.
- **System spec** — `spec/system/debate_spec.rb` drives challenge → accept → alternating turns
  (append in place + composer refocus, asserted via `textarea:focus`) → conclude → read-only public
  transcript, switching participants mid-flow via the Slice-3 `login_as_system` harness.

**Still open / deferred — per the program roadmap:**
- **Debate Increment 2a** — spectator "who argued better?" **verdict** (reuse the vote-counter idiom).
- **Debate Increment 2b** — **real-time broadcasting** via Solid Cable (the pinned transcript/composer
  dom_ids are ready for it).
- **Debate Increment 3** — **turn-timeout + turn-cap auto-conclude** via Solid Queue (MVP has no
  auto-timeout; a ghosted `active` debate persists until a participant concludes).
- **Privacy + Analytics** — incl. the **`new_vote` voter-identity** privacy fix (carried from Slice 3).
- **Badges** — reputation/achievement badges, incl. **`debate_won`**.
- **Trending** — trending hoojahs/topics ranking.
- **Block / mute + private accounts** — closes the cross-hoojah harassment gap (one user challenging a
  victim across many hoojahs; the partial-unique index + per-user throttle bound dup/burst but not this).
- Carried forward: **Vote array→scalar** migration, **serializer N+1 / prosopite**,
  **`config.require_master_key`** (L4), **`rack-cors`** tightening (M1), **Project 3 — Hotwire Native**.

---

## Slice 5 — Privacy Hardening + Analytics (MVP) — DONE

_Branch: `slice-5-privacy-analytics`. Suite: **149 examples / 0 failures / 2 pending** (request +
Cuprite system specs; +8 over the 141 baseline). brakeman **0**; `standardrb` clean; `bundler-audit`
clean. Zero new tables._

**Part A — vote-privacy fix (the `new_vote` voter-identity leak, carried from Slice 3):**
- `Hujah#cast_vote` no longer passes `subject_user_id: by.id` to the `new_vote` `Notification.create!`,
  so the vote notification carries **no voter id**. `NotificationSerializer`'s existing
  `if subject_user_id` guard then emits **no `subject_user`** for a `new_vote` (verified via
  `spec/requests/api/v1/notifications_spec.rb` — `new_hoojah_response` still legitimately carries one).
  The other notification callbacks (`notify_parent_owner`, `notify_mentions`, debate/follow) keep
  `subject_user_id` — they name a genuinely *public* actor and were **not** touched.
- **Backfill** `db/migrate/20260805145333_backfill_new_vote_subject_user.rb` (`disable_ddl_transaction!`,
  data-only) nulls `subject_user_id` on existing rows via
  `Notification.where(category: 4).update_all(subject_user_id: nil)` (integer `4` = `new_vote`, so the
  migration doesn't couple to the model constant).
- **Accepted residual:** the `new_vote` notification's own `created_at` still tells the owner *a* vote
  landed *and when* (never *who*) — inherent to any activity notification, documented in the spec.

**Part B — owner-only `/dashboard` (zero new tables):**
- **`UserAnalytics` PORO** (`app/models/user_analytics.rb`) — compute-on-read aggregates off the
  **denormalized** `agree/neutral/disagree_count` on `hujahs`. `total_votes_received` =
  `SUM(agree+neutral+disagree)` over the user's own hoojahs; `total_arguments_received` = child count via
  a `hujahs`-only sub-select; `distributions` = one `pluck` over the user's top-level hoojahs mapped to a
  read-only `Distribution` value object (`Struct`) owning **k=5 suppression** (`suppressed? = total < 5`)
  and the `agree/neutral/disagree_pct` helpers. **Never joins `votes` or `users`** — a spec subscribes to
  `sql.active_record` and asserts every SELECT touches only `hujahs` (no `votes`/`users`/`JOIN`).
- **`AnalyticsController#show`** — `before_action :authenticate_user!` + `skip_authorization`. **No
  `AnalyticsPolicy`** (it would be tautological): owner-only holds **by construction** because the query
  is `Hujah.where(user_id: current_user.id)` and there is **no `:username`/other-user route** (mirrors
  `NotificationsController#index`). Route `get "/dashboard", as: :dashboard`.
- **Views** — `analytics/show` renders totals as `_stat` chips + each top-level hoojah via a read-only
  `_distribution_bar`. The bar markup is **copied** (~3 lines of Tailwind width-% divs) from
  `hujahs/_vote_bars` — **not shared**, because `_vote_bars` is welded to a `button_to` vote form. No
  SVG, no chart lib, no JS, no lazy frames. A split below k=5 renders "fewer than 5 votes". Signed-in
  navbar gets a **Dashboard** link. System spec `spec/system/analytics_spec.rb` (reuses `login_as_system`)
  drives it headless (totals, a 60% split, the suppressed label).

**Honest scope note (security 2a — tracked follow-up, OUT of scope):** per-hoojah `agree/neutral/disagree`
counts + % are **already public + unsuppressed at any N** on hoojah cards/show pages to anonymous
visitors — the app's largest real secret-ballot gap, independent of this slice. The dashboard's k-gate does
**not** close it; it only stops the dashboard being an efficient discovery index and future-proofs the
`UserAnalytics` suppression pattern for the later trends increment. Closing 2a needs product-level
rounding/suppression on the public pages (a much bigger change).

**Still open / deferred — per the roadmap:**
- **Analytics trends** (day/week rollup via Solid Queue) + **divisive/consensus ranking** — deferred here
  (formula rabbit hole + a k-filter-before-selection subtlety); needs its own spec + a
  `rails-security-auditor` pass and must inherit the 2a public-card caveat.
- **Tracked follow-up:** the **2a public per-hoojah count suppression** above.
- Still open from earlier: **Block/mute + private accounts**, **debate Increments
  2a/2b/3**, **Vote array→scalar** migration, **serializer N+1 / prosopite**,
  **`config.require_master_key`** (L4), **`rack-cors`** (M1), **Project 3 — Hotwire Native**.

---

## Slice 6 (Badges + Trending) — DONE

_Branch: `slice-6-badges-trending`. Suite: **161 examples / 0 failures / 2 pending** (+12 over the 149
baseline: badges + trending model/request/system). brakeman **0**; `standardrb` clean; `bundler-audit`
clean. One new table (`user_badges`)._

**Badges — 4 event-driven achievements (no vote milestones):**
- **Registry in code, not a table:** `app/models/badge.rb` — `Badge::REGISTRY` maps the 4 keys
  (`first_hoojah`, `first_argument`, `first_follower`, `first_debate`) to `{name, description, icon}`
  (Lucide). Only *awards* persist: `user_badges (user_id FK, badge_key)` with a **unique
  `[user_id, badge_key]`** index (migration `20260805150000_create_user_badges`). `UserBadge` validates
  `badge_key` inclusion against the registry keys.
- **`UserBadge.award(user, key)`** is idempotent + notifies once: `exists?` guard → `create!` →
  `Notification.create!(category: :badge_earned, body: key)` → `rescue ActiveRecord::RecordNotUnique`
  (race no-op, no dup row/notification). `User#badges` uses **`filter_map`** over the registry so a
  stale/renamed key can never 500 the public profile (spec-asserted).
- **Award sites are all off the hot path** (after commit / outside any open transaction):
  `Hujah after_create_commit` (`first_hoojah` for a top-level, `first_argument` for a reply),
  `Follow after_create_commit` (`first_follower` → the *followed* user), `Debate#conclude!` after the
  status update (`first_debate` → both participants). **`Hujah#cast_vote`'s transaction is deliberately
  untouched** — a duplicate badge insert inside it would poison the vote tx on Postgres and lose the vote.
  `spec/models/badge_awards_spec.rb` includes the **regression test that `cast_vote` still commits the
  vote**.
- **Notification enum** appends `badge_earned: 11` (no renumber). `_notification_card` gets a
  `badge_earned` branch (Lucide `award` + the registry **name**, not raw `body`) with its own **mark-read
  `button_to`** (it carries no hujah/subject_user, so the existing mark-read affordances didn't cover it).
  `NotificationSerializer` gains a computed **`badge`** attribute (`{key, name, icon}` from the registry,
  nil for other categories) for API/native parity. `_profile_header` renders `user.badges` as public
  Lucide chips with `title` tooltips.

**Trending — `Hujah.trending` (class method, cached; no new model, no jobs):**
- `Rails.cache.fetch("trending:v1", expires_in: 15.minutes)` computes **plain HN gravity on TOTALS**
  (`agree+neutral+disagree + children.size`) over candidates filtered to `parent_id: nil` +
  `updated_at > 48.hours.ago` (voting bumps `updated_at` via `increment!`), caches the **ordered ids
  only** (top 10), then reloads `where(id:).includes(:user)` and re-sorts into cache order.
- **Test env cache store** switched `:null_store` → `:memory_store` (`config/environments/test.rb`) so
  the low-level cache actually persists (only `Hujah.trending` uses `Rails.cache`; cache-dependent specs
  clear it in a `before`).
- `TrendingController#index` is **public** (`skip_authorization`; derived only from public top-level
  hoojahs). Route `get "/trending", as: :trending`. `_trending` partial (compact links + empty state) is
  reused by a standalone `/trending` page (nav link, `flame` icon) **and** by the feed's
  `<aside class="hidden lg:block">` `turbo_frame_tag "trending", src: trending_path, loading: :lazy` —
  the feed column is wrapped in a minimal `lg:flex` grid (single column unchanged below `lg`).
- **Rebuilt `app/assets/builds/tailwind.css`** (`tailwindcss:build`) so the new `lg:flex`/`lg:block`/
  `w-64` utility classes compile — the sidebar's `hidden lg:block` needs `lg:block` present in the CSS.

**Still open / deferred (per the roadmap + reviews):**
- **Vote-milestone badges** (`ten_votes`/`hundred_votes`) — **cut** (hot-path tx hazard + self-vote
  farmable); revisit with **distinct-voter** counting after the Slice 5 2a public-count follow-up.
- **`debate_won`** badge — needs the verdict increment (**Slice 8**).
- Recurring-job trending (Solid Queue) — only if the read-time compute grows; fine at beta scale.
- **Trending privacy re-check when Slice 7 (Block/mute) ships** — candidates must then exclude
  blocked/private content.
- **HTML vote endpoint** (`POST /hoojah/:slug/votes`) isn't in the rack-attack `votes/user` throttle
  (pre-existing; only the API path is) — flagged for the rack-attack owner, out of scope here.

---

## Slice 7 (Block) — DONE

_Branch: `slice-7-block`. Suite: **185 examples / 0 failures / 2 pending** (+24 over the 161
baseline: block model/policy/request + enforcement + visibility + a cuprite system spec; system
dir is **22 examples**, reliably green across repeated runs). brakeman **0**; `standardrb` clean;
`bundler-audit` clean. One new table (`blocks`)._

**Bidirectional Block — interaction cutoff + invisibility, all keyed on one helper:**
- **Model + single source of truth** — `blocks (blocker_id, blocked_id, timestamps)` with a
  **unique `[blocker_id, blocked_id]`** index + a `blocker_id <> blocked_id` DB check
  (`no_self_block`). `Block belongs_to blocker/blocked (class_name User)`, uniqueness-scoped +
  not-self validation. `User` gains `blocks_made`/`blocks_received` (dep: destroy) and the
  **memoized** `hidden_user_ids = (blocks_made.pluck(:blocked_id) + blocks_received.pluck(:blocker_id)).uniq`
  — the bidirectional set (blocked ∪ blocked-by) every filter/policy consults.
- **Enforced at the POLICY layer, not controller guards** (avoids the `verify_authorized` 500 an
  early `return` before `authorize` would cause — denials flow through the existing
  `rescue_from Pundit::NotAuthorizedError`):
  - `FollowPolicy#create?` += `!user.hidden_user_ids.include?(record.followed_id)`.
  - `DebatePolicy#create?` += `!user.hidden_user_ids.include?(record.opponent_id)`.
  - `HujahPolicy#create?` = `user.present? && (record.parent_id.nil? || !user.hidden_user_ids.include?(record.parent&.user_id))`.
    **`HujahsController#create` now authorizes the built instance** (`@hujah = current_user.hujahs.new(compose_params)`
    *before* `authorize @hujah`), not `authorize Hujah` (class), so the policy can read
    `record.parent.user_id`. Missing-parent 404 handling kept (the rescue now calls
    `skip_authorization` since it fires before `authorize`). The shared `Api::V1::HujahsController#create`
    was switched to the same instance-authorize so it keeps working under the parent-reading policy.
- **Because interactions are rejected, there are ZERO notification-creation guards** — no reply →
  no `new_hoojah_response`; no follow → no `new_follower`; challenge rejected → no `debate_challenge`.
  `notify_parent_owner`/`cast_vote`/`Debate#notify` are **untouched**. `mention` is filtered at its
  **query** (`notify_mentions` += `.where.not(id: user.hidden_user_ids)`, plus a `return if handles.empty?`
  fast-path). `new_vote` is deliberately **left unfiltered** (anonymous — no attribution, no vector).
- **In-progress debates are grandfathered** — `DebateTurnPolicy` and the turn/conclude
  notifications are untouched, so an active debate predating a block still allows turns and still
  fires `debate_your_turn`/`debate_concluded` (guarding them would stall the debate).
- **Content filters (signed-in only; anonymous unfiltered)** — `Hujah.timeline_for` and the global
  feed branch (`HujahsController#index`) exclude `hidden_user_ids`; `HujahsController#show` filters
  `@children` (hides pre-block replies too); `TrendingController#index` rejects per-viewer over the
  still-global cache.
- **BlocksController** (`authenticate_user!`, `set_target` from `:username`) — `create` authorizes
  `Block.new(...)` then, in a **transaction**, `find_or_create_by` (rescue `RecordNotUnique`) **and**
  removes reciprocal follows both ways (`Follow.where(follower: [me,@target], followed: [me,@target]).delete_all`
  — `delete_all` since Follow has no destroy callbacks). `destroy` mirrors `FollowsController` (`authorize
  @block, :destroy? if @block` else `skip_authorization` — a nil block would 500 under
  `verify_authorized`). `index` renders the current user's blocked list at `/blocks`. `BlockPolicy`
  (`create? = user.present?`; `destroy? = record.blocker_id == user&.id`). rack-attack `block/user`
  throttle (20/min). `_follow_button` gained Block/Unblock states (Unblock when blocked-by-me; never
  Follow for a hidden pair). Turbo-Stream replaces the action button + follower-count chip.
- **System-harness fix (important):** the persistent Warden `on_request` hook (`spec/support/devise.rb`)
  now re-`set_user`s a **freshly-found** `User.find(id)` each request instead of the one stored object.
  Production loads `current_user` anew per request, so the per-instance `hidden_user_ids` memo is always
  recomputed; reusing one object would persist a stale memo across a browser flow (memoized before a
  block, read after). The block-visibility **request** specs model the same via a `sign_in_fresh` helper.

**Documented boundaries / still open:**
- **Direct-URL boundary (MVP):** Block does NOT hide a blocked user's profile, hoojah show page, or
  their appearance in third-party followers/following lists reached by direct URL — that's **Slice 7b**
  (private accounts + mute). Block removes them from *your* feeds/threads/trending and cuts
  interaction/notification.
- **`Api::V1` block filters — deferred, not ignored:** the JSON feed/children/user endpoints still
  have no social-graph filtering (pre-existing); a native client will need the same filters incl.
  `HujahSerializer#children`. (The `create` instance-authorize above does now reject a blocked-pair
  reply via the API as a side effect — filtering of *reads* is what's deferred.)
- **Grandfathered debate:** an in-progress blocked-pair debate is not auto-concluded (its
  notifications keep firing) — deferred.
- Carried forward: **debate Increments 2a/2b/3** (Slice 8, incl. `debate_won`), **Vote array→scalar**,
  **serializer N+1 / prosopite**, **`config.require_master_key`** (L4), **`rack-cors`** (M1),
  **Project 3 — Hotwire Native**.

---

## ⚠️ Environment quirks — you MUST know these to run anything

This machine is arm64 / Darwin 25 with modern clang. The repo carries build helpers:

- **Ruby is via `mise`**, pinned to `3.4.9` (`.ruby-version` + `mise.toml`). Always run Ruby/Rails/bundle as:
  ```bash
  mise exec ruby@3.4.9 -- <cmd>
  ```
- **`source .mise-build-env.sh` before any `bundle install`** — it prepends a `clang` shim
  (`.cc-shim/`) that relaxes a few `-Werror` flags so native C extensions compile. Modern gems
  (Ruby 3.4) mostly don't need it, but it's harmless and required if a native build fails.
- **The canonical test command** (spring is gone; warnings/yarn noise filtered):
  ```bash
  source .mise-build-env.sh
  RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec
  ```
- **Test DB is schema-only, no seeds:** `bin/rails db:test:prepare` (NOT `db:prepare`, which seeds and
  pollutes whole-table-count assertions).
- **Postgres 18** runs locally (brew service), connects as the OS user (no password in dev/test).

---

## What's on `master` now

- 6 sequential Rails hops (6.0→6.1→7.0→7.1→7.2→8.0→8.1), each its own commit, green + boot-gated.
- Ruby 2.7.8 → 3.3.12 → 3.4.9.
- **24 characterization request specs** (`spec/requests/**`, `spec/support/auth_helpers.rb`) — the safety net.
- Backend modernization: `jsonapi-serializer`, Solid Queue/Cache/Cable, Rails-8 multi-DB production
  `config/database.yml`, Kamal + Thruster (placeholder registry/host), Zeitwerk verified,
  brakeman (0 warnings) + bundler-audit (clean via `.bundler-audit.yml`), puma 7.2.1 (CVE fix).

Full per-hop record: **`docs/superpowers/UPGRADE-LOG.md`**.

---

## Open decisions / owner action needed

**Security — `docs/superpowers/SECURITY-FINDINGS.md`.** The audit found serious **pre-existing** app-logic
vulns (NOT upgrade regressions), deliberately left unchanged because they alter the API contract the
React SPA depends on and the characterization specs:
- `Api::V1::VotesController`, `NotificationsController#update/#destroy`, `HujahsController#destroy` have
  **no authentication** (trust `params[:user_id]`/id → IDOR).
- Login / `is_logged_in?` responses **leak the full `User` record** including `password_digest`.
- CSRF disabled app-wide; `:id` mass-assignable on user update; legacy unrouted-but-dangerous
  `VotesController`.

Decide: fix as a dedicated security pass, or fold into Project 2 (where auth/front-end are reworked).
These will need spec changes (the characterization specs currently lock the insecure behavior).

---

## Next: Project 2 — React SPA → Hotwire (Turbo + Stimulus)

Not started. When resuming, run the same cycle: `superpowers:brainstorming` → spec → `writing-plans` →
subagent-driven build. Known scope from the earlier decomposition:

- Replace the **React 16 SPA** (`app/javascript/**`, ~40 components: cards, forms, navbars, icons,
  notifications, user profile) with **server-rendered ERB + Turbo Frames/Streams + Stimulus**.
- Retire **Webpacker/shakapacker + React** → **importmap + Propshaft** (Propshaft was deliberately
  deferred here; sprockets is currently inert).
- Use the **`better-stimulus`** agent (installed) for Stimulus controllers.
- The JSON API can stay for programmatic clients; the Hotwire views become the primary UI.
- **shakapacker's JS build is currently INACTIVE** (`bin/shakapacker` not wired; package.json untouched;
  there's an accepted shakapacker CVE ignored in `.bundler-audit.yml` that should be removed once
  shakapacker is deleted).

Then **Project 3 — Hotwire Native**: Rails-side path-config + native auth, then a separate native shell repo.

---

## Deferred items carried forward (from the upgrade)

- Propshaft adoption (→ Project 2).
- Deploy: `config/deploy.yml` has placeholder `service: hoojah` but **registry/servers are placeholders** —
  set real values + `APP_HOST`/`RAILS_MASTER_KEY`/DB env before any Kamal deploy. Solid* uses separate
  production DBs (`hoojah_production_{cache,queue,cable}`) that must be created at deploy.
- One-time user logout will occur on first deploy (7.0 changed session key-gen SHA1→SHA256).
- `config.require_master_key` left commented (no `config/master.key` present locally; enable when the
  deploy provides the key).

---

## Doc map

| File | What |
|------|------|
| `docs/superpowers/specs/2026-08-03-rails-6-to-8.1-upgrade-design.md` | Approved design |
| `docs/superpowers/plans/2026-08-03-rails-6-to-8.1-upgrade.md` | Implementation plan |
| `docs/superpowers/UPGRADE-LOG.md` | Per-hop upgrade record |
| `docs/superpowers/SECURITY-FINDINGS.md` | Audit triage + open items |
| `README.md` | Stack + run instructions |
