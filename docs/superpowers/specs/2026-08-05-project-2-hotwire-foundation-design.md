# Project 2 — Slice 1: Hotwire Foundation + Auth + Read/Vote Loop

_Design spec. Date: 2026-08-05. Status: **approved (brainstorming)** + **specialist-reviewed** (security,
Stimulus/Turbo, simplicity — feedback incorporated). Next: implementation plan (`writing-plans`)._

> **Review incorporation (v2):** Dropped Pundit for two plain `before_action` rules (simplicity + security
> converged: an app-wide `verify_authorized` would break/foot-gun the untouched `Api::V1::*` controllers).
> **Critical fix:** the IDOR remediation now targets the *actual* vulnerable endpoints
> (`Api::V1::VotesController#create`, `Api::V1::HujahsController#destroy`), not just the new HTML surface,
> with the characterization specs rewritten to assert secure behavior. Added Devise 5.0 config pinning,
> migration-safety steps (case-dup audit, concurrent index, validity check), an explicit CSP directive
> table + Drift nonce, a `Hujah#cast_vote` rich-model method, a collapsed `format_body` helper, a shared
> `dom_id(hujah, :vote_bars)` scheme, and a Stimulus-conventions section.

## Context

`hoojah-beta` is a Rails **8.1.3.1 / Ruby 3.4.9** app (Project 1 upgrade complete, merged `93a3ff2`).
It currently serves a **React 16 SPA** (`app/javascript/**`) backed by a JSON API (`Api::V1::*`) and a
hand-rolled session `SessionsController`. Project 2 replaces the SPA with **server-rendered Hotwire**
(Turbo + Stimulus) and retires the Webpacker/shakapacker + React + Node toolchain in favour of
**importmap + Propshaft**.

See `docs/superpowers/HANDOVER.md` for full project state and `docs/superpowers/SECURITY-FINDINGS.md`
for the pre-existing vulnerabilities this slice begins to remediate.

Project 2 is delivered in **slices**; this spec is **Slice 1** — the walking skeleton that proves the
full pattern end-to-end (foundation + auth + the core read/vote loop). Slice 2+ (compose form, profile,
notifications, flags) get their own specs.

## Goals (Slice 1)

1. Delete the React SPA + Node/Webpacker/shakapacker build; stand up importmap + Propshaft + Tailwind +
   Turbo + Stimulus.
2. Replace hand-rolled auth with **Devise** (no forced password reset for existing users).
3. Rebuild the two core screens server-side, faithful to today's look: **Hujah index feed** and
   **single Hujah** (vote bars + threaded child responses + response filter).
4. **Voting** works via Turbo Streams, authenticated.
5. Fold in the security fixes that live on this surface (CSRF, votes/hujah-destroy IDOR, login leak,
   mass-assignment, legacy `VotesController`).
6. Establish the test harness (request + JS system specs) and dev tooling (linter, mail preview).

## Non-goals (deferred to Slice 2+)

- Compose/new-Hujah form (incl. "respond to a hujah" flow), user profile page, notifications index,
  flag modal, social-share menu polish.
- Notifications IDOR fix (lives with the notifications UI in Slice 2).
- Removing the JSON API — it **stays** for programmatic/native clients (Project 3), and inherits the
  same auth fixes on shared endpoints.
- Pulling image hosting in-house (ActiveStorage) — Cloudinary stays as a JS-widget URL store.

## Locked decisions (from brainstorming)

| Decision | Choice |
|---|---|
| Slicing | Walking skeleton first (this spec) |
| Security | Fold fixes for this surface into Slice 1 |
| CSS | **Tailwind** (`tailwindcss-rails`), **faithful port** of current look |
| Auth | **Devise** (current line `~> 5.0`) |
| Third-party kept | Cloudinary uploads, Drift chat, social share (as plain links) |
| Icons | **Lucide only** (`lucide-rails`) — no custom SVG partials |
| Voting UI | **Turbo Streams** (server is source of truth) + light Stimulus for button feedback |

