# Slice 8: Debate Increments — Verdict, Real-time, Timeout

_Design spec. Date: 2026-08-06. Status: **design + specialist-reviewed** (security, better-stimulus,
simplicity — folded, v2). **Final slice** of the "land everything" program._

> **Review incorporation (v2).** **2a:** compute-on-read (drop the 3 denormalized counters) — this also
> **dissolves the Critical transaction-poison bug** (no counter increment → `cast_verdict` is a single
> `create!` with a method-level rescue), and add the **Slice-7b visibility gate** to the verdict policy
> (must-fix — write endpoint bypassed the read gate). **2b ships** (better-stimulus resolved the DOM/composer
> issues) **with subscribe-time channel authorization** (security High — the signed stream token is a
> durable unrevocable credential; the app's first Action Cable use must gate the socket). **3:** fix the
> **`conclude!(by: nil)` crash** (`other(nil).id`) → notify both; **`touch: true`** on `DebateTurn` so the
> idle clock tracks turns. Drops: denormalized verdict columns, redundant `[debate_id]` index.

## Context

Slice 4 shipped the debate MVP. This adds the three deferred increments. Reuse the pinned
`dom_id(@debate, :transcript)`/`(:composer)`, the `_vote_bars` width-% idiom, and the C1 instance-authorize
discipline.

## Part 2a — Spectator verdict (concluded debates)

### Model — compute-on-read (no denormalized counters)

- `debate_verdicts (debate_id FK, user_id FK, choice integer)`, unique `[debate_id, user_id]` **DB index**
  (no standalone `[debate_id]` index — the composite's leftmost prefix covers it). `choice` enum
  `{ challenger: 0, opponent: 1, draw: 2 }`. `DebateVerdict belongs_to :debate, :user`.
- **Tally is compute-on-read** (renders on one page, not a list): `debate.verdict_tally =
  debate_verdicts.group(:choice).count`. **No columns on `debates`, no counter sync.**
- **`Debate#cast_verdict(by:, choice:)`** — a single insert; **no transaction, method-level rescue**
  (this is why dropping the counters matters — there is nothing to poison):
  ```ruby
  def cast_verdict(by:, choice:)
    return false unless concluded? && !participant?(by) && DebateVerdict.choices.key?(choice.to_s)
    debate_verdicts.create!(user: by, choice: choice)
    true
  rescue ActiveRecord::RecordNotUnique
    false                       # already voted — idempotent no-op
  end
  ```
  Immutable one-vote per spectator (changeable is deferred). No verdict notifications.

### Controller / auth / UI

- Route `post "/debates/:slug/verdicts", to: "debate_verdicts#create"`.
- `DebateVerdictsController#create` (`authenticate_user!`; **`rescue_from Pundit::NotAuthorizedError, with:
  :render_forbidden`** for a hard 403, matching the sibling debate controllers): `verdict_params =
  params.permit(:choice)`; `authorize @debate.debate_verdicts.new(user: current_user, choice:
  verdict_params[:choice]), :create?` (a **DebateVerdict instance** so Pundit resolves the right policy —
  C1 pattern); `@debate.cast_verdict(...)` (invalid choice → `head :unprocessable_content`);
  `turbo_stream.replace dom_id(@debate, :verdict)`.
- **`DebateVerdictPolicy#create?`** (spectators only, concluded only, **AND visible per Slice 7b**):
  ```ruby
  def create?
    user.present? && record.debate.concluded? && !record.debate.participant?(user) &&
      DebatePolicy.new(user, record.debate).show?   # inherits concluded+both-visible gate
  end
  ```
  (Closes the must-fix gap: without the `show?` clause a blocked/non-follower could POST a verdict on a
  debate they can't read.)
- **UI:** `_verdict` partial on the concluded debate show: three `button_to` (challenger/opponent/draw) for
  an eligible spectator + a result bar (from `verdict_tally`, `_vote_bars` width-% idiom). Participants +
  anonymous + already-voted see the tally read-only.
- rack-attack: `throttle("debate_verdicts/user", limit: 10, period: 1.minute)` keyed on the warden user for
  `POST /debates/:slug/verdicts`.
- **`debate_won` badge deferred** (dynamic tally → no coherent finalization).

## Part 2b — Real-time turns (Turbo broadcasting) — with channel authorization

### Subscribe-time authorization (the app's first Action Cable — security must-fix)

The signed Turbo stream token is durable/unrevocable, so gate the socket, not just the page:
```ruby
# app/channels/application_cable/connection.rb
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user
    def connect
      self.current_user = env["warden"]&.user(scope: :user) || reject_unauthorized_connection
    end
  end
end

# app/channels/debate_channel.rb — a Turbo stream channel that re-checks DebatePolicy#show?
class DebateChannel < Turbo::StreamsChannel
  def subscribed
    debate = GlobalID::Locator.locate(verified_stream_name_from_params&.split(":")&.first) rescue nil
    # (implementer: derive the Debate from the verified stream name; reject unless authorized)
    if debate && DebatePolicy.new(current_user, debate).show?
      super
    else
      reject
    end
  end
end
```
The debate `show` view only renders the subscription for an authorized viewer (already gated by
`authorize @debate`), and the channel independently re-verifies `show?` at subscribe time.

### Streams + broadcasts

- **`debates/show`:** `<%= turbo_stream_from @debate, channel: "DebateChannel" %>` (transcript + status —
  viewer-agnostic) AND `<%= turbo_stream_from [@debate, current_user], channel: "DebateChannel" if
  @debate.participant?(current_user) %>` (this viewer's composer + actions — user-signed).
- **Duplicate-DOM is a non-issue** (better-stimulus): `_debate_turn` already wraps each row in
  `id="<%= dom_id(debate_turn) %>"`, so Turbo's `removeDuplicateTargetChildren` dedups the controller
  response + the broadcast append by id. **Keep the Slice-4 controller `turbo_stream` response unchanged**;
  broadcast unconditionally (incl. the actor).
- **Viewer-scoped composer/actions:** split `_debate_status` → `_debate_status` (state label / declined
  note — viewer-agnostic) + new **`_debate_actions`** (Accept/Decline/Conclude — viewer-scoped). Both
  `_turn_composer` and `_debate_actions` take an explicit **`viewer:` local**
  (`local_assigns.fetch(:viewer) { current_user }`) — NOT the implicit `current_user` (undefined in a
  broadcast render context; the current draft would blank the opponent's buttons — a bug better-stimulus
  caught).
- **Broadcasts — after `with_lock`, `_later` variants (Solid Queue):** `post_turn` →
  `broadcast_append_later_to @debate, target: dom_id(self, :transcript), partial: "debates/debate_turn"` +
  per-participant `broadcast_replace_later_to [self, p], target: dom_id(self, :composer), partial:
  "debates/turn_composer", locals: { debate: self, viewer: p }` for `p in [challenger, opponent]`.
  `accept!`/`conclude!` broadcast `_debate_status` to `@debate` + `_debate_actions` per-participant.
- **No new Stimulus controller** — the existing `debate_composer` autofocus reconnects on broadcast-replace
  for free.
- Tests: `have_broadcasted_to` on `post_turn`; the subscription tag renders; channel rejects a
  non-participant/unauthorized subscribe. (Two-session visual real-time is out of cuprite scope.)

## Part 3 — Timeout auto-conclude

- **`touch: true`** on `DebateTurn belongs_to :debate` (so `debates.updated_at` tracks the last **turn**,
  not just the last status change — else the job concludes actively-argued debates).
- **`conclude!(by: nil)` fixed** (the spec-v1 crash: `other(nil).id`):
  ```ruby
  def conclude!(by: nil)
    return false unless active? && (by.nil? || participant?(by))
    update!(status: :concluded)
    if by.nil? then notify(challenger, :debate_concluded); notify(opponent, :debate_concluded)
    else notify(other(by), :debate_concluded) end
    UserBadge.award(challenger, "first_debate"); UserBadge.award(opponent, "first_debate")
    true
  end
  ```
  (`conclude` controller action always passes `current_user` behind `authenticate_user!` → the nil/system
  path is only reachable from the job.)
- `ConcludeStaleDebatesJob < ApplicationJob`: `Debate.active.where("updated_at < ?", 7.days.ago).find_each
  { |d| d.conclude!(by: nil) }`. `config/recurring.yml` (production): `conclude_stale_debates: { class:
  "ConcludeStaleDebatesJob", schedule: "every day at 3am" }`. Dev has no worker (documented — prod runs it).
- Test: `perform_now` concludes an idle (>7d, via a stale `updated_at`) active debate + notifies both; a
  recent one stays active; concluded/declined untouched.

## Component boundaries

- Models: `DebateVerdict`; `Debate#cast_verdict` + `verdict_tally` + broadcast calls + `conclude!(by: nil)`;
  `DebateTurn` `touch: true`. Channels: `ApplicationCable::Connection` (identified) + `DebateChannel`.
  Controllers: `DebateVerdictsController` + `DebateVerdictPolicy`. Job: `ConcludeStaleDebatesJob` +
  `recurring.yml`. Views: `_verdict`; split `_debate_status`/`_debate_actions` (+ `viewer:` local);
  `turbo_stream_from` tags. rack-attack: `debate_verdicts/user`. No new gems, no new Stimulus.

## Testing

- **Verdict:** spectator-only + concluded-only + **visibility** (a non-follower of a private participant →
  403; a participant → 403; an active debate → 403); one immutable vote (second → no-op); tally correct;
  invalid `choice` → 422; anonymous read-only.
- **Real-time:** `post_turn`/`accept!`/`conclude!` `have_broadcasted_to`; subscription tag renders for a
  participant; **`DebateChannel` rejects an unauthorized subscribe**; the `viewer:`-local partials render
  the right composer/actions state per participant.
- **Timeout:** `perform_now` concludes an idle active debate + notifies both + awards first_debate; recent
  stays active; `touch: true` verified (posting a turn bumps `debate.updated_at`).
- Full suite green; brakeman 0; bundler-audit clean; StandardRB clean.

## Deferred

`debate_won` badge; changeable verdict; live verdict-tally for other viewers (only the voter's own bar
updates); two-session real-time system test; Project 3 (Hotwire Native).

## Program completion

This slice completes the "land everything" roadmap: **Social, Debate (MVP + verdict + real-time +
timeout), Privacy+Analytics, Badges+Trending, Block, Private accounts** all shipped. Remaining are the
explicitly-deferred niceties + **Project 3 (Hotwire Native)**.
