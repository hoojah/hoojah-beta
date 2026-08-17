# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Hoojah** (https://beta.hoojah.my) — a Malaysian social debate platform. A user posts a *hujah*
(claim), others cast **agree / neutral / disagree** votes and thread stance-tagged responses, and any
argument can be escalated into a one-on-one turn-based **debate** with real-time turns and a
spectator verdict.

Rails 8.1 / Ruby 3.4, **server-rendered Hotwire** (Turbo + Stimulus over importmap — no Node,
no build step for JS), Devise auth, Pundit authorization, Action Cable over Solid Cable, plus a
legacy-shaped `Api::V1` JSON API kept for native clients.

Read `docs/superpowers/HANDOVER.md` **first** on any resumed work — it carries per-slice status, the
deferred backlog, and open decisions. `docs/FEATURES.md` is the screen-by-screen reference.

## Commands

Ruby is **mise-managed**. If mise hasn't activated the shell, prefix every command with
`mise exec ruby@3.4.9 --`.

```bash
bundle install
bin/rails db:prepare                # dev DB (runs seeds)
bin/rails db:test:prepare           # test DB — schema only. Do NOT use db:prepare here; it seeds.

bin/dev                             # THE dev command: Puma + tailwindcss:watch (Procfile.dev)
bin/jobs                            # Solid Queue worker

# Full suite (request + headless-Chrome system specs)
RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec
# Faster inner loop — skip system specs
RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec --exclude-pattern "spec/system/**/*"
# One file / one example
RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/debate_spec.rb:42

# Quality gates — all must stay green
bundle exec standardrb              # add --fix to autocorrect
bundle exec brakeman -q
bundle exec bundler-audit check --update
```

`bin/rails server` alone does **not** rebuild CSS — always use `bin/dev`.
If `bundle install` fails building a C extension on Apple Silicon, `source .mise-build-env.sh` first
(it installs a `clang` shim in `.cc-shim/` that relaxes `-Werror`).

System specs live in `spec/system/**`, are tagged `js: true`, and drive real headless Chrome via
Cuprite (`CUPRITE_CHROME_PATH` overrides the binary).

**All agents share one Postgres test database.** Concurrent full-suite runs collide with
`PG::ObjectInUse`. Run one suite at a time; use targeted specs when working in parallel.

## Architecture

### Request pipeline

`ApplicationController` includes Pundit and sets `after_action :verify_authorized, unless:
:devise_controller?`. **Every non-Devise action must call `authorize` or `skip_authorization`
exactly once** or it raises. Policies live in `app/policies/` (one per resource, per-action).
`Pundit::NotAuthorizedError` → HTML redirect back with an alert, everything else `403`.

Pagination is `pagy(:countless, …)` via `Pagy::Method` (pagy ~> 43.6 — not the classic
`Pagy::Backend`).

### Two surfaces, two CSRF strategies

- **HTML/Turbo** (`app/controllers/*.rb`) — CSRF **on**. `button_to`/forms carry the token.
- **`Api::V1`** (`app/controllers/api/v1/`) — `Api::V1::BaseController` uses
  `protect_from_forgery with: :null_session`, JSON via `jsonapi-serializer` (`app/serializers/`).

Consequence: a new HTML write action belongs on a **main route, not under `Api::V1`**, so CSRF stays
enforced. The routes file states this at several call sites.

### Routing

`config/routes.rb` is entirely **hand-written paths — no `resources`**, and every route carries a
comment explaining why it exists in that shape. Records are addressed by **friendly_id slug**
(`Hujah`, `Debate`) or by **`:username`** (`/u/:username`), never by id. Notable shapes:

- Devise mounted at `path: ""` → `/login`, `/signup`, `/logout`, and `registrations#create` at `POST /`.
- Own-resource surfaces take no username in the URL (`/notifications`, `/dashboard`, `/blocks`) —
  they are owner-only by construction via `policy_scope`.
- `debates#extend_rounds` (not `extend` — that would shadow `Object#extend`).

### Domain model

`User` — Devise + the follow graph (`following`/`followers` are **accepted-only**; private accounts
create `pending` follows) and the block graph (`hidden_user_ids` is bidirectional). Private-flag
changes bust the trending cache.

`Hujah` — self-referential (`parent_id`) claim/response tree. Vote tallies are denormalized counter
columns (`agree_count`/`neutral_count`/`disagree_count`) maintained inside `cast_vote`'s
transaction; `votes.vote` is a legacy **array column appended per cast** (latest element is the
current stance — collapsing it to a scalar is a deferred item). `after_create_commit` hooks fire
reply notifications, `@mention` notifications, and badge awards. `Hujah.trending` is a
Hacker-News-gravity score computed on read, cached 15 min as **ids only**.

`Debate` — `challenger` vs `opponent`, `enum status: pending/active/concluded/declined`, turns
alternating by position. Round, phase (opening/counter/response/closing), and whose turn it is are
**all derived, never stored** — read the comments on `current_phase`, `final_position`, and
`extendable_by?` before touching them; `extend_rounds!` takes `with_lock` to protect the phase
*label* invariant against a concurrent `post_turn`. `ConcludeStaleDebatesJob` auto-concludes debates
idle > 7 days.

Privacy is a real constraint, not incidental: votes are a **secret ballot** — the `new_vote`
notification deliberately carries no `subject_user_id`, because recording it let the owner
de-anonymize voters through the serializer.

### Real-time

