# Hoojah — Session Handover

_Last updated: 2026-08-24. Read this first when resuming._

## TL;DR

**Project 1 (Rails 6.0 → 8.1 upgrade + backend modernization) is DONE and merged to `master`.**
The app runs **Rails 8.1.3.1 on Ruby 3.4.9**, suite is **24 examples / 0 failures / 2 pending**,
boots in dev + test. Merge commit: `93a3ff2`. **Not pushed** — run `git push origin master` when ready.

> **Correction (2026-08-17):** this line used to say the remote is Bitbucket. It is **GitHub** —
> `https://github.com/hoojah/hoojah-beta.git`. That matters: it makes GitHub Actions the right answer
> for the CI gap, with no migration needed.

**Project 2 (React SPA → Hotwire) is COMPLETE** — all 8 slices shipped (Hotwire foundation, features +
Pundit, social, Debate MVP + increments, privacy + analytics, badges + trending, block, private
accounts). The **"land everything" roadmap is done** — see "Slice 8 … 🏁 PROGRAM COMPLETE" below.

**Slice 9 (design-system adoption + structured debate phases) is also DONE** on branch
`slice-9-design-system`, **not merged** — suite **513 / 0 / 2**. Read its section at the bottom of
this file before touching views or Tailwind: it corrects CLAUDE.md's gotcha #1 (Ruby `#` comments are
NOT scanned; ERB `<%# %>` comments ARE) and records nine CSS rules that ship with no view asking for
them.

Next up: **Project 3 (Hotwire Native)** — not started. (Slice 11, below, closed the last
`Api::V1` security items that were meant to be frozen before native clients consume the API.)

## Passkey / WebAuthn login — DONE ✅ (branch `passkey-webauthn-login`, not merged)

_2026-09-03. Passwordless login via WebAuthn/FIDO2 passkeys (Face ID / fingerprint / security key),
usernameless (discoverable) sign-in alongside the existing password login — password login always
remains available (no lockout). Spec: `docs/superpowers/specs/2026-09-03-passkey-webauthn-login-design.md`;
plan: `docs/superpowers/plans/2026-09-03-passkey-webauthn-login.md`._

- `webauthn` gem `~> 3.4`. New `PasskeyStrategy` Warden strategy — registered but invoked
  **explicitly by name**, not wired in as a default strategy, so the existing password Warden flow
  is untouched.
- `PasskeysController` at `/settings/passkeys` (index/options/create/update/destroy) — owner-only,
  enforced via Pundit and every lookup scoped through `current_user`.
- `Users::SessionsController` override adds `/login/passkey/options` (unauthenticated challenge
  mint) + `/login/passkey` (assertion verify → sign-in).
- `@github/webauthn-json` 0.5.7 vendored via importmap — no Node/build step, consistent with the
  rest of the JS stack.
- Login screen gains a "Sign in with a passkey" option (usernameless/discoverable), hidden
  client-side when the browser lacks WebAuthn support; password and Google login are unchanged.

**Deferred (this feature):**
- Rate-limit both challenge-minting endpoints (`/login/passkey/options` and
  `/settings/passkeys/options`) via Rack::Attack — tracked as an OPEN item in SECURITY-FINDINGS.
- The end-to-end system spec (`spec/system/passkey_login_spec.rb`) is **skipped/pending**.
  Revivable unchanged once (a) CDP virtual-authenticator user-verification stabilizes on
  Chrome/Cuprite, AND (b) the pre-existing Devise 5.0.4/Warden `serialize_from_session` arity bug
  (documented in `spec/support/devise.rb`) is resolved.
- Optional `userHandle` cross-check in `PasskeyStrategy` (defense-in-depth).
- Restore the empty-state placeholder after deleting the last passkey on `/settings/passkeys`.
- `WEBAUTHN_ORIGIN` must be set in production — the initializer falls back to localhost otherwise;
  consider a prod fail-fast.
- **Not pushed.** Branch `passkey-webauthn-login` off `master`. Merge when ready.

## Editable Hujah — DONE ✅ (branch `editable-hujah`, not merged)

_2026-09-03. Three independent slices letting an author edit their hujah. Spec:
`docs/superpowers/specs/2026-09-02-editable-hujah-design.md`; plans:
`docs/superpowers/plans/2026-09-02-editable-hujah-slice-{1,2,3}-*.md`. Built subagent-driven
(Opus implementers) with Fable-5 as the spec-compliance/architect gate + a code-quality gate per
task. **34 commits**, `bin/ci` green (**1379 examples, 0 failures**; Brakeman 0; bundler-audit clean)._

- **Slice 1 — Edit body (time-boxed).** `Hujah#body_editable?` = active + `conviction_count.zero?`
  + within `EDIT_WINDOW` (15 min) — applies to top-level AND replies. `body_edited_at` stamped by a
  `before_update` callback (NOT `updated_at`, which `cast_vote` bumps). `HujahPolicy#edit?/#update?`
  (owner + not-removed + window); `update?` re-derives the window so `authorize` IS the fail-closed
  re-check. `GET /hoojah/:slug/edit` + `PATCH /hoojah/:slug` on MAIN routes (CSRF on); `_compose_form`
  gained an `edit_mode`. Edit-aware `@mention` diff (only NEWLY-added handles notified). "· edited"
  marker. On a failed edit, `restore_attributes([:slug])` reverts FriendlyId's in-memory slug regen.
- **Slice 3 — Custom stance labels (top-level only, immutable).** 3 nullable string columns
  (`agree_label`/`neutral_label`/`disagree_label`). `User#can_customize_stances?` = 10+ default
  top-level non-removed posts. Per-field, normalised (`\s+`→space, cap 24, default-token→nil),
  eligibility-coerced (`before_validation on: :create`), and `attr_readonly` (kept Rails 8.1's
  RAISE-on-assign default — immutability is loud by design; a global config flip was rejected).
  `Hujah#stance_label(pos)` renders at the top-level record's OWN surfaces via
  `HujahsHelper#stance_display_label` (verbatim custom / capitalised default); children always
  default. Inline click-to-edit on the composer for eligible authors (`stance_labels_controller.js`,
  keyboard-accessible). `first_custom_hoojah` badge. Render-point edits add **no** Tailwind classes
  (verified: bundle md5 unchanged with a positive control).
