# Hoojah

Server-rendered Hotwire app (feed, single-hujah, voting) with a Devise auth layer and a
JSON `Api::V1` API for native clients — https://beta.hoojah.my

## Stack

- **Ruby** 3.4.9 (pinned via `.ruby-version` + `mise.toml`)
- **Rails** 8.1
- **PostgreSQL** (multi-database in production: primary + Solid Cache/Queue/Cable)
- **Hotwire** — Turbo + Stimulus over **importmap-rails** (no Node/Webpacker)
- **Propshaft** asset pipeline + **Tailwind CSS** (`tailwindcss-rails`)
- **Devise** ~> 5.0 (`/login`, `/signup`, `/logout`, password reset)
- **RSpec** + FactoryBot + Capybara/Cuprite (headless-Chrome system specs)
- **rack-attack** throttling, **invisible_captcha** honeypot, nonce-based CSP
- **Solid Queue / Solid Cache / Solid Cable** (production infrastructure)
- **Kamal** + Thruster (deploy; registry/host still placeholders)

## Setup

```bash
mise install                 # installs Ruby 3.4.9 from .ruby-version / mise.toml
bundle install
bin/rails db:prepare         # dev
bin/rails db:test:prepare    # test (schema only, no seeds)
```

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
RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec        # full suite (request + system specs)
```

System specs (`spec/system/**`, tagged `js: true`) drive a real headless Chrome via
Cuprite; set `CUPRITE_CHROME_PATH` to override the browser binary on CI.

Code style is enforced with **StandardRB** (`bundle exec standardrb`).

## Documentation

- `docs/superpowers/HANDOVER.md` — session handover + project status (read this first).
- `docs/superpowers/UPGRADE-LOG.md` — the Rails 6.0 → 8.1 upgrade record (per-hop).
- `docs/superpowers/SECURITY-FINDINGS.md` — audit results and open security items.
- `docs/superpowers/specs/` and `docs/superpowers/plans/` — design + implementation plans.

## Known follow-on work

- **Project 2 Slice 2:** compose/new-hujah form, user profile, notifications index, flag
  modal, social-share menu (see HANDOVER for the deferred list).
- **Project 3:** Hotwire Native (mobile).
- **Security:** remaining app-logic findings in `SECURITY-FINDINGS.md`.