`DebateChannel < Turbo::StreamsChannel` re-checks `DebatePolicy#show?` at subscribe time, so the
Cable gate mirrors the HTTP gate: an active debate streams to participants only, a concluded one to
anyone who may read the transcript. Fails closed on a deleted record.

### Views and the design system

`docs/design-system/` is a mirror **extracted from this codebase** — it is the spec, and work
against it is codification, not redesign. Start at its `readme.md`, then `MIRROR-NOTES.md`.

Shared primitives:

- `app/views/ui/_card`, `_avatar`, `_divider`, `_empty_state`, `_menu`
- `DesignSystemHelper` — `ds_button_classes`, `ds_card_classes`, `ds_avatar_classes`,
  `ds_menu_item_classes`, `ds_initials`, `ds_debate_state_color`

`ui/_card` is a **layout partial**: `render layout: "ui/card", locals: {...} do … end`.
`render partial: "ui/card" do … end` silently renders nil and raises a confusing error.

House style, briefly: white **square-cornered** cards with `shadow` and `#f3f4f6` hairlines; pill
buttons with a 2px coloured border and `active:scale-95`; an 8px stance-coloured left border on
compact cards; stance trio agree `#fcaf45` / **neutral `#e1306c` (pink, never grey)** / disagree
`#833ab4`; primary `#415de6`; Lucide icons via `lucide-rails`; system font stack, no webfonts, no
dark mode, essentially no animation.

## Tailwind gotchas — these have each caused a real bug here

1. **Tailwind v4 scans the whole repo as text**, but **not uniformly — the extractors differ by file
   type**, which Slice 9 established by experiment:
   - **ERB `<%# … %>` comments ARE scanned.** A concrete class name in ERB prose compiles a real
     rule. So does one in JS, YAML, SVG or Markdown.
   - **Ruby `#` comments are NOT.** In `.rb` files it is specifically *string literals* that are
     extracted — bare words and symbols are not, which is why `variant: :outline` never shipped a
     rule despite appearing a dozen times.
   - **The input CSS file is not scanned as a source at all**, so its own comments are safe.

   So the "write `bg-<stance>`, never a concrete class" discipline is load-bearing **in ERB**, and
   optional in Ruby comments. `docs/`, `spec/` and `app/assets/images` are `@source not`-excluded;
   `README.md`, `CLAUDE.md` and `.yarn/releases/*.js` are **not**, and do contribute rules.

   Two traps: **`@source not` paths resolve relative to the working directory, not the CSS file** —
   build from the repo root or `docs/`/`spec/` are silently re-admitted. And **a comment describing a
   class you just deleted will resurrect it**.

   Cheap check: md5 the built bundle before and after a comment-only edit — it must not change. Pair
   it with a **positive control** (append a comment naming an unused class, confirm the hash *moves*),
   or a broken harness is indistinguishable from a clean result.
2. **Interpolated classes must be safelisted.** Anything built by string interpolation
   (`bg-#{stance}`, `border-#{read_state}`, every `ds_button_classes` tone) needs an
   `@source inline(...)` entry, and the safelist covers the **bare** utility only —
   `peer-checked:bg-agree` is a separate entry.
3. **Same-family utilities resolve by bundle order, not call order.** `.px-4` precedes `.px-5`. So a
   call-site override of a baked-in padding/width is a coin flip — hence `ui/_menu`'s `width:` is
   required, and `ui/_card`'s `padded:` must never be combined with padding in `class:`.
4. **An uncoloured `border-b` inherits `currentColor`** — inside an `<a>` that means an indigo rule,
   because `@layer base` links are `--fg-link`.
5. `app/assets/builds/tailwind.css` is **gitignored** and nothing rebuilds it before RSpec. Any spec
   asserting on compiled CSS must call `TailwindBuild.once!` (see `spec/support/tailwind_build.rb`)
   and query with `TailwindBuild.emitted?`. Every deploy must run `assets:precompile`, which hooks
   `tailwindcss:build`.

## Testing conventions

RSpec + FactoryBot (`spec/factories/`), transactional fixtures, `FactoryBot::Syntax::Methods` mixed
in, spec type inferred from directory. Support helpers in `spec/support/` (`auth_helpers`,
`capybara`, `devise`, `record_identifier`, `tailwind_build`).

Known trap: `have_broadcasted_to(...).with { }` runs its block against **every** payload on the
stream — it asserts "all broadcasts were this one", not "this one was broadcast". Two specs here
only passed because their stream carried a single payload.

## Working conventions

- **StandardRB** formats Ruby. `db/schema.rb`, `db/migrate/**`, and `bin/**` are excluded.
- `strong_migrations` is active — migrations against populated tables need the concurrent/batched
  treatment (see the notes in `HANDOVER.md` about the Devise backfill).
- Commit subjects follow `Slice N Task X.Y: <what>` for roadmap work, plain imperative otherwise.
  **No Claude/Anthropic branding in commit messages** (no `Co-Authored-By`, no "Generated with").
- **Never `git commit --amend` unless HEAD is verifiably your own commit** — an agent amending
  another's cost a history repair on this branch.
- The prevailing method here is: implementer → independent review → batched fixes → re-verify.
  Comments in this codebase carry the *why* at unusual density; when changing such code, keep the
  reasoning current rather than deleting it.
- Open security items live in `docs/superpowers/SECURITY-FINDINGS.md`; the deferred backlog and
  per-slice history in `docs/superpowers/HANDOVER.md`; plans and specs under
  `docs/superpowers/plans/` and `docs/superpowers/specs/`.
