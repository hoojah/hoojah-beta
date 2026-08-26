# Security Findings — Hoojah (post Rails 6.0→8.1 upgrade)

Source: `rails-security-auditor` + Brakeman 8.0.5 + bundler-audit 0.9, run 2026-08-04 on Rails 8.1.3.1 / Ruby 3.4.9.

**Brakeman: 0 warnings.** **bundler-audit: 1 (shakapacker — see below).**

> **Scope note.** This was a *Rails upgrade* (Project 1). The audit surfaced many
> **pre-existing application-logic vulnerabilities** that existed in the original Rails 6.0
> app — they are NOT upgrade regressions. Fixing them changes the JSON API contract the
> React SPA depends on and would require rewriting the characterization specs (which
> deliberately capture current behavior). Those are **product/security decisions for the
> owner** and are best done as a dedicated security pass or folded into Project 2 (where the
> front-end + auth flow are reworked for Hotwire). They were **not** changed here.

---

## ✅ Fixed in this pass (safe, convention-level, no API-behavior change)

- **Security tooling added** (audit H5): `brakeman` + `bundler-audit` in `:development, :test`.
- **`config.force_ssl = true` + `config.assume_ssl = true`** in production (audit H2) — HSTS + Secure session cookie; TLS terminated at Kamal/Thruster proxy.
- **`config.log_level` → `info`** (was `:debug`) + `config.hosts` allowlist via `ENV["APP_HOST"]` (audit M2, M3).
- **Expanded `filter_parameters`** to cover email/secret/token/_key/crypt/salt/etc. (audit M3).

All above are production/tooling only; test+dev suite stays green (24/0/2).

---

## ⚠️ OPEN — the whole of it

**One item open.** `2a`, the four Slice-11 low follow-ups (`vote?-block`, `notif-param-500`,
`A7 counts`, `username-uniq-index`), and `verdict-k` are all **closed** (2026-08-26) — see the two
"Closed" passes below. The **only** remaining open item is the deploy-gated master-key item. Read
this table and stop.

| ID | Severity | Issue | Where it lands | State |
|----|----------|-------|----------------|-------|
| L4 | Low | `config.require_master_key` commented out in `production.rb:19` | Deploy track, **not a slice** | Open by design. Gated on the deploy providing `RAILS_MASTER_KEY`, not on any code change here. Enabling it before the key exists turns a boot into a crash. |

**Accepted residual risk (not a scheduled item).** The 2a k-anonymity rule is a pure count
threshold. Because replying requires a prior vote and a child hoojah publicly carries its author's
stance, voters who *also replied* have voluntarily disclosed their stance — so the effective
anonymity set is `total_votes − publicly-stance-tagged voters`, not `total_votes`. At exactly total=k
with k−1 stance-tagged repliers, the revealed split pins the one silent voter. Repliers self-disclosed;
closing the boundary case for the lone silent voter needs a reply-aware threshold, deferred. Accepted
2026-08-26.

---

## ✅ Closed — verdict-k + unified k=3 (2026-08-26) — branch `security/verdict-k`

Owner decision 2026-08-26: **lower the secret-ballot threshold k from 5 to 3 everywhere**, and extend
the gate to debate spectator verdicts (hiding the winner too, since the winner is derived from the
counts). Explore → spec → subagent TDD → Fable leak-review (confirmed the verdict gate is tight and no
literal-5 threshold survives).

