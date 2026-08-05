# Slice 4: One-on-One Debate — MVP

_Design spec. Date: 2026-08-05. Status: **design + specialist-reviewed** (security, Stimulus, simplicity —
folded, v2). "Land everything" program (roadmap: `docs/superpowers/ROADMAP-future-features.md`). The
**signature** Hoojah feature._

> **Review incorporation (v2).** **Simplicity trims:** derive `current_turn_user` (no column) + `round`
> (from turn count); drop `max_rounds`/auto-conclude (→ Increment 3); `friendly_id :slugged` (no history);
> collapse `debate_accepted` into `debate_your_turn` → **4** debate notification categories. **Security
> (Critical):** `DebateTurnsController#create` authorizes a **DebateTurn**, not the debate (else any user
> posts any turn); + nil-safe public Debates-lens `Scope`, strong-params (no `opponent_id`/`user_id`/
> `position`), validate the argument belongs to the URL hoojah, `RecordNotUnique` + validation-failure
> handling, `with_lock` in `post_turn`, rack-attack throttles. **Stimulus:** CSS `field-sizing` (no JS
> auto-grow); minimal `debate_composer` (autofocus + optional empty-disable); challenge-dialog `dom_id`
> scoped to the **hoojah/argument** (no Debate exists at open-time); (there is no `vote_controller.js` —
> voting is a pure server round-trip).

## Context

Shipped: feed, 3-option voting, threaded arguments (child hoojahs carrying a stance in `hujahs.vote`),
compose/profile/notifications/flags/share, Devise 5.0.4, Pundit, Slice 3 social (follow/feed/mentions).
This slice adds the **one-on-one debate** — a focused, turn-based back-and-forth between two users,
escalated from an existing argument. **Increment 1 (MVP)**; spectator verdict, real-time broadcasting, and
turn-timeout auto-conclude are later program sub-slices.

## Goals (MVP)

Challenge a user from their argument → accept/decline → alternating turns (each notifies the other) →
conclude → **public, read-only transcript**. Debates surface in a "Debates" lens on the hoojah page
(linked to, not replacing, the argument thread).

## Non-goals (later sub-slices)

Spectator "who argued better?" verdict (2a); real-time broadcasting via Solid Cable (2b); turn-timeout +
turn-cap auto-conclude via Solid Queue (3); profile-level "challenge anyone"; turn edit/delete (turns are
immutable); @mention-notify inside a turn body (turns are outside the `Hujah` tree — a typed `@handle`
links but does not notify; cosmetic).

## Locked decisions (defaults from the sketch; reviewed)

