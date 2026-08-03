# Hoojah

JSON API backend (session + bcrypt auth) for the Hoojah React SPA — https://beta.hoojah.my

## Stack

- **Ruby** 3.4.9 (pinned via `.ruby-version` + `mise.toml`)
- **Rails** 8.1
- **PostgreSQL** (multi-database in production: primary + Solid Cache/Queue/Cable)
- **RSpec** + FactoryBot
- **shakapacker** (React SPA bundler — see note below)
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
bin/rails server             # API + SPA shell
bin/jobs                     # Solid Queue worker (production-style)
```

## Tests

```bash
bundle exec rspec
```

The suite is a **characterization safety net** (request specs for every API endpoint +
auth) added during the Rails 6→8 upgrade. See `docs/superpowers/`.

## Documentation

- `docs/superpowers/UPGRADE-LOG.md` — the Rails 6.0 → 8.1 upgrade record (per-hop).
- `docs/superpowers/SECURITY-FINDINGS.md` — audit results; **open application-security items
  awaiting owner decision** (unauthenticated API endpoints, user-object leak on login, etc.).
- `docs/superpowers/specs/` and `docs/superpowers/plans/` — the upgrade design + plan.

## Known follow-on work

- **Project 2:** replace the React/Webpacker SPA with **Hotwire (Turbo + Stimulus)** on
  importmap + Propshaft; retire shakapacker (its JS build is currently inactive).
- **Project 3:** Hotwire Native (mobile).
- **Security:** address the app-logic findings in `SECURITY-FINDINGS.md` (they change the
  API contract, so were intentionally left for a dedicated pass).
