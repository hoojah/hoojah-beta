# Slice 4: One-on-One Debate — MVP

_Design spec. Date: 2026-08-05. Status: **design (from roadmap sketch)**, pending specialist review +
plan. "Land everything" program (roadmap: `docs/superpowers/ROADMAP-future-features.md`). This is the
**signature** Hoojah feature._

## Context

Shipped: feed, 3-option voting, threaded arguments (child hoojahs carrying a stance in `hujahs.vote`),
compose/profile/notifications/flags/share, Devise 5.0.4, Pundit, and Slice 3 social (follow/feed/mentions).
This slice adds the **one-on-one debate**: a focused, turn-based back-and-forth between two users,
escalated from an existing argument. This is **Increment 1 (MVP)**; spectator verdict, real-time
broadcasting, and turn-timeout auto-conclude are later sub-slices in the program.

## Goals (MVP / Increment 1)

1. **Challenge** a user to a debate from their existing argument on a hoojah.
2. **Accept / decline** a challenge.
3. **Alternating turns** (turn-based, capped at `max_rounds`), each notifying the other party.
4. **Conclude / concede** → a **public, read-only transcript**.
5. Debates surface in a "Debates" lens on the hoojah page (linked to, not replacing, the argument thread).

## Non-goals (later program sub-slices)

Spectator "who argued better?" verdict (Increment 2a); real-time turn broadcasting via Solid Cable
(Increment 2b); turn-timeout auto-conclude via Solid Queue (Increment 3). Also deferred: challenging from
a profile (challenge is argument-anchored only in MVP), turn edit/delete (turns are immutable).

## Locked decisions (defaults chosen from the sketch's open questions; flagged for review)

| Question | Default |
|---|---|
| Who can challenge whom | **Argument-anchored only** — challenge the author of an existing argument; both stances already known |
| Stance opposition | **Enforced** — `opponent_stance` must differ from `challenger_stance` (model validation) |
| Active-debate visibility | **Participants-only** while active; **public** once concluded |
| Turn immutability | **Immutable** once posted (no edit/delete) |
| Multiple debates per hoojah | **Allowed**; a **partial-unique index** blocks a duplicate *live* challenge between the same pair on the same hoojah |
| Abandonment | MVP: either party may `conclude`/`concede` anytime; **no auto-timeout** (Increment 3) |
| Notification deep-link | add nullable `notifications.debate_id` |
| Relationship to arguments | **Link, not replace** — a "Debates" section on the hoojah page |

## Architecture

### 1. Data model (two new tables + one column)

```
debates
  hujah_id            bigint  null: false  FK→hujahs     # the claim being debated
  challenger_id       bigint  null: false  FK→users
  opponent_id         bigint  null: false  FK→users
  challenger_stance   integer null: false                # 1/2/3, same enum as hujahs.vote
  opponent_stance     integer null: false
  status              integer null: false  default: 0    # enum pending/active/concluded/declined
  current_turn_user_id bigint  FK→users, nullable        # whose move; nil when pending/concluded/declined
  max_rounds          integer null: false  default: 5
  round               integer null: false  default: 0
  slug                string  null: false                # friendly_id
  timestamps
indexes: [hujah_id], [challenger_id], [opponent_id], [status], unique [slug],
         partial-unique [hujah_id, challenger_id, opponent_id] WHERE status IN (0,1)   # no dup live challenge

debate_turns
  debate_id  bigint null: false FK→debates
  user_id    bigint null: false FK→users
  body       text   null: false                          # raw; rendered via format_body
  position   integer null: false                         # 1..N strict order
  round      integer null: false
  timestamps
indexes: unique [debate_id, position], [user_id]

notifications  → ADD  debate_id bigint, nullable   (deep-link debate notifications)
```

**Kept separate from the `Hujah` tree** — debate turns are NOT child hoojahs (that would entangle
feed/vote/slug/flag machinery). A turn is a plain authored body.

