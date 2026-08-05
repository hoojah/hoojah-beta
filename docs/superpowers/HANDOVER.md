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