## Architecture

### 1. Asset pipeline

**Remove:** `shakapacker` gem + `config/webpacker.yml` + `app/javascript/packs` + `package.json` +
Node engines + `sass-rails`; the `app/javascript` React tree; the shakapacker CVE ignore
(`GHSA-96qw-h329-v5rg`) from `.bundler-audit.yml`.

**Add:** `importmap-rails`, `propshaft`, `tailwindcss-rails`, `turbo-rails`, `stimulus-rails`.

`application.html.erb` swaps `stylesheet_pack_tag`/`javascript_pack_tag` for
`stylesheet_link_tag "tailwind"` + `javascript_importmap_tags`. Carry over the Cloudinary and Drift
`<script>` tags. Tailwind theme tokens encode the agree/neutral/disagree colour system and the
card/vote-bar styles ported from the current SCSS.

### 2. Auth — Devise

**Migration safety (no forced reset):**
- **Pre-migration audit (blocking):** run `SELECT lower(email), count(*) FROM users GROUP BY lower(email)
  HAVING count(*) > 1` and resolve any case-duplicate emails **before** adding the unique index; adopt
  **downcase-before-save** email normalization so the DB index (case-sensitive) and Devise's
  case-insensitive uniqueness agree.
- Rename `password_digest` → `encrypted_password` (metadata-only on Postgres; both bcrypt `$2a$…`, cost
  embedded → existing passwords validate unchanged).
- Add `reset_password_token` (+ unique index), `reset_password_sent_at`, `remember_created_at`.
- Add a **unique index on `email`** (default `""`) — `disable_ddl_transaction!` +
  `algorithm: :concurrently` (enforced by `strong_migrations`), with a **post-migration index-validity
  check** (guard against a silent `INVALID` index) and a staging dry-run + tested down-migration (a bad
  rollback on this table is a lockout risk).

**Model:** drop `has_secure_password`; add
`devise :database_authenticatable, :registerable, :recoverable, :rememberable, :validatable`.
(`:confirmable`/`:lockable` deferred — would require confirming the existing user base + extra columns.)
Reconcile validations: Devise owns email + password; keep `username` presence/uniqueness. Move
`photo: User.random_photo` into an `after_create` callback.

**Devise 5.0 config (pin explicitly — do NOT accept generator defaults blindly):**
- `config.pepper` **stays unset** (a default pepper stub would silently invalidate every existing hash).
- `config.stretches = 12` to match `has_secure_password`'s bcrypt cost so `$2a$12$…` hashes round-trip.
- `config.paranoid = true` (password-reset/enumeration must not reveal whether an email is registered —
  same leak class as the C1 finding).
- `Devise.password_length = 8..128` — **closes deferred finding M6** (no minimum password length).
- Mailer `config.action_mailer.default_url_options = { host: … }` per env (reset links won't render
  otherwise); dev preview via `letter_opener`.

**Routes/controllers:** `devise_for :users` with friendly path names preserving **`/login`, `/logout`,
`/signup`** URLs + `/users/password` for reset. Delete `SessionsController`, `UsersController#create`,
and the `/login` `/logout` `/logged_in` routes + `resources :users, only: :create`. Extra signup fields
(`username`, `full_name`) via `configure_permitted_parameters`.

**Ripple:** `current_user` / `user_signed_in?` / `authenticate_user!` now come from Devise → delete the
hand-rolled `ApplicationController` helpers. Sweep `Api::V1::*` + `HujahSerializer` params that call the
old `logged_in?`/`current_user` (still session-backed via Warden). The `/logged_in` endpoint that leaked
`password_digest` is **removed**.

### 3. Endpoint hardening (the IDOR fix — plain `before_action`, no Pundit)

Slice 1 has exactly **two** authorization rules, so it uses explicit controller filters rather than a
policy framework (Pundit deferred to Slice 2, where flags/notifications multiply the rules — an app-wide
`verify_authorized` net now would 500 every untouched `Api::V1::*` controller and invite a blanket skip
that silently re-opens these IDORs). Each rule is guarded by a request spec asserting the secure
behavior. **Both the new HTML controllers and the shared `Api::V1::*` endpoints that own the actual
vulnerabilities get fixed** — not just the HTML surface:

