# Hoojah — Session Handover

_Last updated: 2026-08-05. Read this first when resuming._

## TL;DR

**Project 1 (Rails 6.0 → 8.1 upgrade + backend modernization) is DONE and merged to `master`.**
The app runs **Rails 8.1.3.1 on Ruby 3.4.9**, suite is **24 examples / 0 failures / 2 pending**,
boots in dev + test. Merge commit: `93a3ff2`. **Not pushed** — run `git push origin master` when ready
(remote is Bitbucket).

Next up: **Project 2 (React SPA → Hotwire)**, then **Project 3 (Hotwire Native)**. Neither started.

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
