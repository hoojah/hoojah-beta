# Hoojah

![Ruby](https://img.shields.io/badge/Ruby-3.4.9-CC342D?logo=ruby&logoColor=white)
![Rails](https://img.shields.io/badge/Rails-8.1.3-D30001?logo=rubyonrails&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-18-4169E1?logo=postgresql&logoColor=white)
![Hotwire](https://img.shields.io/badge/Hotwire-Turbo%20%2B%20Stimulus-5CD8E5?logo=hotwire&logoColor=white)
![Tailwind CSS](https://img.shields.io/badge/Tailwind-CSS-38BDF8?logo=tailwindcss&logoColor=white)
![Devise](https://img.shields.io/badge/Devise-auth-E9573F)
![Pundit](https://img.shields.io/badge/Pundit-authorization-4B7BEC)
![Action Cable](https://img.shields.io/badge/Action%20Cable-Solid%20Cable-9B59B6)
![Tests](https://img.shields.io/badge/tests-273%20passing-brightgreen?logo=rspec&logoColor=white)
![Code style](https://img.shields.io/badge/code_style-standard-brightgreen)
![Deploy](https://img.shields.io/badge/deploy-Kamal-663399)

**Hoojah** is a social debate platform. Post a _hujah_ (a stance or claim), gather
**agree / neutral / disagree** votes, thread stance-tagged responses, and escalate any
argument into a one-on-one, turn-based **debate** — with real-time turns and a spectator
verdict. It's a **server-rendered Hotwire** app (Turbo + Stimulus over importmap, no Node)
on **Rails 8.1 / Ruby 3.4**, with **Devise** auth, **Pundit** authorization, **Action Cable**
(Solid Cable) for live debate turns, and a JSON `Api::V1` for native clients —
https://beta.hoojah.my

> **Status.** The "land everything" feature roadmap is **complete** — Social (follow /
> Following feed / @mentions), Debate (MVP + spectator verdict + real-time + timeout),
> Privacy + Analytics, Badges + Trending, Block, and Private accounts have all shipped.
> Suite: **273 examples / 0 failures / 2 pending** (request + headless-Chrome system specs);
> brakeman **0**; bundler-audit clean; StandardRB clean. Next up: **Project 3 — Hotwire
> Native**. See `docs/superpowers/HANDOVER.md` for full project status.

## Stack

- **Ruby** 3.4.9 (managed by **mise**, pinned via `.ruby-version` + `mise.toml`)
- **Rails** 8.1.3
- **PostgreSQL** (Postgres 18 locally; multi-database in production: primary + Solid Cache/Queue/Cable)
- **Hotwire** — Turbo + Stimulus over **importmap-rails** (no Node/Webpacker)
- **Propshaft** asset pipeline + **Tailwind CSS** (`tailwindcss-rails`)
- **Devise** 5.0 (`/login`, `/signup`, `/logout`, password reset)
- **Pundit** 2.5 authorization (per-action policies; app-wide `verify_authorized`)
- **Action Cable** over **Solid Cable** — real-time debate turns on an authorization-gated
  channel (`DebateChannel` re-checks the policy at subscribe time)
- **RSpec** + FactoryBot + Capybara/**Cuprite** (headless-Chrome system specs)
- **rack-attack** throttling, **invisible_captcha** honeypot, nonce-based CSP
- **Solid Queue / Solid Cache / Solid Cable** (production infrastructure; `bin/jobs` runs the worker)
- **Kamal** + Thruster (deploy; registry/host still placeholders)

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

> **Deploy note:** `app/assets/builds/tailwind.css` is gitignored and built by the
> `tailwindcss:build` task, which is hooked into `assets:precompile`. Any deploy must run
> `assets:precompile` so the compiled Tailwind bundle exists in production.

## Tests

```bash
# full suite (request + system specs) — 273 examples, 0 failures, 2 pending
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
- `docs/superpowers/ROADMAP-future-features.md` — the source feature roadmap.
- `docs/superpowers/UPGRADE-LOG.md` — the Rails 6.0 → 8.1 upgrade record (per-hop).
- `docs/superpowers/SECURITY-FINDINGS.md` — audit results and open security items.
- `docs/superpowers/specs/` and `docs/superpowers/plans/` — design + implementation plans.

## Project status

Project 2 (Hotwire) is **complete** — all 8 slices shipped (the full "land everything" roadmap).
Next up is **Project 3 — Hotwire Native**. The per-slice record, deferred backlog, and carried-forward
tech debt live in [`docs/superpowers/HANDOVER.md`](docs/superpowers/HANDOVER.md); open security items in
[`docs/superpowers/SECURITY-FINDINGS.md`](docs/superpowers/SECURITY-FINDINGS.md).