| ID | Issue | Closed by | What changed |
|----|-------|-----------|--------------|
| **k=3** | The 2a/A7 threshold was 5; owner lowered it to 3 for all secret-ballot surfaces. | `bd423a9` | `UserAnalytics::K` `5 → 3` — the single source `Hujah::VOTE_BREAKDOWN_MIN`, the analytics `suppressed?`, and the new verdict gate all reference it, so hoojah vote breakdowns, the analytics distribution, and verdicts now reveal at **3+**. User-facing copy ("fewer than K votes", "sealed until K") interpolates the constant. All boundary specs moved 5→3 (below-k at total 2, ≥k at total 3). |
| **verdict-k** | Debate spectator-verdict winner + percentages rendered with no k floor — same secret-ballot class as 2a, different electorate. At 1–2 voters the winner itself leaks a vote. | `9ee69bc` | `Debate#verdict_visible?` (`total_verdicts >= UserAnalytics::K`). Below k the concluded winner-hero (`_verdict.html.erb`) suppresses the winner, crown, "Winner" pill, percentages, result bar and dimming — showing only the always-safe "Decided by N spectators" total, a "sealed until K" note, and the viewer's OWN verdict (`Debate#verdict_by`). At ≥k the hero is unchanged. The winner/pct computation was moved *inside* the ≥k branch so nothing derived from the split reaches the DOM below k; the turbo re-render inherits the gate. No debate/verdict serializer exists, so there is no API leg. |

## ✅ Closed in the secret-ballot + hardening pass (2026-08-26) — branch `security/secret-ballot-and-hardening`

Built off `master` after the cloudinary-google-auth merge. Compressed brainstorm (owner decisions
recorded here) → spec → **pre-implementation Fable leak-audit** (caught the `UserSerializer#hujahs`
API leak the first draft missed, and confirmed analytics was already gated) → subagent-driven TDD
(per-track implementer + Fable spec/quality/leak review + batched fixes). Isolated-DB full suite
green; standardrb + brakeman 0 + bundler-audit 0.

| ID | Issue | Closed by | What changed |
|----|-------|-----------|--------------|
| **2a** | Public per-stance vote breakdown de-anonymizes voters at a small electorate. | `c9526ac` `075cc75` `8850aa2` `8bb4cab` `2fa392b` | Single model rule `Hujah#breakdown_visible?` (`total_votes >= VOTE_BREAKDOWN_MIN`, where `VOTE_BREAKDOWN_MIN = UserAnalytics::K = 5` — one threshold, no drift). Below k every surface shows the **total + the viewer's own stance** only, never a per-stance count/percentage/bar; at ≥k the full split as before. Gated: `_vote_bars`, `_vote_hero`, `_child_card`, `_user_hujah` (HTML) and `HujahSerializer` (+ nested `children`) (API). Serializer gate single-sourced via `Hujah#ballot_counts`. **No author exception** (the author is an observer too — consistent with the id-less `new_vote` notification). Each surface has a below-k absence spec + ≥k positive control. |
| **A7 counts** | `UserSerializer#hujahs` per-stance counts + the analytics distribution — same class as 2a. | `8850aa2` `2fa392b` (+ pre-existing `UserAnalytics::K`) | `UserSerializer#hujahs` now gated identically (nil below k, always-present `total_count`) — this was the leak the Fable audit caught (reachable via `GET /api/v1/users/:username`). The analytics aggregate distribution was **already** suppressed below k via `UserAnalytics::K`/`#suppressed?`; pinned by spec. |
| **vote?-block** | `HujahPolicy#vote?` lacked the `hidden_user_ids` block check `#create?` has. | `e359ed7` | `#vote?` now `user.present? && record.visible_to?(user) && !user.hidden_user_ids.include?(record.user_id)`. Bidirectional (blocker + blocked-by). Spec: blocker forbidden, blocked-by forbidden, unrelated allowed. |
| **notif-param-500** | `Api::V1::NotificationsController#notification_params` missing `require`. | `e359ed7` | `params.require(:notification).permit(:read)` + a scoped `rescue_from ActionController::ParameterMissing → :bad_request` mirroring `Api::V1::FlagsController`. Missing key → **400**, happy path (200 + `read` flipped) unchanged. (Found: pre-fix it was actually a silent 200 via param-wrapping, not a 500.) |
| **username-uniq-index** | No unique DB index on `users.username`; `User.generate_username` (OAuth) is check-then-act. | `e359ed7` | Migration `add_index :users, :username, unique: true, algorithm: :concurrently` (`disable_ddl_transaction!`). DB now rejects a duplicate (spec via `save!(validate: false)`). **Deploy note:** confirm `SELECT username, COUNT(*) FROM users GROUP BY 1 HAVING COUNT(*) > 1` is empty before the deploy runs this migration — a concurrent unique build aborts (and leaves an INVALID index) if duplicates exist. Dev/test have none. Username lookup stays **case-sensitive** (matches the existing model validation; a `lower(username)` index was considered and deliberately deferred — it would require case-insensitive lookups too). |