**Associations:** `Hujah has_many :debates, dependent: :destroy`; `User has_many :challenged_debates`
(fk challenger_id) + `:defended_debates` (fk opponent_id) + `:debate_turns`; `Debate belongs_to :hujah,
:challenger, :opponent, :current_turn_user (optional)`, `has_many :turns, class_name: "DebateTurn",
dependent: :destroy`; `DebateTurn belongs_to :debate, :user`. `Notification belongs_to :debate, optional: true`.

**friendly_id:** `Debate` uses `[:slugged, :history]` (like `Hujah`); slug from the root hoojah's first
words + disambiguator (deep-link-friendly for Project 3).

### 2. Rich-model state machine (thin controllers, like `cast_vote`)

`Debate` enum `status: { pending: 0, active: 1, concluded: 2, declined: 3 }`. Methods (each wrapped in a
`transaction`, notifications via the model):
- `accept!` — guard `pending?` + caller is opponent; → `active`, `current_turn_user = challenger`
  (challenger moves first); notify challenger (`debate_accepted`).
- `decline!` — guard `pending?` + opponent; → `declined`; notify challenger (`debate_declined`).
- `post_turn(by:, body:)` — guard `active?` + `by == current_turn_user`; create `DebateTurn` (next
  `position`, current `round`); flip `current_turn_user` to the other participant; when both have moved in
  a round, `round += 1`; **auto-conclude when `round >= max_rounds`**; notify the other party
  (`debate_your_turn`) unless just concluded (then `debate_concluded` to both). Raise/return on guard fail.
- `conclude!(by:)` — guard `active?` + participant; → `concluded`; notify the other (`debate_concluded`).

Validations: `opponent_stance != challenger_stance`; both participants distinct; `body` presence on turns.

### 3. Notifications — append-only enum

```ruby
enum :category, { …, mention: 5, new_follower: 6,
                  debate_challenge: 7, debate_accepted: 8, debate_declined: 9,
                  debate_your_turn: 10, debate_concluded: 11 }
```
Created inside the model methods (parallel to `notify_parent_owner`/`cast_vote`). `hujah_id` → root
hoojah, `subject_user_id` → the other participant, `debate_id` → deep-link. `_notification_card` gets
`case` branches + Lucide icons (`swords`/`messages-square` for debate; pick from available Lucide set at
build).

### 4. Routes / controllers (RESTful)

```ruby
post   "/hoojah/:slug/debates",  to: "debates#create"      # challenge from an argument (params: opponent argument id / opponent_id + stances)
get    "/debates/:slug",         to: "debates#show", as: :debate
patch  "/debates/:slug/accept",  to: "debates#accept"
patch  "/debates/:slug/decline", to: "debates#decline"
patch  "/debates/:slug/conclude", to: "debates#conclude"
post   "/debates/:slug/turns",   to: "debate_turns#create"
```
`DebatesController` + `DebateTurnsController`, thin — `authenticate_user!`, `authorize`, call the model
method, respond with Turbo Streams. Challenge is initiated from an argument's card ("Challenge to debate")
via the existing `dialog_controller` (a stance-confirm dialog); `opponent = argument.user`,
`opponent_stance = argument.vote`, `challenger_stance = current_user`'s vote on the root (or chosen).
The hoojah `show` page gains a "Debates" section listing debates on that hoojah.

### 5. Hotwire (request-driven Turbo Streams — no broadcasting in MVP)

Debates are human-paced/low-frequency → request-driven is sufficient. `DebateTurnsController#create`
responds with `turbo_stream.append` of `_debate_turn` into `dom_id(debate, :transcript)` +
`turbo_stream.replace` of `_turn_composer` (`dom_id(debate, :composer)` — now "waiting for @opponent",
form disabled for the mover). Accept/decline/conclude replace a `_debate_status`/`_debate_actions`
region. **Pin `dom_id(debate, :transcript)`/`(:composer)` now** so Increment 2b broadcasting drops in
untouched. Stimulus: reuse `dialog_controller` (challenge modal); a tiny `debate_composer_controller`
(textarea auto-grow + submit-disable-while-empty, **presentational only** — no fetch/state, per the
Slice-1 Stimulus contract). `local-time` (already pinned) for turn timestamps.

### 6. Authorization (Pundit — per-action, per Slice 2 discipline)

