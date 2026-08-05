# Hoojah

Server-rendered Hotwire app (feed, single-hujah, voting, compose/respond, profiles,
notifications, flagging, social share, follow + @mentions) with a Devise auth layer,
Pundit authorization, and a JSON `Api::V1` API for native clients — https://beta.hoojah.my

## Stack

- **Ruby** 3.4.9 (pinned via `.ruby-version` + `mise.toml`)
- **Rails** 8.1
- **PostgreSQL** (multi-database in production: primary + Solid Cache/Queue/Cable)
- **Hotwire** — Turbo + Stimulus over **importmap-rails** (no Node/Webpacker)
- **Propshaft** asset pipeline + **Tailwind CSS** (`tailwindcss-rails`)
- **Devise** ~> 5.0 (`/login`, `/signup`, `/logout`, password reset)
- **Pundit** ~> 2.5 authorization (per-action policies; app-wide `verify_authorized`)
- **RSpec** + FactoryBot + Capybara/Cuprite (headless-Chrome system specs)
- **rack-attack** throttling, **invisible_captcha** honeypot, nonce-based CSP
- **Solid Queue / Solid Cache / Solid Cable** (production infrastructure)
- **Kamal** + Thruster (deploy; registry/host still placeholders)

## Screens (Hotwire)

- **Feed** + **single-hujah** with per-stance **voting** and a client-side response filter.
- **Compose / respond** — `/hoojah/new` and `/hoojah/:slug/respond` (stance-tagged replies;
  a reply notifies the parent owner).
- **Profile** — public view + owner edit at `/u/:username`, a native `<dialog>` edit modal
  with a Cloudinary photo widget (host-validated URLs).
- **Notifications** — `/notifications`, mark-read + Turbo-Stream delete.
- **Flag** — a `<dialog>` reason picker on the single-hujah page (spam / abusive / irrelevant).
- **Share** — server-rendered social intent links (WhatsApp / X / Telegram / Reddit /
  Facebook / Email) with a progressively-enhanced Web Share button.
- **Follow** — follow / unfollow any public profile from `/u/:username`; the button and
  follower count refresh via Turbo Stream (idempotent, rack-attack throttled). Public
  followers / following lists at `/u/:username/followers` and `/u/:username/following`.
- **Following feed** — a **Following** tab on the feed shows your own + followed users'
  hoojahs (`Hujah#timeline_for`); an anonymous `?filter=following` request falls back to
  the global feed.
- **@mentions** — `@handle` in a hoojah body renders an injection-safe link to
  `/u/:handle` (tokenized before `simple_format`/`auto_link` so an `@` inside an email or
  URL is never linkified) and notifies each mentioned user once on create.
- **Debate** — a one-on-one, turn-based debate escalated from an argument. Challenge the
  argument's author (native `<dialog>` stance picker) → they accept/decline → alternating
  turns (each notifies the other) → either party concludes → a public, read-only transcript
  at `/debates/:slug`. Debates surface in a **Debates** lens on the hoojah page. Turn
  authorization is turn-scoped (`DebateTurnPolicy` — only the current-turn user may post);
  active debates are participants-only, concluded ones public. **Real-time** turns broadcast
  live over an **authorized `DebateChannel`** (the app's first Action Cable use — the socket
  re-checks `DebatePolicy#show?` at subscribe time, not just the page). A concluded debate gets
  a **spectator verdict** ("who argued better?" — challenger / opponent / draw; one immutable
  vote per visible spectator, compute-on-read tally). An idle active debate (no turn for 7 days)
  is **auto-concluded** by a daily `ConcludeStaleDebatesJob` (Solid Queue recurring). rack-attack
  throttled.
- **Dashboard** — an owner-only `/dashboard` showing the signed-in user's own aggregate
  stats (votes received, arguments received) and a per-hoojah vote distribution, computed
  on read from the denormalized `hujahs` counters with **zero new tables**. Owner-only by
  construction (always `current_user`, no username in the URL, no `AnalyticsPolicy`); the
  query never joins `votes`→`users`, and a per-hoojah split below 5 votes is suppressed
  ("fewer than 5 votes"). See the **Privacy** note below.

- **Block** — a bidirectional block from any profile (`/u/:username`; Block ↔ Unblock via
  Turbo Stream; a blocked-users list at `/blocks`). Block is enforced at the **Pundit policy
  layer**: a blocked pair can no longer reply to, follow, or challenge each other (so no such
  content and no such notification is ever created), and their content is filtered from each
  other's feeds, reply threads, trending, and `@mention` notifications (via one memoized
  `User#hidden_user_ids` helper). Blocking also removes any existing follow in both directions.
  Filters are **signed-in only** (anonymous is unfiltered); votes stay anonymous and are
  deliberately not filtered. rack-attack throttled.