## ✅ Closed in Slice 11 (2026-08-25) — the `Api::V1` hardening pass

Branch `slice-11-api-hardening` (off `master` `e82acab`). `bin/ci` green: **886 examples / 0
failures**, standardrb + brakeman 0 + bundler-audit 0. Built brainstorm-compressed (owner
decisions were already recorded here) → plan → **pre-implementation Fable leak-audit** (caught two
A1-class leaks the first draft missed — the `UserSerializer#hujahs` list and the reply-serving feed
index) → subagent-driven TDD (per-task implementer + spec/quality review) → **`rails-security-auditor`
pass: A1/A2/A4 CONFIRMED CLOSED, no new findings**. Plan:
`docs/superpowers/plans/2026-08-25-slice-11-api-hardening.md`.

| ID | Issue | Closed by | What changed |
|----|-------|-----------|--------------|
| **`Api::V1` read parity (A1)** | Serializer-nested + feed-index + user-endpoint content bypassed the Slice-7b/2026 visibility gates: a private/blocked/per-post-restricted author's body+username reachable via the JSON API. | `1ad534c` `e56b817` `5600051` `62ce577` `42fcab7` `daf4feb` | Extracted the two inline visibility predicates onto the model — `Hujah#visible_children_for` (from `HujahsController#show`) and `User#visible_hujahs_for` (from `UsersController#profile_tab_list`) — so HTML and API share ONE SQL-filtered gate. `HujahSerializer` (`children`/`children_count`/`parent`, the last with an added block check) and `UserSerializer` (`hujahs`/`hujah_count`) are now viewer-aware via a Devise-session `current_user:` serializer param (not request-forgeable). The `Api::V1` feed index is now **top-level only** (`parent_id: nil`, closing the public-reply-under-a-restricted-parent leak) **and** block-filtered for signed-in callers. Each leak has a named spec in `spec/requests/api/v1/api_visibility_spec.rb` (incl. a block-dimension `parent` test proven by temporary clause-removal) + `users_spec.rb`. **Contract change:** the user endpoint's `hujahs`/`hujah_count` are now top-level-only (were all hujahs incl. replies) — the intended secure behaviour; follower-aware parity for restricted top-level claims stays deferred to Project 3. |
| **`flag_params` (A2)** | `params[:flag].permit(...)` with no `require` → `NoMethodError` on nil → 500 **before** `authorize`. | `b2a5940` | `params.require(:flag).permit(...)` + a scoped `rescue_from ActionController::ParameterMissing → :bad_request` in `Api::V1::FlagsController` (needed because the test env runs `show_exceptions = :none`; mirrors the documented in-controller-rescue convention). Now 400, not 500. Spec asserts the real 400. |
| **M1 (A4)** | Dead `rack-cors` config (`localhost:3000`, `credentials: true`) from the retired React dev server. | `e39d338` | `config/initializers/cors.rb` deleted; `rack-cors` removed from `Gemfile`/`Gemfile.lock`. `rails middleware` boots clean with no `Rack::Cors`; no dangling reference. |

Also folded in (not a ledger item — a robustness bug found during the A1 work): `NotificationSerializer#hujah`
used `Hujah.find(notification.hujah_id)`, which **500'd the entire notifications index** once any
referenced hoojah was deleted (`notifications.hujah` is `optional: true`). Switched to the nil-safe
association accessor (`16c6acc`); the private-account `visible_to?` gate (Slice 7b) is unchanged.

---

## ✅ Closed — the 2026-08-04 deferrals, reconciled in Slice 10