| Question | Default |
|---|---|
| Who challenges whom | **Argument-anchored only** (challenge the argument's author) |
| Stance opposition | **Enforced** — `opponent_stance != challenger_stance` (model validation) |
| Active-debate visibility | Participants-only while active; **public** once concluded |
| Turn immutability | Immutable |
| Multiple debates per hoojah | Allowed; partial-unique index blocks a duplicate *live* challenge for the same (hoojah, challenger, opponent) — directional |
| Abandonment / length bound | No auto-timeout or turn-cap in MVP (→ Increment 3); either party may `conclude` anytime |
| Notification deep-link | nullable `notifications.debate_id` |

## Architecture

### 1. Data model (2 tables + 1 column; derived state, not stored)

```
debates
  hujah_id           bigint  null: false  FK→hujahs
  challenger_id      bigint  null: false  FK→users
  opponent_id        bigint  null: false  FK→users
  challenger_stance  integer null: false          # 1/2/3 (snapshot — votes are mutable, so store it)
  opponent_stance    integer null: false          # snapshot
  status             integer null: false default 0  # enum pending/active/concluded/declined
  slug               string  null: false          # friendly_id :slugged (NO history)
  timestamps
indexes: [hujah_id],[challenger_id],[opponent_id],[status], unique[slug],
         partial-unique [hujah_id,challenger_id,opponent_id] WHERE status IN (0,1)

debate_turns
  debate_id bigint null: false FK→debates
  user_id   bigint null: false FK→users
  body      text   null: false                    # raw; rendered via format_body
  position  integer null: false                   # 1..N; assigned (turns.maximum(:position)||0)+1
  timestamps
indexes: unique [debate_id, position], [user_id]

notifications  → ADD debate_id bigint, nullable
```
**No `round`, `current_turn_user_id`, or `max_rounds` columns** — derived (below). Turns are deliberately
NOT child hoojahs (avoids feed/vote/slug/flag entanglement).

**Derived (methods on `Debate`, not columns):**
```ruby
def current_turn_user
  return nil unless active?
  last = turns.order(:position).last
  last.nil? ? challenger : (last.user_id == challenger_id ? opponent : challenger)
end
def current_round = (turns.count / 2) + 1   # display only
```
Deriving `current_turn_user` removes the mutable-column race surface; the real concurrency guard is the
`unique [debate_id, position]` index.

**Associations:** `Hujah has_many :debates, dependent: :destroy`; `User has_many :challenged_debates`
(fk challenger_id), `:defended_debates` (fk opponent_id), `:debate_turns`; `Debate belongs_to :hujah,
:challenger (class_name User), :opponent (class_name User)`, `has_many :turns, class_name "DebateTurn",
dependent: :destroy`; `DebateTurn belongs_to :debate, :user`; `Notification belongs_to :debate, optional: true`.
`friendly_id :slug_source, use: :slugged` (slug from the root hoojah's first words + disambiguator).

### 2. Rich-model state machine (thin controllers, mirroring `cast_vote`)

`enum status: { pending: 0, active: 1, concluded: 2, declined: 3 }`. Validations: `opponent_stance !=
challenger_stance`; `challenger_id != opponent_id`; turn `body` presence.

- `after_create_commit :notify_challenge` → `debate_challenge` notification to the opponent (parallel to
  `Hujah#notify_parent_owner`).
- `accept!(by:)` — guard `pending?` + `by == opponent`; → `active`; notify challenger **`debate_your_turn`**
  (acceptance *is* the challenger's turn beginning — no separate `accepted` category).
- `decline!(by:)` — guard `pending?` + `by == opponent`; → `declined`; notify challenger `debate_declined`.
- `post_turn(by:, body:)` — `with_lock` inside a transaction: guard `active?` + `by == current_turn_user`;
  create `DebateTurn` at `(turns.maximum(:position)||0)+1`; notify the *other* participant
  `debate_your_turn`. **No round math, no auto-conclude** (deferred). Returns false / raises on guard fail.
- `conclude!(by:)` — guard `active?` + participant; → `concluded`; notify the other `debate_concluded`.

### 3. Notifications — append-only, 4 new categories

```ruby
enum :category, { …, mention: 5, new_follower: 6,
                  debate_challenge: 7, debate_declined: 8, debate_your_turn: 9, debate_concluded: 10 }
```
Created inside the model methods. `hujah_id` → root hoojah, `subject_user_id` → the other participant,
`debate_id` → deep-link. `_notification_card` gets `case` branches + Lucide icons (choose from the
available set at build, e.g. `swords`/`messages-square`/`flag`).

### 4. Routes / controllers (RESTful; every write derives actor from `current_user`)

```ruby
post   "/hoojah/:slug/debates",   to: "debates#create"
get    "/debates/:slug",          to: "debates#show",     as: :debate
patch  "/debates/:slug/accept",   to: "debates#accept"
patch  "/debates/:slug/decline",  to: "debates#decline"
patch  "/debates/:slug/conclude", to: "debates#conclude"
post   "/debates/:slug/turns",    to: "debate_turns#create"
```
(No generic `PATCH /debates/:slug` — the named member actions only.)

**`DebatesController#create`** (`authenticate_user!`): strong params **`permit(:argument_id,
:challenger_stance)` only**. Load `@hujah` from the URL `:slug`; load `argument = Hujah.find(params[:argument_id])`
and **validate `argument.parent_id == @hujah.id`** (the argument belongs to this hoojah) else
`head :unprocessable_content`. Derive `opponent = argument.user`, `opponent_stance = argument.vote`,
`challenger_stance` = the submitted value (or the challenger's own vote on the root, validated to oppose).
Build via `current_user.challenged_debates.new(hujah: @hujah, opponent:, ...)` — **never** an `opponent_id`/
`challenger_id` from params. `authorize @debate, :create?`. Save with graceful failure
(`if @debate.save … else render/head :unprocessable_content`, catching the stance/self-challenge
validation). **`rescue ActiveRecord::RecordNotUnique`** (dup live challenge race) → treat as an already-
exists no-op, like `FollowsController`. Respond: `turbo_stream` (append the debate card to the hoojah
Debates lens) + `close_dialog` for the challenge dialog.

**`DebateTurnsController#create`** (`authenticate_user!`): strong params **`permit(:body)` only**. Load
`@debate` by slug. **CRITICAL — `authorize @debate.turns.new(user: current_user), :create?`** (resolves
`DebateTurnPolicy`, NOT `DebatePolicy` — authorizing `@debate` would call `DebatePolicy#create?` =
`user.present?` and let any user post any turn). Then `@debate.post_turn(by: current_user, body:
params[:body])`; on a guard/validation failure render `:unprocessable_content` (not 500). Respond
`turbo_stream.append` `_debate_turn` to `dom_id(@debate, :transcript)` + `turbo_stream.replace`
`_turn_composer` at `dom_id(@debate, :composer)`.

**`accept`/`decline`/`conclude`** (`authenticate_user!`): load `@debate`, `authorize @debate, :accept?`
(resp.), call the model method (rescue `RecordInvalid`→422), Turbo-Stream replace the `_debate_status`/
`_debate_actions` region.

**Debates lens** — NOT a new action/route: `HujahsController#show` (public, `skip_authorization`) adds
inline `@debates = policy_scope(@hujah.debates)`. `policy_scope` does not count toward `verify_authorized`.

**rack-attack** (`config/initializers/rack_attack.rb`, following the file's idiom):
```ruby
throttle("debates/challenge/user", limit: 10, period: 1.minute) { |r| r.env["warden"]&.user&.id if r.post? && r.path.match?(%r{\A/hoojah/[^/]+/debates\z}) }
throttle("debates/turns/user",     limit: 20, period: 1.minute) { |r| r.env["warden"]&.user&.id if r.post? && r.path.match?(%r{\A/debates/[^/]+/turns\z}) }
```

### 5. Hotwire (request-driven Turbo Streams — broadcasting deferred to Increment 2b)

Human-paced → request-driven is enough. Turn post → `append` `_debate_turn` + `replace` `_turn_composer`
(now "waiting for @opponent", form disabled for the mover). Accept/decline/conclude → replace the status/
actions region. **Pin `dom_id(@debate, :transcript)` / `dom_id(@debate, :composer)` now** so 2b
broadcasting drops in untouched.

**Stimulus:**
- Reuse `dialog_controller` for the "Challenge to debate" stance-confirm modal. The dialog exists before
  any `Debate` does, so its element id is **`dom_id(argument, :challenge_dialog)`** (scoped to the
  argument/hoojah, NOT a debate); `DebatesController#create`'s `close_dialog` Turbo-Stream target must use
  the **exact same** `dom_id` call. Challenge-dialog teardown is already covered by the global
  `turbo:before-cache` loop (non-task).
- `debate_composer_controller` — minimal & presentational: `connect() { this.fieldTarget.focus() }` (the
  one legit `connect()` use — refocuses the textarea on first render AND after the Turbo-Stream replace,
  which also scrolls it into view for free). Auto-grow is **CSS `field-sizing: content`** (+ `rows="3"`
  fallback), no JS. Empty-submit blocking is native `required` + Turbo's in-flight submit-disable; add a
  `submit` target + `input->debate-composer#toggleSubmit` **only if** a visibly-disabled button is wanted
  (no Values, no state). Targets: `field`, (optional) `submit`. `local-time` (pinned) for turn timestamps.

### 6. Authorization (Pundit — per-action)

- `DebatePolicy`: `show? = record.concluded? || participant?`; `create? = user.present?`;
  `accept? = user_present && user == record.opponent && record.pending?`; `decline? = accept?`;
  `conclude? = participant? && record.active?`; `participant? = user && [challenger_id, opponent_id].include?(user.id)`.
  **`Scope#resolve`** (nil-safe — the lens renders on the public hoojah page): `user ?
  scope.where(status: :concluded).or(scope.where(challenger_id: user.id)).or(scope.where(opponent_id: user.id))
  : scope.where(status: :concluded)`.
- `DebateTurnPolicy#create? = user && record.debate.active? && record.debate.current_turn_user == user`.
- `debates#show` calls `authorize @debate` before loading turns. Every action authorize/skip'd.

## Gem manifest

**None.**

## Component boundaries

- Models: `Debate` (state machine + validations + `current_turn_user`/`current_round` + friendly_id +
  notifications), `DebateTurn`; `Notification` gains `belongs_to :debate`.
- Controllers: `DebatesController` (create/show/accept/decline/conclude), `DebateTurnsController` (create).
- Policies: `DebatePolicy` (+ `Scope`), `DebateTurnPolicy`.
- Partials: `_debate_card`, `_debate_transcript`, `_debate_turn`, `_turn_composer`, `_debate_status`,
  `_challenge_dialog`; a "Debates" section on `hujahs/show`; a "Challenge to debate" action on `_child_card`.
- Stimulus: reuse `dialog`; add `debate_composer` (autofocus, optional empty-disable). CSS `field-sizing`.
- rack-attack: two throttles.

## Testing

- **Model:** accept/decline guards (only opponent, only pending); `post_turn` — only `current_turn_user`
  may post, only when `active?`, position increments, `with_lock` prevents a double-post duplicate
  (unique index); `conclude!` by either participant; `current_turn_user` derivation (challenger first,
  then alternation, nil unless active); stance-opposition + distinct-participant validations; one
  notification per transition (correct category + `debate_id`).
- **Request (security-critical):** **a participant who is NOT `current_turn_user` posting a turn → 403**
  (the C1 mis-wire test); posting to a concluded/pending debate → 403; **non-participant viewing an active
  debate → 403, anyone viewing a concluded debate → 200**; a **forged `argument_id`** from another hoojah →
  422; a **duplicate live challenge** → handled (no 500); a self-/same-stance challenge → 422 (not 500);
  the Debates lens on a public hoojah page shows concluded debates to anonymous, hides others' active ones.
- **System (cuprite):** challenge dialog → accept → alternating turns append in place + composer refocus →
  conclude → read-only transcript. (Reuse the Slice-3 `login_as_system` harness.)
- Full suite green; brakeman 0; bundler-audit clean; StandardRB clean. Eager-load turns + participants.

## Execution model

This reviewed spec → `writing-plans` → subagent-driven build with per-phase review gates.

## Risks / open questions

- **Cross-hoojah harassment:** the partial-unique index + actor-scoped `debates/challenge/user` throttle
  bound duplicate live challenges + burst rate, but not one user challenging a victim across many hoojahs
  (same gap as `follow/user`). Acceptable for MVP; the Block/mute Safety slice closes it.
- **Abandonment / unbounded length:** no auto-timeout or turn-cap in MVP; a ghosted/endless `active`
  debate persists until a participant concludes. Increment 3 (Solid Queue) resolves both.
- **Stance seeding:** challenger stance = their existing vote on the root if present, else chosen in the
  dialog; validated to oppose the opponent's.

## Deferred (later program sub-slices)

2a spectator verdict (reuse the vote-counter idiom); 2b real-time via Solid Cable; 3 turn-timeout/cap
auto-conclude. Then: Privacy-hardening + Analytics, Badges (incl. `debate_won`), Trending, Block/mute +
private accounts.
