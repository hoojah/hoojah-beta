# Hoojah

![Ruby](https://img.shields.io/badge/Ruby-3.4.9-CC342D?logo=ruby&logoColor=white)
![Rails](https://img.shields.io/badge/Rails-8.1.3-D30001?logo=rubyonrails&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-18-4169E1?logo=postgresql&logoColor=white)
![Hotwire](https://img.shields.io/badge/Hotwire-Turbo%20%2B%20Stimulus-5CD8E5?logo=hotwire&logoColor=white)
![Tailwind CSS](https://img.shields.io/badge/Tailwind-CSS-38BDF8?logo=tailwindcss&logoColor=white)
![Devise](https://img.shields.io/badge/Devise-auth-E9573F)
![Pundit](https://img.shields.io/badge/Pundit-authorization-4B7BEC)
![Action Cable](https://img.shields.io/badge/Action%20Cable-Solid%20Cable-9B59B6)
![Tests](https://img.shields.io/badge/tests-536%20passing-brightgreen?logo=rspec&logoColor=white)
![Code style](https://img.shields.io/badge/code_style-standard-brightgreen)
![Deploy](https://img.shields.io/badge/deploy-Coolify%20%2B%20Docker-8b5cf6)

**Hoojah** is a social debate platform. Post a _hujah_ (a stance or claim), gather
**agree / neutral / disagree** votes, thread stance-tagged responses, and escalate any
argument into a one-on-one, turn-based **debate** — with real-time turns and a spectator
verdict. It's a **server-rendered Hotwire** app (Turbo + Stimulus over importmap, no Node)
on **Rails 8.1 / Ruby 3.4**, with **Devise** auth, **Pundit** authorization, **Action Cable**
(Solid Cable) for live debate turns, and a JSON `Api::V1` for native clients —
https://beta.hoojah.my

> **Status.** The "land everything" feature roadmap is **complete** — Social (follow /
> Following feed / @mentions), Debate (MVP + spectator verdict + real-time + timeout +
> named Opening/Counter/Response/Closing phases), Privacy + Analytics, Badges + Trending,
> Block, and Private accounts have all shipped, and the **Hoojah Design System** is adopted
> across all eight view families. Suite: **536 examples / 0 failures / 0 pending** (request +
> headless-Chrome system specs); brakeman **0**; bundler-audit clean; StandardRB clean.
> CI enforces every gate on each PR (Slice 10), and the app is deployable to Coolify
> (Slice 10b). Next up: **Slice 11 — API hardening**, then the stance-domain unification
> and the secret-ballot decision. **Project 3 (Hotwire Native) is deliberately fourth** —
> everything that changes the API contract or hardens its surface goes first, because
> native clients bake contracts in. See
> [`docs/superpowers/plans/2026-08-17-post-slice-9-roadmap.md`](docs/superpowers/plans/2026-08-17-post-slice-9-roadmap.md)
> for the sequence and `docs/superpowers/HANDOVER.md` for full project status.

## Stack

- **Ruby** 3.4.9 (managed by **mise**, pinned via `.ruby-version` + `mise.toml`)
- **Rails** 8.1.3
- **PostgreSQL** (Postgres 18; one database in production — Solid Cache/Queue/Cable share it)
- **Hotwire** — Turbo + Stimulus over **importmap-rails** (no Node/Webpacker)
- **Propshaft** asset pipeline + **Tailwind CSS** (`tailwindcss-rails`)
- **Devise** 5.0 (`/login`, `/signup`, `/logout`, password reset)
- **Pundit** 2.5 authorization (per-action policies; app-wide `verify_authorized`)
- **Action Cable** over **Solid Cable** — real-time debate turns on an authorization-gated
  channel (`DebateChannel` re-checks the policy at subscribe time)
- **RSpec** + FactoryBot + Capybara/**Cuprite** (headless-Chrome system specs)
- **rack-attack** throttling, **invisible_captcha** honeypot, nonce-based CSP
- **Solid Queue / Solid Cache / Solid Cable** (production infrastructure; `bin/jobs` runs the worker)
- **Coolify** + Docker (deploy) — multi-stage `Dockerfile`, Puma behind **Thruster**; see [Deploy](#deploy)

## Features

Feed & voting, compose/respond, profiles, notifications, flag, share, follow + Following feed,
@mentions, **debate** (real-time turns + spectator verdict + timeout auto-conclude), an owner-only
analytics dashboard, trending, badges, block, and private accounts — all server-rendered with
Turbo/Stimulus. Full screen-by-screen reference, including the secret-ballot privacy model:
**[`docs/FEATURES.md`](docs/FEATURES.md)**.

## Setup

```bash
mise install                 # installs Ruby 3.4.9 from .ruby-version / mise.toml
bundle install
bin/rails db:prepare         # dev
bin/rails db:test:prepare    # test (schema only, no seeds — do NOT use db:prepare, it seeds)
```

> **mise-managed Ruby.** All commands below assume mise has activated Ruby 3.4.9 for the
> shell. If it hasn't (or on CI), prefix any Ruby/Rails/bundle command with
> `mise exec ruby@3.4.9 --` — e.g. `mise exec ruby@3.4.9 -- bin/rails db:prepare`.

> **Apple Silicon / modern clang note:** `.mise-build-env.sh` provides a `clang` shim
> (in `.cc-shim/`) that relaxes a few `-Werror` flags so native gems compile. If a
> `bundle install` fails to build a C extension, run `source .mise-build-env.sh` first.

## Running

```bash
bin/dev                      # Puma + Tailwind watcher (Procfile.dev) — the dev command
bin/jobs                     # Solid Queue worker (production-style)
```

`bin/dev` runs both the web server and the Tailwind `css:watch` process; `bin/rails server`
alone will not rebuild CSS on change.

## Deploy

The target is **Coolify**, which builds this repo's `Dockerfile` and fronts the container
with its own TLS-terminating reverse proxy. There is no Kamal, no Capistrano and no
Procfile — the image's `CMD` is the whole story.

```bash
docker build --platform linux/amd64 -t hoojah .
docker run -p 3000:3000 \
  -e RAILS_MASTER_KEY=... -e DATABASE_URL=... -e APP_HOST=beta.hoojah.my hoojah
```

**Build for `linux/amd64`.** `Gemfile.lock`'s `PLATFORMS` lists `x86_64-linux` but not
`aarch64-linux`, so an ARM64 Linux build cannot resolve the platform-specific gems. If
Coolify ever runs on an ARM host, commit `bundle lock --add-platform aarch64-linux`.

### Environment

Copy [`.env.example`](.env.example) into Coolify's environment editor. Required:
`RAILS_MASTER_KEY`, `DATABASE_URL`, `APP_HOST`. `RAILS_ENV`, `RAILS_LOG_TO_STDOUT` and
`RAILS_SERVE_STATIC_FILES` are already baked into the image.

`APP_HOST` feeds `config.hosts <<`, so a wrong value answers **every** request with 403.
`/up` is deliberately excluded from that check — the platform's health probe reaches the
container on its internal address, never on `APP_HOST`, and without the exclusion the
deploy never goes healthy.

### ⚠️ `config/master.key` does not exist

It is gitignored and was never carried over from the original Rails 6 app, while
`config/credentials.yml.enc` **is** committed — and is unreadable without the key. Before
the first deploy the key must be **recovered or regenerated**, and regenerating discards
the current encrypted credentials. This is an owner action; no code change substitutes
for it. (The image still *builds* without it — `assets:precompile` runs under
`SECRET_KEY_BASE_DUMMY=1`.)

Once `RAILS_MASTER_KEY` is set in Coolify and a deploy has succeeded, uncomment
`config.require_master_key = true` in `config/environments/production.rb` — that is the
last step of the first deploy, and it closes ledger item **L4**. It is left commented
until then because enabling it now would break local and CI boots, which have no key.

### First-deploy database bootstrap

One-time, from a shell on the container (or a Coolify pre-deploy command):

```bash
bin/rails db:schema:load:primary   # app schema from db/schema.rb
bin/rails db:migrate               # Solid Cache/Queue/Cable tables
```

**Do not run `bin/rails db:prepare`.** It runs `db/seeds.rb`, which creates
login-capable accounts sharing a hardcoded password; `db/seeds.rb` now aborts in
production, which would leave the bootstrap half-finished. The two commands above are
the seed-free equivalent and are safe to re-run.

Solid Cache, Solid Queue and Solid Cable all live in the **primary** database (see the
comment at the top of `config/database.yml`). Their tables come from `db/cache_migrate`,
`db/queue_migrate` and `db/cable_migrate` rather than from the `db/*_schema.rb` dumps,
because `db:prepare` skips a schema dump once `schema_migrations` exists in the target
database — which, sharing one database, it always does.

### The background worker is a second service

`config/recurring.yml` schedules `ConcludeStaleDebatesJob` daily at 3am, so **without a
worker, debates idle past 7 days are never auto-concluded**. Deploy a second Coolify
service from the same image with the command overridden to:

```bash
bundle exec bin/jobs
```

### Assets

`app/assets/builds/tailwind.css` is gitignored and nothing rebuilds it at boot. The
`Dockerfile` runs `assets:precompile` (which `tailwindcss-rails` hooks
`tailwindcss:build` into) in the build stage — if that step is ever removed, or if the
build falls back to Nixpacks autodetection, the app deploys with **no CSS at all** while
appearing to succeed.

### One-time logout on the first deploy

Rails 7.0 changed the session key generator (SHA1 → SHA256), so any sessions predating
this deploy are invalidated. Users are signed out once. Expected, not a bug.

## Tests

```bash
# full suite (request + system specs) — 536 examples, 0 failures, 0 pending
RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec

# skip the headless-Chrome system specs for a faster inner loop
RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec --exclude-pattern "spec/system/**/*"
```

System specs (`spec/system/**`, tagged `js: true`) drive a real headless Chrome via
Cuprite; set `CUPRITE_CHROME_PATH` to override the browser binary on CI.

Quality gates (all green): **StandardRB** (`bundle exec standardrb`), **brakeman**
(`bundle exec brakeman -q`), and **bundler-audit** (`bundle exec bundler-audit check --update`).

## Documentation

- **[`docs/FEATURES.md`](docs/FEATURES.md)** — screen-by-screen feature reference + privacy model.
- `docs/superpowers/HANDOVER.md` — full project status/history + the deferred backlog (read first).
- `docs/design-system/` — the design system, extracted from this codebase. Start at its `readme.md`,
  then `MIRROR-NOTES.md`.
- `docs/superpowers/ROADMAP-future-features.md` — the source feature roadmap.
- `docs/superpowers/UPGRADE-LOG.md` — the Rails 6.0 → 8.1 upgrade record (per-hop).
- `docs/superpowers/SECURITY-FINDINGS.md` — audit results and open security items.
- `docs/superpowers/specs/` and `docs/superpowers/plans/` — design + implementation plans.

## Project status

Project 2 (Hotwire) is **complete** — all 8 slices shipped (the full "land everything" roadmap),
plus Slice 9 (design system + structured debate phases), Slice 10 (CI) and Slice 10b (Coolify deploy
readiness).

The sequence from here is in
[`docs/superpowers/plans/2026-08-17-post-slice-9-roadmap.md`](docs/superpowers/plans/2026-08-17-post-slice-9-roadmap.md):
**11 — API hardening**, **12 — stance-domain unification** (array→scalar then enum, one slice),
**13 — the secret-ballot decision** (option C, decided), then **Project 3 — Hotwire Native**. Project 3
is fourth on purpose: the items the HANDOVER has flagged as "before Project 3" since Slice 1 are still
open, and the API's stance wire format is about to change — native clients bake contracts in, so
everything that changes or hardens the contract goes first.

The per-slice record, deferred backlog, and carried-forward tech debt live in
[`docs/superpowers/HANDOVER.md`](docs/superpowers/HANDOVER.md); open security items in
[`docs/superpowers/SECURITY-FINDINGS.md`](docs/superpowers/SECURITY-FINDINGS.md).