Twelve of the rows this page listed as "deferred — owner decision required" were fixed during
Project 2, mostly as a side effect of the Devise and Pundit migrations rather than as a
dedicated security pass. They stayed *listed* as open for months, which defeats the purpose of
a ledger: the genuinely-open set above was unreadable underneath them.

The independent confirmation is the **2026-08-17 audit below: no findings at Critical or High,
anywhere.** Every row here was Critical, High or Medium. The `Closed by` column is the primary
evidence — each SHA was traced with `git log -S` against the exact file and line the original
auditor cited, not inferred from a commit subject.

| ID | Severity | Issue | Closed by | What actually changed |
|----|----------|-------|-----------|------------------------|
| C1 | Critical | `render json: @user` leaks `password_digest` + `email` on every login / `is_logged_in?` / signup (`sessions_controller.rb:9,24`, `users_controller.rb:37`) | `691cbb4` + `28c30d4` | Both leaking controllers were **deleted, not patched**. `691cbb4` removed `SessionsController` when `devise_for` took over `/login`; `28c30d4` removed the orphaned top-level `UsersController`. `Api::V1::UsersController` was never part of C1 — it has gone through `UserSerializer` since 2020. Locked by `b703896`, whose sessions spec asserts no digest reaches the response. |
| C2 | Critical | `Api::V1::VotesController` has no auth; trusts `params[:user_id]` — vote as anyone | `9db1f07` | Adds `before_action :authenticate_user!`, drops `:user_id` from `vote_params`, derives the voter from `current_user`. |
| C3 | Critical | Notifications `update`/`destroy` IDOR — no auth, unscoped `find(params[:id])` | `e53f945` | Closed via Pundit rather than by rescoping the finder: `authenticate_user!` + `authorize notification` on both actions, `policy_scope(Notification)` on index, and the by-username `find_user` lookup removed. Spec: `971c649`. |
| C4 | Critical | `hujahs#destroy` unauthenticated + no ownership check | `74d8fc2` | `authenticate_user!` plus `require_owner!` (`head :forbidden unless hujah&.user_id == current_user.id`). |
| C5 | Critical | Legacy non-namespaced `VotesController` + `resources :votes` — unauthenticated CRUD (dead scaffold) | `691cbb4` | The 74-line scaffold deleted and `resources :votes` replaced by `devise_for :users` in the same commit that killed `SessionsController`. |
| H1 | High | CSRF disabled app-wide (`skip_before_action :verify_authenticity_token`) | `691cbb4` | Strips the skip and the hand-rolled session helpers from `ApplicationController`. The paired JSON strategy landed one commit later in `d39d9a3` (`Api::V1::BaseController` with `null_session`) — which is the CSRF split the 2026-08-17 audit re-verified as invariant 1. |
| H4 | High | No shared auth enforcement; `current_user` truthiness by accident (500, not 401) | `d20ea6e` + `e53f945` | `d20ea6e` adds `include Pundit::Authorization`, `after_action :verify_authorized` (Devise-exempt) and `ApplicationPolicy`; `e53f945` applies `authorize`/`skip_authorization` across every controller. This is why the codebase now *cannot* ship an unauthorized action — it raises. |
| H6 | High | `:id` permitted in `user_params` (PK mass-assignment) | `28c30d4` | `permit(:username, …, :id, :user)` → an explicit attribute list, plus a regression spec asserting an injected `:id` cannot reassign the primary key. |
| M4 | Med | No CSP | `581d9ac` | Replaces the fully-commented-out default initializer with a real policy (default/script/style/img/connect/frame-src) and a nonce generator. Follow-up `dcc9303` fixed the nonce (`SecureRandom`, not `session.id`, which was blank for first-time anonymous visitors). |
| M6 | Med | No minimum password length | `4e5fd96` (+ `a1ed040`) | `config.password_length = 8..128` in the Devise initializer. Enforcement needs `:validatable`, which arrives with the User model's Devise migration in `a1ed040`. |
| M7 | Med | `link` field unsanitized (stored-XSS risk if rendered as an href) | `f060284` → `a262f26` | `f060284` adds `validates :link, format: {with: %r{\Ahttps?://}i}, allow_blank: true`; `a262f26` anchors it end-to-end (`%r{\Ahttps?://\S+\z}i`) so a trailing newline cannot smuggle a second line past the matcher. `a262f26` is the commit that took brakeman to 0. |
| L3 | Low | Invalid login returns HTTP 200 with `{status: 401}` in the body | `691cbb4` | Died with `SessionsController`; Devise's `sessions#create` returns a real 401. `b703896` rewrote the spec to assert it. |