- **Votes IDOR (C2):** `Api::V1::VotesController#create` **and** the HTML `VotesController#create` get
  `before_action :authenticate_user!`; the voter is **`current_user`**, `params[:user_id]` is ignored/
  removed. Rewrite `spec/requests/api/v1/votes_spec.rb` to assert votes record under the session user,
  not a supplied `user_id`.
- **Hujah-destroy IDOR (C4):** `Api::V1::HujahsController#destroy` **and** HTML destroy get
  `authenticate_user!` + an owner-only `before_action` (`@hujah.user == current_user`, else 403/redirect).
  Rewrite the `hujahs_spec.rb` destroy block to assert unauthenticated/non-owner deletes are rejected.
- **CSRF (H1):** delete the app-wide `skip_before_action :verify_authenticity_token`. `ApplicationController`
  keeps Rails' default `protect_from_forgery with: :exception` for HTML/Turbo. `Api::V1::BaseController`
  (introduce it) uses **`protect_from_forgery with: :null_session`** — a forged cross-site cookie POST
  lands in a null session and, combined with `authenticate_user!`, cannot act as the user. (Documented as
  the interim strategy; token auth revisited in Project 3.)
- **`:id` mass-assignment (H6):** fix at `app/controllers/api/v1/users_controller.rb#user_params` — drop
  `:id` (and the meaningless `:user` key) from the permit list; add a regression spec.
- Delete the legacy top-level `VotesController` + `resources :votes` route (C5).
- **Light throttle** the authenticated vote-create endpoint via `rack-attack` (counter/notification spam).

### 4. Screens

Server-rendered controllers back the HTML UI (the `Api::V1::*` controllers remain for JSON clients):

- **`HujahsController#index`** (`root`) — feed of top-level hujahs as Tailwind cards; logged-out users
  also see the "pinned/intro" block. **Paginated** with `pagy` (`pagy_countless`): a plain
  stream-append container `<div id="hujah-feed">` (**no `turbo_frame_tag` per card/page** — unnecessary
  nesting), a "load more" `button_to` that `turbo_stream.append`s the next page's cards **and
  `turbo_stream.replace`s itself** (advancing `page`, or removing on last page). Double-submit is
  guarded by Turbo's auto-disable + a test asserting no duplicate cards.
- **`HujahsController#show`** — full card, vote bars + percentages, threaded child responses, the
  all/agree/neutral/disagree response **filter**, vote + response counts. Resolved via
  `friendly.find` (see §6).

Body text (plain debate text — no rich editor exists; the old slug code strips tags defensively) is
rendered by a single helper `format_body(text) = auto_link(simple_format(text), html: { target: "_blank",
rel: "noopener" })`. `simple_format` already sanitizes to a safe subset and handles paragraphs/newlines;
`auto_link` (`rails_autolink`) linkifies URLs without double-linking — the safe replacement for React
`dangerouslySetInnerHTML` + `react-linkify`. **No custom `sanitize` allowlist** (that would double-sanitize
for no gain) — *verify at implementation* that no stored body relies on richer HTML; if one does, add a
scoped `sanitize` step then.

### 5. Voting (Turbo Streams — Approach A)

Three `button_to` forms (one per stance) post to an authenticated `VotesController#create`
(`before_action :authenticate_user!` — no hand-rolled redirect). The controller is **thin**: it calls a
**rich-model method `Hujah#cast_vote(by: current_user, choice:)`** that encapsulates the existing
semantics — **vote stored as an array** (`vote: [n]`, current = `.vote.last`), **denormalized counters**
(`agree_count`/`neutral_count`/`disagree_count`), and the new-vote notification — then responds with a
**`turbo_stream.replace`** of that hujah's `_vote_bars` partial (bars, %, "voted" state, counts). Server
is the source of truth; the SPA's triplicated client-side counter math is **deleted**, not ported.