- **Slice 2 — Change visibility (permanent, destructive; top-level only).** `VisibilityChange`
  service (`app/services/visibility_change.rb`): direction by enum rank; `affected_participants`
  (voters + subtree arg authors who lose access, prospective `visible_under?` mirroring
  `Hujah#visible_to?` EXACTLY — batched via `author_follower_ids` to kill the N+1); `blockers`
  (an affected arg with OTHER users' reply/vote or ANY debate); `apply!` — row-locked purge
  (re-checks `tightening?`+`blockers` UNDER the lock, snapshots BEFORE deleting, recounts AFTER via
  `Hujah::COUNTER_FOR`, secret-ballot notification with NO `subject_user_id`). Loosening never purges.
  `hujah_archives`/`hujah_archive_participants` tables (FK-less `hujah_id`); `hujah_archived`
  notification cat 16. `Hujah#promote!` detaches a reply (parent_id/vote nil, **slug stays stable** —
  it derives from the body, which promote doesn't touch). `visibility_edit` (counts + entangled
  blockers reloaded full since the service returns partial-selects + typed-confirm "REMOVE") /
  `update_visibility` (fail-closed server re-check). `HujahsController#show` redirects a purged
  participant to their frozen `hujah_archives#show` (read-only snapshot; **breakdown gated by the same
  `VOTE_BREAKDOWN_MIN` k-anonymity rule** so a lone co-voter's stance can't be deduced). `DebateChannel`
  already stops streaming to a purged spectator (leak spec pins it).

**Deferred (this feature):**
- **Archive URL breaks if the hoojah is later deleted.** `HujahArchivesController#show` and the
  `#show` redirect both resolve via `Hujah.friendly.find(slug)`, so a tightened-then-DELETED hoojah
  (a vote-only hoojah is `deletable?`) 404s before the surviving archive data is consulted — the
  purged voter loses the access the FK-less design promised them. Fix needs the archive addressed
  independently of the live record (store the slug on `HujahArchive`, or a token-based `/archive/:token`
  URL — the plan deliberately kept tokens out of the URL, so this is a small redesign).
- **Redirect-to-archive fires for ANY invisibility cause**, not just a tighten (a purged participant
  later blocked, or the hoojah moderation-removed, still lands on their archive). Matches the
  "archive is the permanent record" intent, but worth a product confirmation for the removed case.
- **Not pushed.** Branch `editable-hujah` off `master` (34 commits). Merge when ready.

## UI fixes + delete-hujah flow — DONE ✅ (branch `ui-fixes-and-delete-hujah`)

_2026-08-28. Five UI corrections + a new owner-only delete-hujah flow. Spec:
`docs/superpowers/specs/2026-08-28-ui-fixes-and-delete-hujah-design.md`. Reviewed by
rails-simplifier, rails-security-auditor, better-stimulus, and code-reviewer; Fable-adjudicated._

Shipped: double-`#` hashtag pill fix; feed-card indicator row (un-linked counts, conviction
`heart`→`zap`, native `title` tooltips, dot before conviction); profile active-tab highlight
(tab bar moved inside the `profile-list` Turbo frame); responsive menu tap targets
(`py-3 sm:py-1`); scrollable edit-profile dialog (`open:flex … min-h-0`); **delete hoojah**
— `DELETE /hoojah/:slug`, owner-only via `HujahPolicy#destroy?` (now also blocks
moderator-removed content so the audit Notification survives), refused when the hoojah has
replies/debates (`Hujah#deletable?`, `with_lock`-guarded), native `turbo_confirm`, custom
`visit` Turbo StreamAction to leave the deleted show page. Notifications are deliberately
NOT cascaded — they survive a hoojah's deletion and render nil-safe (Slice 11 Task 9 contract).

**Deferred backlog (decisions from the review, not oversights):**

- **`danger` tone for `ds_menu_item_classes`.** The Delete row uses `tone: "neutral"` (orange),
  visually equal to the Report row; menu rows have no dedicated destructive tone. Adding one is a
  design-system change (helper + `@source inline` safelist + mirror docs) — out of this branch's
  scope. The `turbo_confirm` mitigates meanwhile.
- **Dangling reply notification on leaf-reply destroy.** Deleting a leaf *reply* is allowed; the
  parent-owner's "X replied to your hoojah" notification carries `hujah_id = parent.id`, so it
  survives pointing at a now-gone reply (thread still loads). Fix needs a notification→child
  linkage (currently only `hujah_id = parent`), so it's deferred.
- **Full destroy-vs-reply race closure.** The `with_lock` in `HujahsController#destroy` closes
  destroy-vs-destroy and destroy-vs-moderation, but a reply created concurrently never locks the
  parent row. Fully closing it needs an `ON DELETE RESTRICT` FK on `hujahs.parent_id` — a
  `strong_migrations` job against a populated table, not for this merge.

## Slice 11 — Api::V1 Hardening — DONE ✅ (branch `slice-11-api-hardening`, not merged)

_2026-08-25. Closes the SECURITY-FINDINGS OPEN items **A1** (the only one with live-traffic
exposure), **A2**, and **M1/A4** — the JSON-API authorization/visibility parity that Slices 11–13
were carved out to settle before Project 3. `bin/ci` green: **886 examples / 0 failures** (+22 over
the 864 baseline), brakeman 0, standardrb + bundler-audit clean. prosopite: no material N+1
regression (isolated measurement of the changed serializers = the acknowledged bounded per-record
C2 pattern; the pre-existing `debate.rb` baseline still dominates). Plan:
`docs/superpowers/plans/2026-08-25-slice-11-api-hardening.md`. Built brainstorm-compressed (owner
decisions already in the ledger) → plan → **pre-implementation Fable leak-audit** → subagent-driven
TDD (per-task implementer + spec/quality review) → **rails-security-auditor pass (A1/A2/A4 CONFIRMED
CLOSED)**._

**What shipped (11 commits):**
- **Shared visibility gates.** Extracted the two inline predicates onto the model —
  `Hujah#visible_children_for(viewer)` (from `HujahsController#show`) and
  `User#visible_hujahs_for(viewer)` (from `UsersController#profile_tab_list`). HTML and API now
  call ONE SQL-filtered gate each and can't drift; both HTML controllers were refactored onto them
  (behaviour-identical).
- **A1 — serializers viewer-aware.** `HujahSerializer#children`/`children_count`/`parent` (parent
  guarded on privacy **and** block) and `UserSerializer#hujahs`/`hujah_count` filter through the
  shared gates via a Devise-session `current_user:` serializer param (not request-forgeable). The
  `Api::V1` feed index is now **top-level only** (`parent_id: nil`) **and** block-filtered for
  signed-in callers. Named leak specs in `spec/requests/api/v1/api_visibility_spec.rb` +
  `users_spec.rb`. **Fable caught two A1-class leaks the first plan draft missed** — the
  `UserSerializer#hujahs` list and the reply-serving feed index — both fixed before implementation.
- **A2 — `flag_params`.** `params.require(:flag)` + a scoped `rescue_from ParameterMissing → 400`
  (test env runs `show_exceptions = :none`; mirrors the `HujahsController#create` convention).
- **M1/A4 — dead CORS.** `config/initializers/cors.rb` + the `rack-cors` gem deleted.
- **Bundled robustness fix.** `NotificationSerializer#hujah` no longer 500s the notifications index
  when a referenced hoojah was deleted (`notification.hujah` nil-safe accessor, not `Hujah.find`).

**Contract change (intentional):** the `Api::V1` user endpoint's `hujahs`/`hujah_count` are now
top-level-only (were all hujahs incl. replies) — the secure behaviour; native follower-aware parity
for restricted top-level claims stays deferred to Project 3.

**New tracked follow-ups (Low, not scheduled — see SECURITY-FINDINGS):** `HujahPolicy#vote?` lacks
the `hidden_user_ids` block check `#create?` has (both surfaces, shared policy);
`Api::V1::NotificationsController#notification_params` has the same latent params-on-nil 500 as flags
had (post-authorize, not the security class); `UserSerializer#vote_count` + remaining `*_count`
columns stay unfiltered (A7 class, track with 2a). Carried forward unchanged: **A3/2a** (Slice 13),
**A6** (votes unique index / first-vote race), **L4** (deploy), **Project 3 (Hotwire Native)**.

## Hoojah 2026 FULL-APP redesign — DONE ✅ (branch `hoojah-2026-full-redesign`, not merged)

_2026-08-25. Extends the earlier 2-surface redesign to the **whole app**. `bin/ci` green:
**864 examples / 0 failures**, brakeman 0, standardrb + bundler-audit clean, prosopite 179
(≈146 baseline — no N+1 regression). 31 commits. Spec:
`docs/superpowers/specs/2026-08-24-hoojah-2026-full-app-redesign-design.md`; plan:
`docs/superpowers/plans/2026-08-24-hoojah-2026-full-app-redesign.md`. Built via
brainstorm→spec→plan (reviewed by rails-simplifier + better-stimulus + rails-security-auditor)
→ subagent-driven development, with a **Fable architecture/leak audit gating every phase**._

**All 11 remaining surfaces brought onto the 2026 language, in 5 gated phases:**
- **P0 Foundation** — `-soft` safelist; `ui/_avatar` gradient tile `variant:` (orthogonal to
  `size:`, so the photoless fallback is now a tile app-wide); `shared/_screen_header`; navbar
  restyle (`bg-nav`, filled trending, tile avatar; theme/scheme pill KEPT). `--color-nav` bridge
  added so `bg-nav` compiles.
- **P1 Auth + Feed** — Devise login/signup/reset restyle + inert "Continue with Google" +
  `password_visibility` controller; **vote-widget redesign** (`_vote_bars`: segmented aggregate bar
  + pill buttons; vote POST contract unchanged); feed card `rounded-2xl` + swords/"Jump in";
  `_live_debate_strip`; feed active-debate **preload** (`Hujah#active_debate`, single query);
  composer polish (`hrise` via classes API).
- **P2 Discover + Trending** — **NEW full-text search** (`SearchController`, `Hujah/User/Hashtag.search`
  reusing the new **`Hujah.visible_to`/`User.visible_to` SQL scopes**, `sanitize_sql_like`,
  `search/ip` rack-attack throttle, live-suggest Stimulus with frame-wraps-form JS-off); Discover
  feed tab; `_follow_button surface:` local; rich `/trending` page (reuses `Hujah.trending`, sidebar
  stays minimal).
- **P3 Debates** — `debates.opening_argument` column (posted as the challenger's opening turn on
  `accept!`; **`accept!` now notifies `current_turn_user`**, not always the challenger); debate
  **create page** (rounds 2/3/5, instance-authorize, flat permit — supersedes `_challenge_dialog`,
  now orphaned); pending accept/decline screen; transcript **VS scoreboard + chat bubbles**;
  read-only **spectator view** (extended `DebatePolicy#show?` so a visible spectator may read an
  ACTIVE debate — pending stays participant-only); **verdict winner-hero** (draw-safe, closings,
  share; secret-ballot tally). Pinned dom_ids + derived phase logic preserved throughout.
- **P4 You** — notifications filter tabs + scope-only `read_all` (IDOR-safe) + card restyle
  (soft-tint tiles, secret-ballot `new_vote`); profile gradient header + conviction card (real
  votes-cast, **no level/streak fiction**) + visibility-filtered live-debate card; profile
  count-tabs (Hoojahs/Responses/Debates, responses `visible_to?`-filtered, debates via
  `DebatePolicy::Scope`); analytics KPI pair (+ Followers, kept OUT of `UserAnalytics`) + stacked
  distribution bar (k=5 kept). **No 7-day chart** (deferred).

**Security — 4 real leaks caught by the per-phase Fable audits and fixed (each with a named spec):**
1. **Live-debate teaser** (feed strip + swords/Jump-in) leaked private/blocked debate participants
   to any feed viewer → `HujahsController#preload_active_debates` now gates on both participants
   `visible_to?` + block (`4f24faa`, `spec/requests/feed_live_debate_visibility_spec.rb`).
2. **Debate create/new page** was a read primitive for `followers_only`/`private_only` claims +
   private argument authors (enumerable `argument_id`) → `DebatePolicy#create?` (which `new?` falls
   through to) gained the `hujah.visible_to? && opponent.visible_to?` clause (`bd6f427`,
   `spec/requests/debate_create_visibility_spec.rb`).
3. **`DebatePolicy::Scope`** gated debates on `visible_to?` (privacy) but not blocks; the profile
   Debates tab opened a fresh surface → block filter added to `Scope#resolve` (closes the tab AND
   the pre-existing hoojah-page Debates lens) (`01e10e3`).
4. **`accept!` notification** misdirected "your turn" to the challenger when an opening argument was
   posted (mover is then the opponent) → `notify(current_turn_user, …)` (`58854f8`).

**Deferred (per the approved scope boundary — real-data substitutes shipped instead; these are a
follow-up program):** turn timers + expiry; live presence / typing indicators / watcher counts;
verdict-during-active + live lean bar; conviction **levels & streaks** gamification; analytics
**time-series + WoW deltas**; trending period toggle / %-deltas / category-vote data. Also deferred:
re-mirror `docs/design-system/` to the rounded/schemed 2026 language (the redesign **supersedes the
square-card + neutral-is-pink house rules**); server-side length cap on `debates.opening_argument`
(parity Low with `DebateTurn#body`); consolidate the duplicated share intent-links in
`hujahs/_card_menu` vs `_share_menu`; delete the orphaned `_challenge_dialog`; harden the
order-dependent feed/trending **request-spec isolation** (`trending:v1` memory-store; passes in the
full `bin/ci` order — see the [[hoojah-ci-shared-db-gotchas]] memory). Pre-existing count-vs-visible
aggregate leaks (tab badges, hashtag `hujahs_count`) unchanged (same class as the Slice-5 2a item).

## Hoojah 2026 redesign — DONE ✅ (branch `hoojah-2026-redesign`, not merged)

A deliberate **rebrand** of the new-post composer and the single-hujah "argument" view, imported from
a Claude Design project (`Hoojah 2026.dc.html`). Spec: `docs/superpowers/specs/2026-08-24-hoojah-2026-redesign-design.md`;
plan: `docs/superpowers/plans/2026-08-24-hoojah-2026-redesign.md`; mockup refs under
`docs/superpowers/specs/assets/`. Full `bin/ci` green (**603 examples / 0 failures**, all gates);
clean prosopite **147** (≈ the 146 baseline — no N+1 regression). Built via superpowers
brainstorm→spec→plan→subagent-driven development with a **Fable-5 architecture audit** that caught
five visibility-leak surfaces before implementation, plus a final code-review pass.

**What shipped (28 commits, ~6 tracks):**
- **Theming (rebrand).** Tailwind v4 `@theme inline` colors now chain onto runtime CSS vars switched
  by `data-theme` (light/dark) + `data-scheme` (spectrum/signal/ballot) on `<html>`, with a nonce'd
  no-FOUC head script and a `theme_controller` navbar toggle. **This supersedes the old design-system
  rules** ("neutral is PINK", "no dark mode"): the default scheme is **Spectrum** (agree `#0ea5a4`
  teal / neutral `#e8930c` amber / disagree `#8b5cf6` violet). `--color-gray-{50,100,200}` remap onto
  surface tokens; `bg-white`/`text-black` are still pinned, so shared chrome was swept to
  `bg-card`/`text-ink` (baked into `ds_card_classes`). `docs/design-system/` is now **stale** and
  needs re-mirroring (deferred — see below).
- **Per-post visibility.** `hujahs.visibility` enum (`visible_public`/`followers_only`/`private_only`).
  `Hujah#visible_to?` gates it (reply branch ANDs the replier's own account privacy). Closed on
  **every** claim reader: HTML feed (both branches), show, `HujahPolicy#show?`/`#vote?`, the JSON API
  index, `Hujah.trending`, the profile page, concluded-debate transcripts (`DebatePolicy#show?`/Scope),
  the `/t/:name` tag feed, **and** `HujahsController#new` (the respond composer's parent card — a leak
  the final review caught). Each surface has a named leak spec.
- **Conviction voting = a lock, not a weight.** `votes.conviction` boolean + `hujahs.conviction_count`
  (aggregate only — secret ballot preserved). `cast_vote` takes a `FOR UPDATE` row lock. UI: tap =
  normal vote, hold-to-charge = conviction (locked forever), progressive-enhancement over `button_to`.
- **Hashtags.** `Hashtag` + `hashtag_hujahs` join, parsed from the body like `@mentions`
  (`HASHTAG_RE`, `sync_hashtags` after_save_commit), `format_body` linkifies `#tags` (distinct
  U+E002/E003 markers) to a `/t/:name` feed.
- **New-post surface:** full-page composer + inline feed composer rebuilt to the mockup —
  visibility select (JS-off-safe native `<select>`), suggested-hashtag chips, "How people weigh in"
  preview, allow-debates toggle, 8-char gate. `composer_controller`.
- **Single-hujah surface:** contextual header, author/claim hero, vote hero with charge-ring/boom,
  restyled debates + responses (stance-left-border, Challenge/"In debate"), three-state argument
  composer + `respond_hujah_path` fallback. `conviction_controller`, `argument_composer_controller`.
  `_vote_bars` (feed) left untouched; new `_vote_hero` for the show page; the vote Turbo Stream
  replaces both + the composer bar.

**Backlog / deferred (decisions, not oversights):**
- **Unique index on `votes [hujah_id, user_id]`.** The `FOR UPDATE` lock closes the conviction
  double-count + same-stance-upgrade races, but the concurrent *first-vote* race (two requests both
  find no row and both `votes.create!`) is still open. Add a concurrent unique index +
  `rescue ActiveRecord::RecordNotUnique` (retry). Until then a race can create two vote rows per
  (hujah, user).
- **Locked re-vote is a silent no-op**, not a domain error (spec §3.7) — UI-unreachable via the hero's
  `locked-value`.
- **Deep dark-mode polish of non-focus screens** (auth, profile, notifications, debate room) — they
  inherit the tokens but still carry pinned `bg-white`/`text-black` islands (e.g. `_challenge_dialog`,
  left frozen). The redesigned surfaces + shared chrome are dark-safe.
- **Re-mirror `docs/design-system/`** to the 2026 palette — it currently documents the retired one.
- **Follow button** omitted from the claim hero (`users/_follow_button` is locked to the indigo
  profile surface; would render invisible on the light hero).
- **BOOM celebration** markup is present but `hidden` — a conviction commits immediately and Turbo
  replaces the hero, leaving no client-side window; needs an optimistic-animation pass.
- **Respond overlay** = the existing full-page `respond_hujah_path` flow rather than a separate
  in-page morph overlay (keeps the no-JS baseline).
- **Scheme picker** is a minimal navbar cycle button (no dedicated picker screen); **image-attach**
  button in the composer is visual-only.
- Nice-to-have: `preventDefault` the vote-hero button click to drop a redundant (harmless, lock-serialized) tap POST.

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

## Slice 7b (Private Accounts) — DONE

_Branch: `slice-7b-private`. Suite: **225 examples / 0 failures / 2 pending** (request + Cuprite
system specs; +40 over the 185 Slice-7 baseline: private-account visibility gates + follow
request/approve + toggle + a cuprite system spec). brakeman **0**; `standardrb` clean;
`bundler-audit` clean. Two new columns (`users.private`, `follows.status`), no new tables._

**The single gate — `User#visible_to?(viewer)`:** `!private? || viewer == self ||
accepted_follower?(viewer)` (`accepted_follower?` = `passive_follows.accepted.exists?(follower_id:)`).
`Hujah#visible_to?(v) = user.visible_to?(v)`. Not memoized (list surfaces gate in SQL). **Every
content surface routes through this.**

**Schema + follow flow (Phases 1–2):**
- `users.private` (bool, default false, indexed); `follows.status` (enum `pending: 0, accepted: 1`,
  default `pending`; **existing rows backfilled → accepted**). `User#following`/`#followers` are
  **accepted-only** via a through-association scope — `following_ids`, counts, and the list pages all
  become accepted-only in one place. **Watch-out:** any test that does `active_follows.create!` with
  no `status:` now gets a **pending** follow (not a following-feed entry) — the request timeline spec
  and the fixed `spec/system/timeline_spec.rb` pass `status: :accepted`.
- `FollowsController#create` = `find_or_initialize_by` + explicit status (`private? ? :pending :
  :accepted`; a forgotten status is inert, never a leak). `FollowRequestsController` (accept =
  PATCH → `update!(status: :accepted)`; decline = DELETE → destroy), `FollowRequestPolicy` (only the
  followed user acts). All follow notifications/badges live in the `Follow` model
  (`after_create_commit` branches accepted vs pending; `after_update_commit :notify_accepted`); the
  **v1 first_follower-on-pending bug is fixed**. 3-state button (Following / Requested / Follow);
  requests accepted/declined from the `follow_request` notification card (**inbox page deferred**).

**The 11 visibility gates (Phase 3, each with a test in `spec/requests/private_visibility_spec.rb`):**
1. **Global feed** else-branch `.joins(:user).where(users: {private: false})` — **UNCONDITIONAL**
   (anonymous too).
2. **Following feed** — automatic (accepted-only `following_ids` gates it).
3. **Trending** — `Hujah.trending` candidates exclude private; `User after_update_commit` busts
   `trending:v1` on the privacy flip (no ≤15-min stale leak). (`hujahs.updated_at` qualified after
   the join.)
4. **Profile** (`UsersController#show`) — `@gated = !visible_to?`; the `_gated_header` partial shows
   avatar/name/@handle/"This account is private"/follow button/**counts only** (no hoojah list,
   headline, location, link, badges).
5. **Hoojah show** — `authorize @hujah`; `HujahPolicy#show? = record.user.visible_to?(user)`
   (nil-safe; anonymous → Pundit rescue redirects).
6. **`@children`** — UNCONDITIONAL SQL predicate `users.private = false OR hujahs.user_id IN
   (following_ids + [self])` (accepted followers see private replies; strangers/anonymous don't),
   composed with the Slice-7 block filter.
7. **Follower/following lists** — `UsersController#followers`/`#following` redirect to the profile
   when `!visible_to?`.
8. **Debate transcript** — `DebatePolicy#show? = participant? || (concluded? && both participants
   visible_to?)`; `Scope` filters the concluded set in Ruby (the lens is one hoojah's debates).
9. **Notification body** — `_notification_card` hoojah branch `&& notification.hujah.visible_to?(current_user)`;
   `NotificationSerializer#hujah` mirrors it (`notification.user` IS the recipient/viewer).
10. **`HujahPolicy#create?`** += `record.parent.visible_to?(user)` (no reply to an unseen private parent).
11. **`Api::V1`** — `HujahsController#index` excludes private authors, `#show` denies (404) a private
    author; `UsersController#show` denies (404) a private account. (Full follower-aware parity deferred.)

**Toggle (Phase 3.2):** `:private` in the profile `user_params` + a checkbox in `_profile_edit`; on
private→public (`was_private && !private?`) `passive_follows.pending.update_all(status: :accepted)`
(bulk, no notification blast). `spec/system/private_spec.rb` drives it end-to-end (owner makes
private → stranger sees the gated profile + requests → owner accepts from notifications → requester
then sees the content), reusing `login_as_system` and switching the acting user mid-flow.

**Documented deferrals / still open:**
- **`/follow_requests` inbox page** (7b-ii, UI polish) — requests are managed from the notification card.
- **Full `Api::V1` visibility parity** — the gated index/show/user endpoints are hardened, but
  serializer `children`/`parent` and the notifications endpoint's deeper parity stay deferred to
  Project 3 (the raw content the feature hides is no longer one guessable URL away).
- **Count leaks (pre-existing, Low):** `hujah_count`/`vote_count`/`children_count` still count
  unfiltered rows (same as Slice 7) — a private author's reply nudges a counter by 1. Noted, not fixed.
- Carried forward: **debate Increments 2a/2b/3** (Slice 8, incl. `debate_won`), **Vote array→scalar**,
  **serializer N+1 / prosopite**, **`config.require_master_key`** (L4), **`rack-cors`** (M1),
  **Project 3 — Hotwire Native**.

---

## Slice 8 (Debate Increments) — DONE — 🏁 PROGRAM COMPLETE

_Branch: `slice-8-debate-increments`. Suite: **271 examples / 0 failures / 2 pending** (+46 over the
225 Slice-7b baseline: verdict model/policy/request + channel/connection auth + broadcasts + timeout
job + a cuprite verdict system spec; system dir is **24 examples**, stable across repeated runs).
brakeman **0**; `standardrb` clean; `bundler-audit` clean. One new table (`debate_verdicts`), two new
channels, one new job; no new gems, no new Stimulus._

This slice shipped the three deferred Debate increments and **completes the "land everything" roadmap**.

**2a — Spectator verdict (concluded debates only):**
- `debate_verdicts (debate_id FK, user_id FK, choice integer)` with a **unique `[debate_id, user_id]`**
  index (no standalone `[debate_id]` index — the composite's leftmost prefix covers it). `choice` enum
  `{challenger: 0, opponent: 1, draw: 2}`. **Tally is compute-on-read** (`Debate#verdict_tally =
  debate_verdicts.group(:choice).count`) — **no denormalized columns**, which is what lets
  `Debate#cast_verdict` be a **single `create!` with a method-level `rescue RecordNotUnique`** (no
  transaction, nothing to poison). One immutable vote per spectator (changeable deferred); no verdict
  notifications.
- `DebateVerdictsController#create` authorizes a **`DebateVerdict` instance** (C1 pattern, so Pundit
  resolves `DebateVerdictPolicy`, not `DebatePolicy`), `rescue_from Pundit::NotAuthorizedError → 403`,
  invalid choice → 422. **`DebateVerdictPolicy#create?`** gates spectators-only + concluded-only **AND**
  `DebatePolicy.new(user, record.debate).show?` — closing the must-fix gap where the write endpoint would
  otherwise bypass the Slice-7b read/visibility gate. `_verdict` partial (three `button_to` for an
  eligible not-yet-voted spectator; read-only width-% tally bar for everyone else). rack-attack
  `debate_verdicts/user` (10/min).

**2b — Real-time turns (the app's FIRST Action Cable use — socket authorization is the security crux):**
- **`ApplicationCable::Connection`** `identified_by :current_user`, deriving the user from
  `env["warden"].user(scope: :user)` or `reject_unauthorized_connection` (anonymous sockets rejected at
  the connection layer). **`DebateChannel < Turbo::StreamsChannel`** re-checks `DebatePolicy#show?` at
  **subscribe time** — the signed Turbo stream token is a durable/unrevocable credential, so the socket
  is gated independently of the page. It resolves the `Debate` from `verified_stream_name_from_params`
  (a tampered/unsigned name verifies to `nil` → rejected), guards `is_a?(Debate)` (a validly-signed
  other-model GID can't authorize), and `rescue ActiveRecord::RecordNotFound → reject` (a since-deleted
  debate). Both the channel spec (6) and a dedicated **connection spec** (3, via
  `ActionCable::Connection::TestCase::Behavior` — `stub_connection` bypasses `connect`) cover it.
- **`debates/show`** renders `turbo_stream_from @debate, channel: "DebateChannel"` (viewer-agnostic
  transcript + status — **always** name the channel; a plain `turbo_stream_from` would fall back to the
  UNAUTHORIZED default channel and defeat the whole fix) **and** `turbo_stream_from [@debate,
  current_user], channel: "DebateChannel" if @debate.participant?(current_user)` (user-signed composer +
  actions).
- **Viewer-scoped partials:** `_debate_status` was **split** into `_debate_status` (state label /
  declined note — viewer-agnostic) + new **`_debate_actions`** (Accept/Decline/Conclude — takes an
  explicit **`viewer:` local** via `local_assigns.fetch(:viewer) { current_user }`, NOT the implicit
  `current_user`, which is undefined in a broadcast render context). `_turn_composer` likewise takes
  `viewer:`.
- **Broadcasts** (after `with_lock`, `_later` Solid Queue variants, via a private
  `broadcast_to_each_participant`): `post_turn` appends the turn to `dom_id(:transcript)` + replaces each
  participant's `dom_id(:composer)` on their user-signed stream; `accept!`/`conclude!` replace
  `dom_id(:status)` + per-participant `dom_id(:actions)`. **id-dedup** (`_debate_turn` wraps each row in
  `dom_id(turn)`) means the Slice-4 **synchronous controller `turbo_stream` responses are kept** and the
  async broadcast is an idempotent no-op. **Review catch (fixed):** splitting the buttons out of
  `_debate_status` orphaned the actor's synchronous button update, so `status.turbo_stream.erb` now also
  replaces `dom_id(:actions)` (guarded by request specs) — otherwise the actor's own buttons would only
  update via the async broadcast, which **never fires in dev (no worker)**.

**3 — Timeout auto-conclude:**
- **`DebateTurn belongs_to :debate, touch: true`** so `debates.updated_at` tracks the last **turn**, not
  just the last status change (else the job would conclude actively-argued debates).
- **`conclude!(by: nil)` crash fixed** (v1 called `other(nil).id`): `by.nil?` (the SYSTEM/timeout path)
  notifies **both** participants; a manual conclude always passes `current_user` → `other(by)`.
  `ConcludeStaleDebatesJob` = `Debate.active.where("updated_at < ?", 7.days.ago).find_each { conclude!(by:
  nil) }`, wired into `config/recurring.yml` (production, daily 3am). **Dev has no job worker** — the
  timeout runs in production recurring only (documented; `bin/jobs` runs the worker production-style).

**Deferred (per the roadmap + reviews):** `debate_won` badge (dynamic tally → no coherent finalization);
changeable verdict; a live verdict-tally / status update for non-actor viewers (only the voter's own bar
updates; `decline!` and `accept!`-composer are not broadcast — the spec-sanctioned boundary); a
two-session visual real-time system test (out of cuprite scope — the single-session spec instead asserts
the `turbo_stream_from` subscription tag renders). Carried forward from the whole program: **Vote
array→scalar** migration, **serializer N+1 / prosopite**, **`Api::V1` visibility/block parity**,
**`config.require_master_key`** (L4), **`rack-cors`** (M1), and **Project 3 — Hotwire Native**.

**🏁 Program status:** the "land everything" roadmap is **complete** — Social (follow / Following feed /
@mentions), Debate (MVP + verdict + real-time + timeout), Privacy + Analytics, Badges + Trending, Block,
and Private accounts have all shipped. What remains is the explicitly-deferred niceties above and
**Project 3 (Hotwire Native)**.

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
| `docs/superpowers/slice-9-task-4.6-freeze-audit.md` | Retroactive freeze audit of the forms family + its visual delta list |
| `docs/design-system/` | The design system, extracted from this codebase (`readme.md`, then `MIRROR-NOTES.md`) |
| `README.md` | Stack + run instructions |

---

## Slice 9 (Design System + Debate Phases) — DONE ✅

_Branch `slice-9-design-system`, **not merged**. Suite **513 examples / 0 failures / 2 pending**
(was 273 on `master`). `spec/system` is 30 examples and was run twice back-to-back with zero
flakes. brakeman **0**; `standardrb` clean; `bundler-audit` clean (1232 advisories, DB at `677ced9`).
Built bundle: 23,767 bytes, 365 rules._

The slice adopted the Hoojah Design System across all ~75 views and gave debate turns named
Opening / Counter / Response / Closing phases. Plan:
`docs/superpowers/plans/2026-08-14-slice-9-design-system.md`. Approved design:
`docs/superpowers/specs/2026-08-14-design-system-and-debate-phases-design.md`. The design system
mirror is `docs/design-system/` — start at its `readme.md`, then `MIRROR-NOTES.md`.

**The framing that mattered throughout:** the design system was generated FROM this codebase, so
Phase 4 was a **codification pass, not a redesign**. Every visual change is a documented DS
correction or a bug fix; none is taste.

### What shipped

- **Phase 1 — tokens + brand.** All 72 DS custom properties in
  `app/assets/tailwind/application.css` (`@theme` for namespaced ones, `:root` for `var()`-only
  aliases). Gradient wordmark in the navbar. Closed the latent gap where
  `border-read` / `border-unread` were used by `_notification_card` and defined nowhere.
- **Phase 2 — five primitives.** `ui/_card` (a **layout** partial), `ui/_avatar`, `ui/_divider`,
  `ui/_empty_state`, `ui/_menu`, plus `DesignSystemHelper` (`ds_button_classes`, `ds_card_classes`,
  `ds_avatar_classes`, `ds_menu_item_classes`, `ds_initials`, `ds_debate_state_color`).
- **Phase 3 — debate phases.** `debates.rounds_limit` (default 4) with a safe active-debate
  backfill; derived Opening/Counter/Response/Closing; auto-conclude at `rounds_limit * 2`;
  `extend_rounds!` at the closing-round boundary only, under `with_lock`; the extend endpoint.
- **Phase 4 — all eight view families:** navigation, voting, hujah, social, debate, forms,
  analytics (`c97b1ce`), overlays (`b8db08c`).
- **Phase 5 — gates + docs**, plus four out-of-plan items described below.

### Task 4.6's freeze gap — closed retroactively, verdict CLEAN

`a410be7` (forms) shipped without the per-element freeze harness the other seven families ran; its
implementing agent was killed by a session limit first. A retrospective audit stripped every `class`
attribute and ERB comment from both sides of all ten files and diffed the residue, so the non-`class`
change set is mechanical rather than eyeballed. **No violations.** Full findings and the visual delta
list that was never written: **`docs/superpowers/slice-9-task-4.6-freeze-audit.md`**.

Two incidental facts from it worth keeping: `.btn`, `.btn-link`, `.field` and `.actions` have **no
CSS rule anywhere in this repo** (retired-Bootstrap leftovers), and `devise/confirmations/new` +
`unlocks/new` are **unreachable today** (`User` is neither `:confirmable` nor `:lockable`) — they
were restyled so enabling either module cannot land an unstyled screen.

### Out-of-plan work that landed here

**All fourteen notification categories now render (`7bd60e6`).** `Notification` declares 14
categories; `_notification_card` had 8 `when` arms, so `admin`, `flag` and the four `debate_*`
categories — which fire on **every** debate challenge / decline / your-turn / conclude — rendered
with no icon and no copy. Both `case`es now cover all fourteen plus a terminal `else` (bell +
"You have a new notification") so no future category can render blank. The body chain's final
`elsif notification.badge_earned?` became a bare `else`, which also closes a **stuck-unread bug**:
an `admin` notification with no hoojah previously had no control to click at all.
`NotificationsController#update` now prefers `debate_path` when `notification.debate` is present
(all four `debate_*` categories set both `debate_id` and `hujah_id`); no extra guard is needed
because the recipient is a participant by construction and `DebatePolicy#show?` admits participants
unconditionally in every status — but note the two branches do **not** fail alike, since
`DebatesController` renders a flat 403 where `hujahs#show` gets the friendly redirect.

> ⚠️ **`flag`'s copy is a guess and is the one string not derivable from the code.** Nothing creates
> that category — it is a legacy SPA leftover — so its intended recipient is unknowable. "Your hoojah
> was flagged for review" assumes it addresses the *author*; if migrated production rows actually
> addressed a moderator, it is wrong for them. **Check production data before treating it as settled.**

**The inert `fill-*` utilities are gone (`652c80d`).** Every icon in the product is `lucide_icon`,
and lucide-rails writes `fill="none"` as a **presentation attribute on the `<svg>` itself** — a
specified value, which beats any fill inherited from an ancestor's utility class. All 30 occurrences
sat on wrapping elements, so all 30 were dead, including the one `ds_button_classes` emitted on
every button. Colour reaches icons via `text-<tone>` → `currentColor` → the stroke attribute. The
strip is provably pixel-identical (the only non-Lucide SVGs are `image_tag`-loaded, and an external
SVG document is unreachable by the host page's CSS). A tombstone in `application.css` records why,
and a new helper-spec invariant asserts no variant × tone × size combination ever emits one again.

**A real suite flake, found and fixed during the final sweep.** `spec/requests/rate_limit_spec.rb`
failed once on the compose example, then passed in isolation and on re-run. Cause: **Rack::Attack
counts into a FIXED window, not a sliding one** — the cache key is
`name:discriminator:(Time.now.to_i / period)`. All 16 examples in that file fire limit+1 requests in
a loop and assert the last is throttled, so a loop that straddles a window boundary resets the
counter mid-flight and the final request lands in a fresh window well under the limit. Compose is the
most exposed (21 requests, each creating a `Hujah` and running its `after_create_commit` callbacks —
the slowest loop in the file). Fixed with `around { |example| freeze_time { example.run } }` plus
`config.include ActiveSupport::Testing::TimeHelpers` in `rails_helper`; verified with three
consecutive clean runs of the file and a green full suite. **Note this was invisible to three
back-to-back gate runs** — a green suite is not by itself evidence that a wall-clock-dependent spec
is deterministic.

**Comment-accuracy pass (`5a9061a`).** Reviews found the code correct but ten prose claims false or
overstated. Notably: `ui/_empty_state` has no shadow, so "every other surface carries it" was wrong;
`Card.prompt.md` says "Never round a **feed card**", not "forbids rounding outright" (the DS rounds
dialogs and menus freely) — and that overreach had already propagated by copy. It also converged
`users/_profile_edit`'s dialog X onto `ds_button_classes`, so all three `Dialog.prompt.md` headers
are byte-identical again apart from `id` and title.

### ⚠️ Tailwind gotcha #1 is narrower than CLAUDE.md says — corrected by experiment

CLAUDE.md and earlier slices state that Tailwind v4 "scans the whole repo as text", implying every
comment is a potential safelist. A four-cell experiment (token `rotate-45`, injected independently,
each cell built and reverted, run twice by different agents with agreeing results) shows the
extractors differ **by file type**:

| Placement | Rule emitted? |
| --- | --- |
| `class="rotate-45"` in ERB markup (control) | **yes** |
| `<%# rotate-45 %>` — ERB comment | **yes** |
| `# rotate-45` — Ruby comment | **no** |
| `ROTTEST = "rotate-45"` — Ruby **string literal** | **yes** |
| `%i[rotate-45]` — Ruby bare word / symbol | **no** |
| `/* rotate-45 */` in `app/assets/tailwind/application.css` | **no** |

So: **the "write `bg-<stance>`, never a concrete class" discipline is load-bearing in ERB (and JS,
YAML, SVG, Markdown) but NOT in Ruby `#` comments.** In Ruby it is specifically *string literals*
that are extracted. This is exactly why `.outline` never shipped from the dozen `variant: :outline`
symbols — an earlier agent concluded the opposite and recommended renaming the variant; **that
conclusion was wrong, do not act on it.** The input CSS file is not scanned as a source at all,
which makes the `application.css` tombstone inherently leak-proof.

Two real leaks were caught and removed this slice: `.grid` came from `app/assets/images/Untitled
Diagram.drawio` (`grid="1"`), fixed with `@source not "../../../app/assets/images"`; `.outline` came
from four ERB comments, fixed by rewording. And `.fill-black` — removed with the rest — was in **no**
`@source inline` line and existed *only* because a comment spelled it literally.

**Nine rules still ship that no view asks for.** Documented, not fixed:

| Rule | Source |
| --- | --- |
| `.capitalize` | `stance.capitalize` in four ERB views |
| `.filter` | `params[:filter]` in five ERB views |
| `.blur`, `.grow`, `.visible`, `.container`, `.inline` | ordinary prose in ERB comments (`.container` also from YAML config; `.inline` pervasively from `@source inline(...)` written in prose, incl. `CLAUDE.md`) |
| `.static` | `vendor/javascript/local-time.js`, Stimulus `static targets =`, and `t.boolean "static"` in `db/queue_schema.rb` |
| `.transform` | **`public/safari-pinned-tab.svg`** — its `<g transform="…">` attribute, bisect-proven as the only source |

Cost is a few hundred bytes and there is no correctness risk. `.transform` is removable by adding
`public/safari-pinned-tab.svg` to the `@source not` list. Also untracked-by-`@source not` and worth
knowing if you ever chase more phantom rules: `README.md`, `CLAUDE.md`, and the two ~5MB
`.yarn/releases/yarn-*.js` bundles are all scanned.

### Other defect classes this slice found — do not reintroduce

1. **`@source not` paths resolve relative to the working directory, not to the CSS file.** Building
   the bundle from anywhere but the repo root re-admits `docs/` and `spec/` and silently adds ~14
   rules. Anything that builds this bundle must `cd` to the repo root first.
2. **A comment describing a class you just deleted can resurrect it.** One agent's draft fix spelled
   a *retired* class literally and would have re-added two rules while documenting their removal.
   Write `fill-<tone>`, never a concrete name — and run the canary.
3. **The canary needs a positive control.** md5 the bundle, strip only the new comments, rebuild,
   compare — but also append a comment naming an unused class and confirm the hash *moves*. Without
   that, a broken harness is indistinguishable from a clean result. One agent's control failed and
   led directly to the extractor finding above.
4. **Interpolated variant classes die silently.** `@source inline("bg-agree")` safelists the *bare*
   utility, not `peer-checked:bg-agree`.
5. **Same-family utilities resolve by bundle order, not call order.** `.px-4` precedes `.px-5`. Hence
   `ui/_menu`'s required `width:` and the rule that `ui/_card`'s `padded:` must never be combined
   with padding in `class:`.
6. **A border with no colour class inherits `currentColor`** — indigo inside an `<a>`, because
   `@layer base` makes anchors `--fg-link`.
7. **`have_broadcasted_to(...).with { }` runs its block against EVERY payload on the stream** — it
   asserts "every broadcast was this one", not "this one was broadcast".
8. **The freeze harness's blind spot is `class`** — the only thing a DS refactor changes. Every
   visual delta must therefore be written out in prose by hand; the mechanical diff cannot see it.

### Two commit messages are known-wrong and were deliberately not amended

The workspace rule is never to `git commit --amend` unless HEAD is verifiably your own commit — an
agent amending another's already cost a history repair on this branch. So these stand, corrected here:

- **`652c80d`** says "24 occurrences across 19 views". The true figure is **30 fill tokens across 28
  lines in 19 views**, plus 6 in `ds_button_variant` and 3 safelist members.
- **`b8db08c`** presents the challenge trigger's gain as "`transition` + `active:scale-95` (and an
  explicit `p-0`)". Three more are unlisted — `justify-center`, `disabled:opacity-50`,
  `disabled:cursor-default` — all inert there. The in-file comment now carries the complete list.

### Deferred out of this slice

- **`_distribution_bar`'s unused `count` block arg** — `|stance, count, pct|` never reads `count`.
  StandardRB only lints `.rb`, so nothing catches it in ERB. Pure churn to fix; sweep it with other
  ERB housekeeping.
- **`spec/system/analytics_spec.rb`'s `have_content("5")`** — the page also renders "fewer than 5
  votes", so that assertion passes even if the stat chip vanishes. Suggested fix: assert the stat
  row's normalized text equals `"5 Votes received"`, which survives class-level refactors. A class
  selector would re-couple the spec to exactly the classes this slice churns; a `data-testid` is a
  markup addition that deserves an explicit decision.
- **`spec/models/notification_spec.rb` is an empty `# Not yet implemented` stub** — the enum, the
  four `optional: true` associations and the `unread` scope have no model-level coverage; everything
  is pinned only indirectly through request specs. (`spec/models/flag_spec.rb` is the other stub;
  these two are the suite's 2 pending.)
- **`app/assets/tailwind/application.css`'s `@layer base` comment** still refers to the layout's
  `<body class="body">`, removed in `8da23b2`. Zero CSS impact — the input CSS is not scanned — but
  it wants a one-word fix.
- **Section-head idiom differs across three families** (`trending/_trending`, `debates/_verdict`,
  `analytics/show`). Adjudicated as **not drift**: the DS pins per-component where a `.jsx` exists
  and is silent otherwise, and `_verdict` is an exact port of `Verdict.jsx`. Trending's uppercase is
  the mild outlier. Do not "unify" these.
- **A terminator hairline above the first and below the last dialog choice row** — the old bounding
  box drew one; the DS-native replacement would be a `ui/_divider` at each end.
- `pinned-tab.svg` repair + favicon wiring; `loading.svg` animation restoration; `app-icon-512.png`
  (fetch when Project 3 starts); the unmirrored `*.d.ts` / `*.jsx` / `guidelines/*.html` /
  `ui_kits/web/*.jsx`, fetchable on demand via the `DesignSync` MCP tool (main-loop only).
- `debate_won` badge (still blocked on a finalized verdict tally, per Slice 8).
- Carried forward from the program: **Vote array→scalar**, **serializer N+1 / prosopite**,
  **`Api::V1` visibility/block parity**, **`config.require_master_key`** (L4), **`rack-cors`** (M1),
  and **Project 3 — Hotwire Native**.

### Environment notes specific to this slice

- **All agents share one Postgres test DB.** Concurrent full-suite runs collide with
  `PG::ObjectInUse`. Run one implementer at a time; reviewers should use targeted specs or none.
- `spec/support/tailwind_build.rb` rebuilds the bundle once per suite run — needed because
  `app/assets/builds/tailwind.css` is gitignored and nothing else rebuilds it before RSpec.
- The working method that paid off, again: implementer → independent spec/quality review → batched
  fixes → re-verify. Reviews this slice caught a false "spec compliant" premise, four false comment
  claims, a concealed header divergence, and one agent's incorrect root-cause for `.outline` that
  would have led to renaming a helper variant for no reason. **Verify agent claims before acting on
  them** — one audit's sole reported defect was itself a false positive.

---

## Post-Slice-9 review passes (2026-08-17) — simplifier, Stimulus, security

Three specialist passes over the finished slice, run analysis-first so proposals could be triaged
against this codebase's many recorded decisions before anything was edited. Suite went
**513 / 0 / 2 → 530 / 0 / 0** — the two `# Not yet implemented` stubs are gone, so there are now
**no pending examples**. brakeman 0, standardrb clean, bundler-audit clean throughout.

Commits: `fc3afa7` (Stimulus tidy + the API flags bug), `1b04b79` (audit ledger),
`26c577a` (simplifier findings).

### Security audit — clean

No new findings at Critical/High and **no regressions** across the slice's 47 commits / 160 files.
Twelve security-critical invariants were verified by direct source inspection rather than by trusting
the comments — full list and the two ledger re-triages are in `SECURITY-FINDINGS.md` under
"Audit 2026-08-17". Headline corrections: **M1 (CORS) came down Med → Low** (the config only admits an
`Origin` a browser never sends from another page — dead config, not a live hole, but still fix before
Project 3 since native clients aren't CORS-gated at all), and **L1 was narrowed to
`Api::V1::FlagsController` and then closed** — it was the last holdout of the `.create` + `if record`
success-on-failure bug, reporting 200 on an unpersisted record.

### What changed

- **`Hujah#current_user_vote` ran its query twice** — once to nil-test, once to read — with a
  redundant `joins(:user)` and a 1/2/3 if/elsif ladder, on the hottest read path in the app (six ERB
  sites + the serializer, several per feed card). Now one `find_by` through a new
  `Hujah::STANCES`, from which `COUNTER_FOR` is derived so the stance trio has one home instead of
  two. The join was safe to drop because `User has_many :votes, dependent: :destroy`.
- **`DebatePolicy::Scope#resolve` N+1'd both participants** on every concluded debate. Now
  `.includes(:challenger, :opponent)`; the deliberate Ruby-side `select` is unchanged, since
  visibility is follow-graph dependent and cannot move into SQL.
- **`DebatesController#create` gave two different answers to two bad inputs** — a forged parent got a
  clean 422, but a bogus `argument_id` raised `RecordNotFound`, which nothing handles, turning a
  `turbo_stream` POST into a 404 HTML page. The constraint is now the scope of the lookup
  (`@hujah.children.find_by(id:)`), so both converge on 422.
- **Four identical `rescue ActiveRecord::RecordInvalid` blocks** in `DebatesController` collapsed to
  one `rescue_from`. `create`'s `RecordNotUnique` rescue stays inline — different exception class.
- **`Hujah#has_children?` was dead** and is deleted.
- **`spec/factories/flags.rb` had never been run.** It said `hoojah { nil }` — no such attribute, the
  association is `hujah` — so `create(:flag)` raised `NoMethodError`. **That is why `flag_spec.rb`
  was a stub.** Factory fixed; both model stubs filled (7 + 11 examples).
- **`hello_controller.js`** (stock scaffold, unreferenced) deleted; **`cloudinary_upload_controller`**
  gained the `disconnect()` teardown it never had — it created a widget in `connect()` whose iframe
  lives *outside* the controller's element, so Stimulus's own bookkeeping never cleaned it up.

### The secret-ballot guard now has a test

The rule that a `new_vote` notification carries **no `subject_user_id`** was previously asserted only
from the `Hujah` side. `spec/models/notification_spec.rb` now pins it three ways: the notification is
valid and persists with a nil `subject_user`; `reflect_on_association(:subject_user).options[:optional]`
is `true` — **the thing a "tidy" would flip**; and `cast_vote` actually writes a row with no voter
recorded. This is the guard against someone making that association required and silently
de-anonymizing voters through the serializer.

### Traps recorded by these passes

- **`Flag` cannot be made invalid through its enum.** Assigning an out-of-enum `subject` raises
  `ArgumentError` (a 500), not a validation error. Use a nonexistent `hujah_id`, which fails as
  `hujah: ["must exist"]` under `load_defaults 8.1`.
- **`Notification.unread` is never globally empty in a fresh example.** `create(:notification)`'s
  `association :hujah` fires `award_authoring_badge`, which writes an unread `badge_earned`
  notification for a *different* user. Scope assertions to `user.notifications.unread`. This is a
  live property of the factory graph, not a test artifact.
- **`window.cloudinary` is never defined under Cuprite** (host blacklisted, script skipped in test),
  so `cloudinary_upload_controller`'s widget branch — including its new `disconnect()` — is
  **unreachable in specs**. A green suite is not coverage there; the teardown is guarded three ways
  for that reason.

### Deferred with reasoning — decisions, not oversights

- **The stance trio is three un-enum'd integer columns** (`hujahs.vote`,
  `debates.challenger_stance`, `debates.opponent_stance`), all carrying the same closed 1/2/3 domain.
  So `DebatesController#create` does a raw int hop between two tables and `Debate` cannot distinguish
  a real stance from a `7`. **The largest latent simplification in the codebase — and it needs its own
  slice.** The hazard is specific: enum-ing `Hujah#vote` flips its reader from `1` to `"agree"`, which
  then lands in `opponent_stance:` on a non-enum integer column and **coerces to 0** — silent data
  corruption unless both models move in one commit, plus every view and `HujahSerializer` reading
  `.vote`, plus a backfill audit.
- **`current_user_vote`'s `logged_in:` keyword is dead weight** — `find_by(user_id: nil)` already
  yields nil, and three of the eight call sites hardcode `logged_in: true`. Removing it is a 9-site
  change (7 ERB + `HujahSerializer` + a spec).
- **`Api::V1::FlagsController`'s `flag_params` has no `require`** — a POST with no `flag` key raises
  `NoMethodError` on nil → **500**, before `authorize` is reached. The HTML sibling already uses
  `require`. Left open because changing it alters the API's answer to a malformed request, which is a
  contract decision for the native-client surface.
- **`DebatePolicy#extend?` was NOT aliased to `conclude?`** despite being byte-identical and despite
  the house precedent `decline? = accept?`. Aliasing couples them, so a future tightening of
  `conclude?` would silently narrow `extend?` — in a policy, silent narrowing is the worst failure
  mode. The existing comment already states the intent.
- **`IconsHelper#stance_color` answers a colour question via the icon map** — correct today only
  because the key sets coincide. Not changed: the fix would have a helper reach into a model
  constant, which is its own smell.
- **`debate_composer_controller`'s `connect()` calls `.focus()`, which scrolls by default** — so a
  "your turn" broadcast yanks a mid-transcript reader down to the composer. `connect()` also fires on
  Turbo cache-restore, contrary to its own comment. `focus({preventScroll: true})` would fix the
  first; whether the scroll is a feature is a product call.
- **`_challenge_dialog`'s wrapper carries both `data-controller="dialog"` and
  `data-response-filter-target="item"`.** Open the modal, then click a filter tab that hides that
  stance, and the ancestor gets `hidden` while the `<dialog>` is still in the top layer. **Reasoned,
  not verified** — settling it needs a headed Cuprite session.

### Process gap — there is no CI

No `.github/workflows/`, no `bin/ci`. brakeman, bundler-audit and standardrb run manually per
`CLAUDE.md`. Every gate in this program has been green **by convention, not by enforcement** — and
this session found a wall-clock-dependent spec that three consecutive green runs missed. Worth a
decision before Project 3.
