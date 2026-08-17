# Hoojah — Feature Reference

A screen-by-screen reference for the server-rendered Hotwire UI. For a quick orientation see
the [README](../README.md); for full project status / history and the deferred backlog see
[`docs/superpowers/HANDOVER.md`](superpowers/HANDOVER.md).

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
- **Trending** — a cached, public `/trending` (`Hujah.trending`, HN-decayed activity) rendered
  both as a standalone page and as a lazy `lg` sidebar frame on the feed.
- **Badges** — 4 event-driven achievements (`first_hoojah`, `first_argument`, `first_follower`,
  `first_debate`) — a code registry (`Badge::REGISTRY`) + a `user_badges` awards table, awarded
  idempotently off after-commit callbacks, surfaced as a `badge_earned` notification and public
  profile chips.

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

## Privacy — secret ballot

The `new_vote` notification carries **no voter identity** (Slice 5): `Hujah#cast_vote` does not
record `subject_user_id`, so the API notifications serializer never hands a hoojah owner the
username of who voted (choice was already secret). A one-off backfill nulled the id on existing
rows. Known follow-up: per-hoojah counts are still public on hoojah cards at any N (tracked).

## Project status & roadmap

The "land everything" roadmap is **complete** — Social (follow / Following feed / @mentions),
Debate (MVP + spectator verdict + real-time + timeout), Privacy + Analytics, Badges + Trending,
Block, and Private accounts have all shipped across Project 2 Slices 1–8. Next up is **Project 3
— Hotwire Native**.

- Full per-slice record + the deferred backlog: [`docs/superpowers/HANDOVER.md`](superpowers/HANDOVER.md)
- The source feature roadmap: [`docs/superpowers/ROADMAP-future-features.md`](superpowers/ROADMAP-future-features.md)
- Open security items: [`docs/superpowers/SECURITY-FINDINGS.md`](superpowers/SECURITY-FINDINGS.md)