**Instant feedback without JS first:** rely on CSS `:active`/`:disabled` + Turbo's native in-flight
form state (`aria-busy`, `data-turbo-submits-with`), which auto-disables the submitter until the stream
returns. Only add a `vote_controller` if a real click-latency check shows it's needed; if added, it is
**strictly presentational** — no `values` holding counts, no `fetch`, no count/bar math; it only toggles
a class / `aria-pressed` on its own button (the next stream render is authoritative). See
"Stimulus conventions".

**Turbo-Stream target id scheme (pin now, shared across index/show/votes):** the vote partial is keyed
by `dom_id(hujah, :vote_bars)` → `vote_bars_hujah_<id>`, identical in the feed card and the show page, so
`VotesController` can `turbo_stream.replace` it regardless of which page the card is on. The index/show
vote widgets may be different partials but **must share this id scheme**.

### 6. Slugs — friendly_id (with history)

Replace the abandonware `slug` gem (dead since 2019; produces **non-unique** slugs) with `friendly_id`
`:slugged` + `:history`. Adds the `friendly_id_slugs` table so **old shared/social links survive a body
edit**. `slug_candidates` truncates the parameterized body (first N words + disambiguating token) →
collision-safe, length-controlled. Controller lookups move `find_by_slug` → `friendly.find`. Data
migration backfills slugs for existing hujahs.

### 7. Icons — Lucide only

`lucide-rails` provides one `lucide_icon` helper. Mapping for the current icon set (no custom SVGs):

| App icon | Lucide | | App icon | Lucide |
|---|---|---|---|---|
| agree | `thumbs-up` | | notification | `bell` |
| disagree | `thumbs-down` | | edit | `square-pen` |
| neutral | `minus` | | more_actions | `ellipsis` |
| hujah | `message-circle` | | flag | `flag` |
| votes | `bar-chart-3` | | crown | `crown` |
| home | `house` | | percent | `percent` |
| views | `eye` | | globe | `globe` |
| back | `arrow-left` | | map_pin | `map-pin` |
| share | `share-2` | | trash | `trash-2` |
| announcement | `megaphone` | | | |

### 8. Security hardening (config, no gems)

- CSRF: handled in §3 (delete app-wide skip; `:exception` for HTML, `:null_session` for `Api::V1`).
- `rack-attack` (backed by existing `solid_cache`): throttle `POST /login`, `/signup`, `/users/password`
  per-IP **and** per-email; plus a light throttle on authenticated vote-create (§3).
- `invisible_captcha`: honeypot on the signup form.
- `force_ssl = true` (HSTS), `permissions_policy.rb` reviewed, headers via Rails 8 `default_headers` —
  **not** the `secure_headers` gem.

**CSP — explicit directive list (not a placeholder).** The page carries two non-self third parties;
`unsafe-inline` on `script-src` is **forbidden** (it would cancel the stored-XSS defense from
`format_body`). Use `config/initializers/content_security_policy.rb` with a **nonce generator**
(`content_security_policy_nonce_generator`) and put `nonce: true` on Drift's inline bootstrap `<script>`:

| Directive | Sources |
|---|---|
| `default-src` | `:self` |
| `script-src` | `:self` + nonce; `widget.cloudinary.com`; Drift script host |
| `style-src` | `:self` (+ nonce if any inline style) |
| `img-src` | `:self` `data:` `https://res.cloudinary.com` |
| `connect-src` | `:self`; `api.cloudinary.com`; Drift websocket/API host |
| `frame-src` | `widget.cloudinary.com`; Drift chat frame host |

Exact Drift hosts confirmed against its current install snippet at implementation.

## Gem manifest

**Add (default group):** `rack-attack ~> 6.8`, `invisible_captcha ~> 0.8`, `pagy ~> 43.6`,
`friendly_id ~> 5.7`, `lucide-rails`, `rails_autolink`, `local_time ~> 3.0`, `devise ~> 5.0`,
`importmap-rails`, `propshaft`, `tailwindcss-rails`, `turbo-rails`, `stimulus-rails`.