`DebatePolicy`: `show? = record.concluded? || participant?` (active = participants-only; concluded =
public); `create? = user.present?`; `accept? = user == record.opponent && record.pending?`;
`decline? = accept?`; `conclude? = participant? && record.active?`; `participant? = user &&
[challenger_id, opponent_id].include?(user.id)`. `DebateTurnPolicy#create? = user && debate.active? &&
debate.current_turn_user_id == user.id` (the core "only the participant whose turn it is" rule).
`DebatesController#show` always `authorize @debate` (visibility folded into `show?`); `index` (Debates
lens) via `policy_scope` (concluded + your own). Every action authorize/skip'd (or 500 under
`verify_authorized`).

## Gem manifest

**None** — friendly_id, Pundit, Turbo, Notification, Solid Queue all present.

## Component boundaries

- Models: `Debate` (state machine + validations + friendly_id + notifications), `DebateTurn`;
  `Notification` gains `belongs_to :debate`.
- Controllers: `DebatesController` (create/show/accept/decline/conclude), `DebateTurnsController` (create).
- Policies: `DebatePolicy`, `DebateTurnPolicy`.
- Partials: `_debate_card` (on the hoojah Debates lens), `_debate_transcript`, `_debate_turn`,
  `_turn_composer`, `_debate_status`, `_challenge_dialog`.
- Stimulus: reuse `dialog`; add presentational `debate_composer`.
- Views: `debates/show`, a "Debates" section on `hujahs/show`, a "Challenge to debate" action on argument
  cards (`_child_card`).

## Testing

- **Model:** the state machine — accept/decline guards (only opponent, only pending), `post_turn` turn
  ordering + turn enforcement (only `current_turn_user`, only active) + round increment + auto-conclude at
  `max_rounds`, conclude by either participant; stance-opposition + distinct-participants validations;
  notification emitted per transition (correct category + `debate_id`), exactly once.
- **Request:** challenge creates a pending debate + `debate_challenge` notification; accept/decline;
  posting a turn out-of-turn → 403; posting when concluded → 403; non-participant viewing an **active**
  debate → 403; **anyone** viewing a **concluded** debate → 200; partial-unique index blocks a duplicate
  live challenge (idempotent/handled, not 500). Turbo-Stream shapes (append turn + replace composer).
- **System (cuprite):** challenge dialog → accept → alternating turns append in place → conclude → read-only
  transcript. (Reuse the Slice-3-hardened `login_as_system` harness.)
- Full suite green; brakeman 0; bundler-audit clean; StandardRB clean. Eager-load turns/participants (no N+1).

## Execution model

Spec → **3 specialist reviews (security/Stimulus/simplicity)** → `writing-plans` → subagent-driven build
with per-phase review gates. Build/test per `HANDOVER.md`.

## Risks / open questions

- **Challenge auth / harassment** — MVP anchors to an argument (contextual). The partial-unique index
  blocks duplicate live challenges; a determined harasser across hoojahs is bounded only by a (to-add)
  rack-attack throttle on `POST /hoojah/:slug/debates` — **add one** (like compose/flag). Profile-level
  "challenge anyone" + block-list interplay → Block/mute Safety slice.
- **Abandonment** — no auto-timeout in MVP; a ghosted debate sits `active` forever. Increment 3 adds a
  Solid Queue auto-conclude. Acceptable for MVP; note it.
- **Stance seeding** — challenger's stance: use their existing vote on the root hoojah if present, else
  require them to pick in the challenge dialog. Validate it opposes the opponent's.
- **`current_turn_user` integrity** — `post_turn` must be transactional + re-check the turn inside the
  transaction to avoid a double-post race (two rapid submits). Guarded by the turn check + unique
  `[debate_id, position]` index.
- **Notification volume** — a long debate emits a `debate_your_turn` per turn; acceptable (only to the 2
  participants).

## Deferred (later program sub-slices)

Increment 2a spectator verdict (reuse the vote-counter idiom); 2b real-time via Solid Cable broadcasting;
3 turn-timeout auto-conclude (Solid Queue). Then the rest of the program: Privacy-hardening + Analytics,
Badges (incl. `debate_won`, now possible) + Trending, Block/mute + private accounts.