Two later findings, both closed, kept here for the same reason:

| ID | Severity | Issue | Closed by |
|----|----------|-------|-----------|
| L1 | Low | create actions use `.create` + `if record` (always truthy) → failures reported as success. Last holdout `api/v1/flags_controller.rb:6` | `fc3afa7` — `.new` + `if flag.save`; failure is now `:unprocessable_content`. Detail below. |
| — | High | Every rack-attack throttle bypassable via a `.format` suffix; `signup/ip` never fired at all | `99f7898` — one shared `throttled_path` helper. Detail below. |

---

## Dependency CVE (bundler-audit)

- **GHSA-96qw-h329-v5rg — shakapacker 6.6.0 (High):** EnvironmentPlugin can leak ENV secrets into client bundles. Fix = shakapacker ≥ 9.5.0.
  - **Accepted for now, tracked in `.bundler-audit.yml`.** Rationale: the webpack/React JS build is not active during the upgrade and **shakapacker is removed entirely in Project 2** (React → Hotwire on importmap+Propshaft). Bumping to 9.x means the exact webpack-rename churn the upgrade deliberately avoided, on code about to be deleted. Re-audit after Project 2; the ignore entry should be removed then.

---

## ✅ Fixed in Slice 9 (2026-08-16) — rack-attack throttles were bypassable

Found while reviewing the Slice 9 debate-extend endpoint, which had been told to mirror an
existing throttle block. The mirror propagated a defect present in **every** throttle.

**1. Format suffix bypassed all 13 throttles.** Every Rails route accepts `(.:format)`, but the
matchers anchored on the bare path — `req.path == "/login"`, or `%r{\A/debates/[^/]+/extend\z}`.
A `.json` / `.turbo_stream` / any `.ext` suffix therefore missed the matcher entirely while still
reaching the controller. Demonstrated: 40 × `POST /debates/:slug/extend.turbo_stream` produced
**zero 429s** and the first request succeeded.

**The auth throttles were the serious case.** 11 × `POST /login.json` returned **401, not 429** —
Devise ran eleven real credential checks. `login/email` was bypassed identically, so the
per-account limit was gone too, leaving an unmetered credential-stuffing endpoint.
`password/ip` is a live mail-bombing vector: `POST /password.json` raises `UnknownFormat`, but
*after* `send_reset_password_instructions` — the mail goes out, then it 406s.

**2. `signup/ip` never fired at all.** `devise_for path: ""` puts `registrations#create` at
**`POST /`**; `/signup` is only the GET form. The matcher was `req.path == "/signup" && req.post?`,
which nothing ever sends. Account creation had **no** rate limit, format suffix or not.
Verified: `bin/rails routes` shows `POST / → users/registrations#create`.

**Fix.** One shared `Rack::Attack.throttled_path(*segments)` helper building
`%r{\A/<path>(\.[^/]+)?\z}`. Literal segments are `Regexp.escape`d; dynamic ones pass an
`ANY_SEGMENT` sentinel so escaping cannot swallow the wildcard. All 13 throttles are built
through it, so a newly added throttle cannot reintroduce the gap. The suffix group is `[^/]+`
rather than `\w+` deliberately — over-matching an unrouted path costs nothing, under-matching
is the bug.

**Coverage.** 12 new request-spec examples, each red before the fix: format-suffixed hits on
extend / verdicts / turns / challenge / flags / compose / follow / unfollow / block / password /
login, plus signup at the corrected `POST /`. Matcher boundaries asserted directly (16 cases)
including the negatives `/u/bob/followers` ∉ `FOLLOW_PATH` and `/hoojah/x/flags` ∉ `COMPOSE_PATH`.