**Add (dev/test):** `capybara`, `cuprite`, `strong_migrations`, `standard`, `letter_opener` (dev).

**Remove:** `shakapacker`, `sass-rails`, `slug`; the shakapacker CVE ignore in `.bundler-audit.yml`.

**Dropped from an earlier draft:** `pundit` — for two authorization rules, plain `before_action` filters
(§3) are leaner and avoid the app-wide `verify_authorized` footgun; **Pundit deferred to Slice 2** when
flags/notifications multiply the rules.

**Deferred to Slice 2+:** `pundit`, `prosopite` + `pg_query` (N+1, arrives with the serializer feed),
`shoulda-matchers`, `faker`, `annotaterb`, `devise-pwned_password`, `view_component`, `turbo_power`,
`cloudinary` (ruby) / ActiveStorage, `recaptcha`.

_No gem needed:_ HTML sanitization (`simple_format`, §4), CSRF (delete the skip, §3), security
headers/CSP (Rails config, §8). Chose `rails_autolink` over `rinku` (pure Ruby, no native build, speed
irrelevant at scale).

## Component boundaries

- `HujahsController` (index/show) — read surface; thin, delegates rendering to partials.
- `VotesController#create` (HTML) + `Api::V1::VotesController#create` (JSON) — `authenticate_user!`, thin;
  call `Hujah#cast_vote`, then render Turbo-Stream / JSON respectively.
- `Hujah` model — **`cast_vote(by:, choice:)`** (array-append + counter denormalization + notification),
  `friendly_id` slug, `current_user_vote`. Body formatting is a view helper (`format_body`), not model.
- Owner/auth guards — plain `before_action` in the controllers (no policy objects in Slice 1).
- Partials — `_hujah_card`, `_vote_bars` (Turbo-Stream target, `dom_id(hujah, :vote_bars)`),
  `_response_filter`, `_hujah_header` (avatar/handle/share).
- Stimulus — `response_filter_controller` (client-side tab filter); `vote_controller` **only if** a
  latency check proves CSS/Turbo-native feedback insufficient; plus `local-time`.

Plain ERB partials, not `view_component`, for a faithful port (extract to components later only if a
card is reused across 3+ contexts with logic).

### Stimulus conventions (Slice 1)

Guardrails so parallel tasks don't improvise (per betterstimulus.com):

- **Naming:** `snake_case_controller.js` ↔ `data-controller="kebab-case"`. Explicitly:
  `response_filter_controller.js` ↔ `response-filter`; `vote_controller.js` ↔ `vote`.
- **All actions via `data-action` in ERB** — no manual `addEventListener`/`connect()`-installed listeners.
- **`vote_controller` contract (if it exists at all):** no `static values` holding counts, no `fetch`, no
  reading/writing `*_count` — the `button_to` form submits, the stream re-render is authoritative. Acts
  only on `this.element` (its own button); never reaches into the vote-bar DOM.
- **`response_filter_controller` contract:** `static targets = ["tab", "item"]`, `static classes =
  ["hidden"]`, `static values = { active: String }`. `filter(e)` sets `this.activeValue = e.params.filter`;
  a single `activeValueChanged` toggles the `hidden` **attribute** (not `visibility`/`opacity`) on items
  (matched via `data-response-filter-vote` on each child) and updates `aria-pressed` on tabs. Tabs wrapped
  in `role="group"` with `aria-label`. Decide + note: empty-state message when a filter matches zero, and
  whether filter state resets to "all" on `turbo:before-cache` back-nav.
- **No Outlets in Slice 1** — the two controllers are independent; reserve Outlets/events for Slice 2.
- **`local-time`:** pin via importmap; verify it re-localizes `<time>` tags on `turbo:load` **and** after
  Turbo-Stream appends/replaces (system-spec assertion), not just full-page load.

## Testing