- **Private accounts** — a user can flip their profile to **private** (profile-edit toggle).
  Following a private user becomes a **request → approve** flow (3-state Follow / Requested /
  Following button; accept or decline from the `follow_request` notification card). A private
  author's content is visible only to **accepted followers** (+ themselves) through **one gate**
  (`User#visible_to?` / `Hujah#visible_to?`), enforced on **every** content surface: the global
  feed and trending exclude them (unconditionally, anonymous too; trending's cache is busted on
  the privacy flip); the profile shows a **gated header** (avatar / name / @handle / counts, no
  hoojah list); the hoojah show page, reply thread (`@children`), follower/following lists,
  concluded **debate transcripts**, **notification bodies**, and the **`Api::V1`** hoojah/user
  read endpoints all gate a private author; and you can't reply to a private parent you can't
  see. Flipping back to public **auto-accepts** all pending requests.

Modals use native `<dialog>` plus a custom `close_dialog` Turbo Stream action.

**Privacy — secret ballot.** The `new_vote` notification carries **no voter identity** (Slice 5):
`Hujah#cast_vote` does not record `subject_user_id`, so the API notifications serializer never hands a
hoojah owner the username of who voted (choice was already secret). A one-off backfill nulled the id on
existing rows. Known follow-up: per-hoojah counts are still public on hoojah cards at any N (tracked).

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

- **Project 2 Slice 2 — done:** compose/respond, profiles, notifications, flag, share, and
  Pundit adoption all shipped (see HANDOVER for the deferred list).
- **Project 2 Slice 3 — done:** follow/unfollow, Following feed, @mentions (see HANDOVER).
- **Project 2 Slice 4 — done:** one-on-one Debate MVP (challenge → accept/decline →
  alternating turns → conclude → public transcript; Debates lens). Deferred: debate
  Increments 2a verdict / 2b real-time / 3 timeout (see HANDOVER).
- **Project 2 Slice 5 — done:** vote-privacy hardening (`new_vote` voter-id leak closed +
  backfill) and an owner-only `/dashboard` (aggregate stats, k=5 suppression, zero new tables).
  Deferred: analytics trends/ranking; the tracked public per-hoojah count suppression (2a); see HANDOVER.
- **Project 2 Slice 6 — done:** 4 event-driven achievement badges (`first_hoojah`, `first_argument`,
  `first_follower`, `first_debate`) — a code registry (`Badge::REGISTRY`) + a `user_badges` awards table,
  idempotent inline awards off existing after-commit callbacks, a `badge_earned` notification, and public
  profile chips; plus a cached, public **`/trending`** (`Hujah.trending`, HN-decayed activity) rendered as
  a lazy `lg` sidebar frame on the feed and a standalone page. Deferred: vote-milestone + `debate_won`
  badges, recurring-job trending, trending block/private exclusion (Slice 7); see HANDOVER.
- **Project 2 Slice 7 — done:** bidirectional **Block** (`blocks` table + `User#hidden_user_ids`).
  Policy-layer interaction rejection (reply/follow/challenge → no content, no notification) +
  signed-in-only content filters (feeds, reply threads, trending, mentions) + reciprocal-follow
  removal. Deferred: mute + private accounts (Slice 7b — Block does not yet hide a blocked user's
  profile/show page or their appearance in third-party follower lists reached by direct URL);
  `Api::V1` block filters; see HANDOVER.
- **Project 2 Slice 7b — done:** **Private accounts** — `users.private` + `follows.status`
  (request → approve) + `User#visible_to?` gating every content surface (global feed + trending,
  gated profile, hoojah show, `@children`, follower/following lists, debate transcripts,
  notification bodies, `Api::V1` reads, reply-create) with a 3-state follow button and a
  private→public auto-accept. Deferred: the `/follow_requests` inbox page; full `Api::V1`
  visibility parity (serializer children/notifications); see HANDOVER.
- **Project 2 Slice 8 — done (program complete):** the three deferred **Debate increments** —
  spectator **verdict** (`debate_verdicts`, compute-on-read tally, visible-spectator-only, one
  immutable vote); **real-time** turns via an authorized `DebateChannel` (subscribe-time
  `DebatePolicy#show?` re-check; viewer-scoped composer/actions partials; id-dedup so the
  synchronous controller response and the async broadcast coexist); and **timeout auto-conclude**
  (`DebateTurn touch: true` + `conclude!(by: nil)` notifies both + a daily `ConcludeStaleDebatesJob`).
  This completes the "land everything" roadmap. Deferred: `debate_won` badge, changeable verdict,
  live tally for non-voters, two-session real-time test; see HANDOVER.
- **Project 3:** Hotwire Native (mobile).
- **Security:** remaining app-logic findings in `SECURITY-FINDINGS.md`.