**Watch item.** `signup/ip` now genuinely throttles `POST /` at 5/min per IP. That is the
intended behaviour but it is newly enforced, and shared-NAT users are the population most likely
to notice.

**Note on test coverage limits.** Rack::Attack is disabled for system specs (its user-keyed
throttles mis-deserialize the Warden test stash under Devise 5), so request specs are the only
guard. Commits: `99f7898`.

---

## Audit 2026-08-17 (post-Slice-9, branch `slice-9-design-system` @ `459575e`)

Full `rails-security-auditor` pass over the config, application and infra layers, cross-referenced
against this ledger. **brakeman 0 warnings** (21 controllers / 14 models / 66 templates);
**bundler-audit 0 vulnerabilities** (DB `677ced9`, 1232 advisories). The `.bundler-audit.yml` ignore
file is **gone** — the shakapacker CVE above is resolved by deletion, since shakapacker was fully
removed in Project 2. That entry is now historical.

**No new findings at Critical or High. No regressions in Slice 9's 47 commits / 160 files.**

### Twelve invariants verified by direct source inspection (not by trusting comments)

1. CSRF split holds — `Api::V1::BaseController` is the only `null_session`; every CSRF-needing write
   route is declared as a main route.
2. `DebateTurnsController#create` authorizes a `DebateTurn` **instance** → `DebateTurnPolicy#create?`.
3. `DebateVerdictsController#create` authorizes a `DebateVerdict` **instance**, and
   `DebateVerdictPolicy#create?` delegates to `DebatePolicy#show?` so the write cannot bypass the read gate.
4. `ApplicationCable::Connection` rejects sockets with no Warden user; `DebateChannel#subscribed`
   re-checks `DebatePolicy#show?`, resolves via `verified_stream_name_from_params`, guards
   `is_a?(Debate)`, rescues `RecordNotFound`.
5. **Every `turbo_stream_from` in the app names its channel** — exactly two hits, both
   `channel: "DebateChannel"`. A bare one would silently fall back to the unauthenticated default.
6. All 13 rack-attack throttles route through the shared `throttled_path` helper; no matcher is built
   outside it, and the Slice 9 `debate_extend` throttle is present and covered.
7. `verify_authorized` cannot be satisfied vacuously — the two intentional early-outs
   (`DebatesController#create`'s forged-`argument_id` guard, `DebateVerdictsController#create`'s bad-
   `choice` rescue) both call `skip_authorization` before returning.
8. CSP has no `unsafe-inline` on `script-src`; the one inline script uses a per-request nonce.
   `style_src` does carry `unsafe-inline`, documented as intentional for the Turbo progress bar.
9. Devise: `paranoid = true`, `password_length = 8..128`, `pepper = nil` deliberately (a pepper would
   invalidate the migrated bcrypt hashes), `stretches = 12` matching the legacy cost.
10. Rails 8 default security headers unmodified.
11. `force_ssl` + `assume_ssl` is the documented Kamal/Thruster pattern, not a missing SSL redirect.
12. `filter_parameters` breadth is adequate against the model/param surface.

### The Slice 9 commit that needed the closest look — cleared

`7bd60e6` added a `debate_path` branch to `NotificationsController#update`. Both angles traced:
**open redirect** — neither branch is user-input-driven; both paths are built from the notification's
own associations. **Authorization bypass** — `authorize @notification` (→ `NotificationPolicy#update?`
= owner) runs *before* the branch, `Debate#notify`'s recipient is a participant by construction, and
`DebatePolicy#show?` admits participants unconditionally in every status. `DebatesController#show`
re-authorizes on arrival regardless.

### M1 (CORS) re-triaged Med → Low

Not fixed — **the risk model was overstated.** The config grants credentialed cross-origin access only
to requests whose `Origin` is literally `http://localhost:3000`, and a browser never sends that Origin
from any other page (`Origin` is not attacker-spoofable in a normal cross-site request). It is dead
config from the retired React dev server, not a live hole — unlike a wildcard or reflected-origin
config, which would be. **Still fix before Project 3**: native HTTP clients are not CORS-gated at all,
so this file protects nothing for them either way.