- **Rewrite the characterization specs that lock insecure behavior** (they must now assert *secure*
  behavior, not merely stay green): `spec/requests/api/v1/votes_spec.rb` (votes record under the session
  user, `user_id` param ignored), the `hujahs_spec.rb` destroy block (unauthenticated/non-owner delete
  rejected), and a new regression spec for the `users` `:id` mass-assignment fix. Migrate the
  `login_as` helper → Warden/Devise `sign_in`.
- Keep the remaining JSON API request specs green.
- **Request specs** for the HTML flows + the Turbo-Stream vote endpoint (assert `turbo_stream` response +
  counter deltas via `cast_vote`), plus the load-more append and **no-duplicate-card on double-submit**.
- **System specs** (`capybara` + `cuprite`, headless Chrome): vote happy-path; response filter must assert
  `aria-pressed` + `hidden`-attribute state (not just visible text); `local-time` localizes after a
  Turbo-Stream append.
- Post-migration: a test/dry-run confirming existing users still authenticate and the unique email index
  is `VALID`.
- TDD per task (superpowers). `strong_migrations` gates the Devise migration in dev/test.

## Execution model

After this spec passes specialist review and `writing-plans` produces the implementation plan:
**Fable as architect** (per the `fable-orchestration` skill) decomposes the plan and delegates
token-heavy execution to **Opus subagents** via `subagent-driven-development`, using the
**`better-stimulus`** agent for Stimulus controllers, with a review checkpoint per task and
verification-before-completion throughout. Build/test commands per `HANDOVER.md`
(`mise exec ruby@3.4.9`, `source .mise-build-env.sh`, `RAILS_ENV=test RUBYOPT='-W0' … rspec`,
`bin/rails db:test:prepare`).

## Named tech-debt (deferred, not lost)

- **Collapse the vote model:** `Vote#vote` array → scalar integer; replace the denormalized
  `*_count` columns with derived counts / `counter_cache`. Kept as-is in Slice 1 for a
  characterization-locked faithful port (and the counters make the Turbo re-render trivial). Do it in a
  dedicated later slice with its own data migration + spec rewrite.
- **Pundit** — adopt when Slice 2's flags/notifications multiply authorization rules.
- **Cloudinary URL trust (matches deferred M7):** the profile-photo update path (Slice 2) stores a
  client-supplied URL verbatim — add server-side host allowlist (`res.cloudinary.com`) when that path
  lands.

## Risks / open items

- **Devise 5.0.x** is newer than prior familiarity — verify API + generator output at install; pin
  `~> 5.0`, and pin the config in §2 rather than trusting generator defaults.
- `lucide-rails` (heyvito) — verify Propshaft/Rails 8.1 compatibility at install; the icon mapping is
  provisional pending exact Lucide icon-name availability.
- `local_time` — verify importmap compatibility (ESM/CJS shim); fallback is vendoring via
  `importmap pin --download`, or a server-side `time_ago_in_words` if it fights importmap.
- Devise column rename on a populated table — behind `strong_migrations`, `disable_ddl_transaction!` for
  the concurrent index, case-dup-email audit first, verify logins + index validity after.
- Turbo-Stream vote re-render must preserve the array-vote + denormalized-counter semantics exactly
  (rewritten characterization specs guard this).
- **Still-open, out-of-scope for this slice** (tracked in `SECURITY-FINDINGS.md`): `rack-cors` hardcoded
  `localhost:3000` + `credentials: true` (M1 — confirm the `ENV["FRONTEND_ORIGIN"]` follow-up lands
  before Project 3 widens origins under the Devise cookie session); `config.require_master_key` left
  commented (L4). Keep `rack-cors` for JSON/native clients until Project 3 decides.

## Doc references

| File | What |
|---|---|
| `docs/superpowers/HANDOVER.md` | Project state + build/run quirks |
| `docs/superpowers/SECURITY-FINDINGS.md` | Pre-existing vuln triage |
| `docs/superpowers/UPGRADE-LOG.md` | Project 1 per-hop record |
