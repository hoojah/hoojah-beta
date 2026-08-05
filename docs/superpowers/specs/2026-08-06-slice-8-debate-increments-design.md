# Slice 8: Debate Increments — Verdict, Real-time, Timeout

_Design spec. Date: 2026-08-06. Status: **design (from Slice-4 debate sketch's deferred increments)**,
pending specialist review + plan. **Final slice** of the "land everything" program (roadmap:
`docs/superpowers/ROADMAP-future-features.md`)._

## Context

Slice 4 shipped the debate MVP (challenge→accept/decline→turns→conclude→public transcript, `Debate` +
`DebateTurn`, in-model state machine, request-driven Turbo, `dom_id(@debate, :transcript)`/`(:composer)`
pinned). This slice adds the three deferred increments:

- **2a — Spectator verdict:** on a **concluded** debate, logged-in **non-participants** vote "who argued
  better?" (challenger / opponent / draw). Reuses the denormalized vote-counter idiom.
- **2b — Real-time turns:** turns/status broadcast live via Turbo Streams (Action Cable) — the app's first
  broadcasting. No new infra (cable: dev `async`, test `test`, prod `solid_cable`).
- **3 — Timeout auto-conclude:** a Solid Queue **recurring** job concludes debates left idle past a
  threshold.

## Part 2a — Spectator verdict

### Model

- `add_column :debates`, denormalized (mirrors hoojah counters): `challenger_votes_count`,
  `opponent_votes_count`, `draw_votes_count` (integer, default 0, null false).
- `debate_verdicts (debate_id FK, user_id FK, choice integer)`, unique `[debate_id, user_id]`, index
  `[debate_id]`. `choice` enum `{ challenger: 0, opponent: 1, draw: 2 }`. **One vote per spectator,
  immutable** for MVP (find_or_create; changeable is a later nicety).
- `Debate#cast_verdict(by:, choice:)` (mirrors `cast_vote` shape, simpler — scalar): guard `concluded?`
  + `!participant?(by)`; `debate_verdicts.create!(user: by, choice:)` (rescue `RecordNotUnique` → no-op);
  `increment!` the matching count. Wrapped in a transaction. Notifications: none (low value; the debate is
  concluded).

### Controller / auth / UI

- Route `post "/debates/:slug/verdicts", to: "debate_verdicts#create"`.
- `DebateVerdictsController#create` (`authenticate_user!`): `authorize @debate.debate_verdicts.new(user:
  current_user), :create?` → **`DebateVerdictPolicy#create? = user.present? && record.debate.concluded? &&
  !record.debate.participant?(user)`** (spectators only, concluded only — parallels the C1 turn-policy
  discipline: authorize a *verdict* instance so Pundit resolves `DebateVerdictPolicy`, not `DebatePolicy`).
  Call `@debate.cast_verdict`, respond with `turbo_stream.replace dom_id(@debate, :verdict)`.
- The concluded debate show page renders a `_verdict` partial: three `button_to` buttons (challenger /
  opponent / draw) for eligible spectators, and a **result bar** (counts + %) — reuse the `_vote_bars`
  Tailwind width-% idiom. Participants + anonymous see the tally read-only. Respects Slice-7b visibility
  (the debate show is already gated by `DebatePolicy#show?`).
- rack-attack: a `debate_verdicts/user` throttle (like votes).
- **`debate_won` badge deferred** — with live spectator tallies the "winner" is dynamic; a badge here is
  awkward. Keep `first_debate` (Slice 6); revisit `debate_won` if verdicts finalize.

## Part 2b — Real-time turns (Turbo broadcasting)

- **`debates/show`** adds `<%= turbo_stream_from @debate %>` (subscribes the viewer to the debate's stream).
- **`Debate` model** broadcasts on the same `dom_id`s pinned in Slice 4 (so this drops in without touching
  the request-driven views): in `post_turn`, after creating the turn, `broadcast_append_to @debate, target:
  ActionView::RecordIdentifier.dom_id(self, :transcript), partial: "debates/debate_turn", locals: { turn: }`
  **and** `broadcast_replace_to @debate, target: dom_id(self, :composer), partial: "debates/turn_composer",
  locals: { debate: self }`. `accept!`/`conclude!` broadcast a `_debate_status`/`_debate_actions` replace.
  (The controller's own `turbo_stream` response still renders for the acting user — the broadcast updates
  the *other* participant's open page. To avoid a double-append for the actor, prefer: the controller
  returns `head :no_content`/a no-op and lets the broadcast update BOTH, OR keeps its response and the
  broadcast targets only the opponent — **decision for the plan**: simplest correct is to let the model
  broadcast to the stream and have the controller action return the broadcast-driven update only, avoiding
  duplicate DOM. Resolve so the actor doesn't see the turn twice.)
- **Composer visibility:** the `_turn_composer` already renders per `current_turn_user`; after a broadcast
  swap, each viewer's composer reflects whose turn it is (the partial is rendered per-broadcast, so it must
  compute "is it *this viewer's* turn" — but a broadcast renders once, not per-subscriber. **Constraint:**
  a broadcast partial can't be viewer-specific. So broadcast the *transcript append* (viewer-agnostic) and
  a *neutral* composer state ("waiting…"/"your turn" derived from `current_turn_user` shown generically),
  and let a full turn-state refresh happen on the acting user's own request response. Keep the composer's
  enable/disable driven by the server-rendered `current_turn_user == current_user` on page load + the
  actor's own response; the broadcast just appends the turn + a generic "it's <user>'s turn" status. Pin
  this in the plan.)
- Tests: `have_broadcasted_to(debate)` on `post_turn`; a system test with two sessions is out of scope
  (cuprite single-session) — assert the broadcast fires + the subscription tag renders.

## Part 3 — Timeout auto-conclude

- `ConcludeStaleDebatesJob < ApplicationJob`: `Debate.active.where("updated_at < ?", 7.days.ago).find_each
  { |d| d.conclude!(by: nil) }` — **`conclude!` gains a nil-`by` "system" path** (currently guards
  `participant?(by)`; allow a system conclude: `def conclude!(by: nil); return false unless active? &&
  (by.nil? || participant?(by)); ...`). A system conclude notifies **both** participants `debate_concluded`.
- `config/recurring.yml` (production): `conclude_stale_debates: { class: "ConcludeStaleDebatesJob",
  schedule: "every day at 3am" }`. Dev has no job worker by default (auto-timeout won't run in dev — note
  in HANDOVER); prod runs it via Solid Queue recurring.
- Test: `perform_now` concludes a debate whose `updated_at` is > 7 days old, leaves a fresh one active,
  notifies both.

## Component boundaries

- Models: `DebateVerdict`; `Debate#cast_verdict` + denormalized counts + broadcast calls +
  `conclude!(by: nil)` system path.
- Controllers: `DebateVerdictsController`; `DebatePolicy`/`DebateVerdictPolicy`.
- Job: `ConcludeStaleDebatesJob` + `recurring.yml`.
- Views: `_verdict` (buttons + result bar) on `debates/show`; `turbo_stream_from @debate`; broadcast
  partials reuse `_debate_turn`/`_turn_composer`/`_debate_status`.
- Notification enum: unchanged (no new categories — verdict has none; system-conclude reuses
  `debate_concluded`). rack-attack: `debate_verdicts/user`.

## Testing

- **Verdict:** `cast_verdict` — spectator only + concluded only (a participant → policy 403; an active
  debate → 403); one immutable vote per spectator (second → no-op, counts unchanged); counts increment
  correctly; the result bar renders; anonymous sees read-only tally.
- **Real-time:** `post_turn`/`accept!`/`conclude!` `have_broadcasted_to(debate)`; `debates/show` renders the
  `turbo_stream_from` subscription; the actor doesn't get a duplicated turn (per the resolved decision).
- **Timeout:** `ConcludeStaleDebatesJob.perform_now` concludes an idle (>7d) active debate + notifies both;
  leaves a recent one active; a concluded/declined one untouched.
- Full suite green; brakeman 0; bundler-audit clean; StandardRB clean.

## Risks / open questions

- **Broadcast duplicate-DOM** (the actor's request response + the broadcast both touching the transcript) —
  resolve in the plan (let the broadcast own the transcript append; controller returns a minimal/no-op, or
  broadcast excludes the actor). This is the one real design decision in 2b.
- **Broadcast partials are viewer-agnostic** — the composer's per-viewer turn state can't be broadcast
  per-subscriber; broadcast the transcript + a generic status, keep per-viewer composer enable/disable on
  page-load/own-response. Pinned above.
- **Verdict integrity:** participants can't vote (policy); one vote per spectator (unique index);
  immutable for MVP. `cast_verdict` is transactional (counter + record atomic).
- **Timeout `conclude!(by: nil)`** must not weaken the participant guard for the normal path — only nil is
  the system path; a non-participant non-nil `by` still fails.
- **Dev auto-timeout** doesn't run without a job worker — documented; prod recurring covers it.

## Deferred

`debate_won` badge; changeable verdict; two-session real-time system test; Project 3 (Hotwire Native — the
debate/verdict URLs are deep-link-friendly for it).

## Program completion

With this slice, the "land everything" roadmap is complete: Social, Debate (MVP + verdict + real-time +
timeout), Privacy+Analytics, Badges+Trending, Block, Private accounts all shipped. Remaining program items
are the explicitly-deferred niceties above + **Project 3 (Hotwire Native)**.