### L1 scope narrowed — and then closed the same day (`fc3afa7`)

The HTML `HujahsController`/`FlagsController` and `Api::V1::HujahsController#create` were all fixed
during Project 2. **`Api::V1::FlagsController#create` was missed** — its only touch since creation was
Slice 2's Pundit migration (`e53f945`), which added `authorize Flag` and left the bug. It still reads
`flag = current_user.flags.create(...)` then `if flag`, which is always truthy because `.create`
returns the object whether or not it persisted. So a malformed flag POST renders the unpersisted
record with 200 and reports success, and the `render json: flag.errors` branch is unreachable. No spec
covered the invalid path.

**Fixed in `fc3afa7`.** `.new` + `if flag.save`; the failure branch now returns
`:unprocessable_content` (grepped first — the codebase uses that status in 12 places and never uses
the Rails 8.1-deprecated `:unprocessable_entity`). The success response is unchanged: `.create` is
`.new` + `.save`, so the happy path renders the identical object from the identical line at 200 —
which matters because `Api::V1`'s response shape is a contract for native clients. A request spec now
asserts `Flag.count` is unchanged, the status is `:unprocessable_content`, and explicitly
`not_to have_http_status(:ok)` — the actual regression being guarded.

**Note on what makes a `Flag` invalid**, for whoever writes the next spec here: `Flag` declares no
validations of its own, but under `load_defaults 8.1` `belongs_to` is required, so a nonexistent
`hujah_id` fails with `hujah: ["must exist"]`. The `enum :subject` is **not** a usable invalidity
route — assigning an out-of-enum value raises `ArgumentError` (a 500), not a validation error.

**Still open, deliberately: `flag_params` is `params[:flag].permit(...)` with no `require`.** A POST
with no `flag` key raises `NoMethodError` on nil → **500**, before `authorize` is even reached. The
HTML sibling (`app/controllers/flags_controller.rb`) already uses `require`. Left alone because
changing it (`require` → 400, or `fetch(:flag, {})` → 422) alters the API's answer to a malformed
request, which is a contract decision for the native-client surface rather than a bug fix.

> **Decided 2026-08-19 — adopt `require`.** The owner confirmed no legacy native client hits
> `Api::V1` in production, so the contract can change as a **breaking** change with no serializer
> shim and no deprecation window. Implementation rides Slice 11. Still listed in the OPEN table at
> the top until it ships.

### Process gap — no CI — ✅ CLOSED in Slice 10 (2026-08-22)

**Was:** no `.github/workflows/` and no `bin/ci`; brakeman, bundler-audit and standardrb run by
hand per `CLAUDE.md`. Every gate green by convention, not enforcement — and the cost was
demonstrated, not theoretical: a wall-clock-dependent spec flake survived **three consecutive green
full-suite runs** before being caught by chance.

**Now:** `bin/ci` runs standardrb → brakeman → bundler-audit → `db:test:prepare` →
`tailwindcss:build` → RSpec, fail-fast, and is the definition of record.
`.github/workflows/ci.yml` calls it on every push to `master` and every pull request, so the two
cannot drift. Two jobs: `gates` (blocking) and `system` (headless-Chrome examples,
**`continue-on-error: true` for one week only** — the workflow carries a dated TODO to remove it,
because a permanently non-blocking check is worse than no check, it merely looks like one).

**Related, found while building it:** the suite could not pass on a clean checkout at all.
`app/assets/builds/tailwind.css` is gitignored and nothing regenerated it before RSpec, so the
layout's `stylesheet_link_tag "tailwind"` raised `Propshaft::MissingAssetError` and every
page-rendering system spec failed. Invisible locally, where `bin/dev` leaves the file behind.
`bin/ci` now builds it. Not a security finding, but exactly the class of thing only a
build-from-empty-tree catches.
