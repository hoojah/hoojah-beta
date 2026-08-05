# Slice 8: Debate Increments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** Spectator verdict (2a) + real-time turns with channel auth (2b) + timeout auto-conclude (3).
**Source spec:** `docs/superpowers/specs/2026-08-06-slice-8-debate-increments-design.md` — READ IT (the
code blocks are the security-critical fixes).

## Canonical commands (HANDOVER.md)
- Rails: `mise exec ruby@3.4.9 -- bin/rails <args>`; Specs: `RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec <path>` (iterate `--exclude-pattern "spec/system/**/*"`). `db:test:prepare` after migrations. Gates: brakeman/bundler-audit/standardrb.

Branch `slice-8-debate-increments`. Commit per task, no attribution. **Never create data via `bin/rails runner`
in RAILS_ENV=test.** Baseline `225/0/2` (202 non-system).

---

# Phase 1 — Verdict (2a)

### Task 1.1: DebateVerdict + cast_verdict (compute-on-read) + policy
**Files:** migration `CreateDebateVerdicts`; `app/models/debate_verdict.rb`; modify `app/models/debate.rb`;
`app/policies/debate_verdict_policy.rb`. Test: `spec/models/debate_verdict_spec.rb`, `spec/policies/debate_verdict_policy_spec.rb`, factory.
- [ ] **Step 1: Migration** — `debate_verdicts (references debate null:false FK, references user null:false FK,
  choice integer null:false, timestamps)`, `add_index [:debate_id,:user_id], unique: true` (NO standalone
  debate_id index). Migrate + `db:test:prepare`.
- [ ] **Step 2: Failing specs** — `debate_verdict_spec`: `cast_verdict` — a spectator on a concluded debate
  records a verdict; a participant → false; on an active debate → false; invalid choice → false; second vote
  by same spectator → false (no dup, `verdict_tally` unchanged); `verdict_tally` groups by choice.
  `debate_verdict_policy_spec`: create? true for a visible spectator on a concluded debate; false for
  participant / active / a non-follower of a private participant (visibility).
- [ ] **Step 3: Run → FAIL.**
- [ ] **Step 4: Implement** — `DebateVerdict` (`belongs_to :debate,:user`; `enum :choice, {challenger:0,
  opponent:1, draw:2}`). `Debate`: `has_many :debate_verdicts, dependent: :destroy`; `cast_verdict` **exactly
  per spec §2a** (single `create!`, **method-level** `rescue ActiveRecord::RecordNotUnique => false`, NO
  transaction, NO counters); `def verdict_tally = debate_verdicts.group(:choice).count`.
  `DebateVerdictPolicy#create?` **exactly per spec** (`... && DebatePolicy.new(user, record.debate).show?`).
- [ ] **Step 5: Run → PASS; full suite green. Commit.**

### Task 1.2: DebateVerdictsController + route + view + throttle
**Files:** `config/routes.rb`, `config/initializers/rack_attack.rb`, `app/controllers/debate_verdicts_controller.rb`,
`app/views/debates/_verdict.html.erb`, `app/views/debate_verdicts/create.turbo_stream.erb`; modify
`app/views/debates/show.html.erb`. Test: `spec/requests/debate_verdict_spec.rb`.
- [ ] **Step 1: Route** — `post "/debates/:slug/verdicts", to: "debate_verdicts#create"`. rack-attack
  `debate_verdicts/user` throttle (spec §2a).
- [ ] **Step 2: Failing spec** — spectator votes on a concluded debate → turbo_stream replaces
  `dom_id(@debate, :verdict)`, verdict recorded; a participant → 403; active debate → 403; invalid choice →
  422; unauth → login.
- [ ] **Step 3: Implement** — `DebateVerdictsController` per spec §2a (`authenticate_user!`; `rescue_from
  Pundit::NotAuthorizedError, with: :render_forbidden`; `verdict_params = params.permit(:choice)`;
  **`authorize @debate.debate_verdicts.new(user: current_user, choice: ...), :create?`**; `cast_verdict`
  → invalid → `head :unprocessable_content`; turbo_stream). `_verdict` partial (`id=dom_id(@debate,:verdict)`,
  three `button_to` for an eligible spectator else the read-only tally bar via `verdict_tally`), rendered on
  `debates/show` for concluded debates.
- [ ] **Step 4: Run → PASS; full suite green; brakeman 0. Commit.**

---

# Phase 2 — Timeout (3)

### Task 2.1: touch:true + conclude!(by: nil) + job + recurring
**Files:** modify `app/models/{debate_turn,debate}.rb`, `config/recurring.yml`; create
`app/jobs/conclude_stale_debates_job.rb`. Test: `spec/models/debate_spec.rb` (extend), `spec/jobs/conclude_stale_debates_job_spec.rb`.
- [ ] **Step 1: Failing spec** — `conclude!(by: nil)` concludes + notifies BOTH participants + no crash;
  `conclude!(by: non_participant)` still false; posting a turn bumps `debate.updated_at` (touch); job:
  `perform_now` concludes an active debate whose `updated_at` is >7 days old + notifies both, leaves a
  recent active one, skips concluded/declined.
- [ ] **Step 2: Run → FAIL** (conclude!(by:nil) currently crashes on `other(nil)`; no touch).
- [ ] **Step 3: Implement** — `DebateTurn`: `belongs_to :debate, touch: true`. `Debate#conclude!(by: nil)`
  **exactly per spec §3** (branch `by.nil?` → notify both, else `other(by)`). `ConcludeStaleDebatesJob`
  (`Debate.active.where("updated_at < ?", 7.days.ago).find_each { |d| d.conclude!(by: nil) }`).
  `config/recurring.yml` production entry `conclude_stale_debates`.
- [ ] **Step 4: Run → PASS; full suite green. Commit.**

---

# Phase 3 — Real-time (2b) + channel authorization

### Task 3.1: Cable connection + DebateChannel auth
**Files:** modify `app/channels/application_cable/connection.rb`; create `app/channels/debate_channel.rb`.
Test: `spec/channels/debate_channel_spec.rb`.
- [ ] **Step 1: Failing spec** — a participant can subscribe to the debate stream; a non-participant of an
  ACTIVE debate is rejected; (concluded + visible) is allowed. (Use `stub_connection(current_user:)` +
  `subscribe`; assert `subscription.confirmed?`/`rejected?`.)
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** — `ApplicationCable::Connection` (`identified_by :current_user`; `connect` →
  `env["warden"]&.user(scope: :user) || reject_unauthorized_connection`). `DebateChannel < Turbo::StreamsChannel`:
  `subscribed` derives the `Debate` from the verified stream name and `reject`s unless
  `DebatePolicy.new(current_user, debate).show?` (spec §2b — adapt the GlobalID/stream-name derivation so
  it actually resolves the debate; if the composite `[@debate, user]` stream is hard to resolve, gate the
  main `@debate` stream via the channel and leave the user-signed composer stream as user-scoped).
- [ ] **Step 4: Run → PASS. Commit.**

### Task 3.2: Broadcasts + viewer-scoped partials
**Files:** modify `app/models/debate.rb` (broadcast calls), `app/views/debates/show.html.erb`,
`app/views/debates/{_turn_composer,_debate_status}.html.erb` (+ new `_debate_actions.html.erb`). Test:
`spec/models/debate_broadcast_spec.rb`.
- [ ] **Step 1: Failing spec** — `have_broadcasted_to(debate)` on `post_turn` (transcript append) and on
  `accept!`/`conclude!`; the `viewer:`-local composer renders the form for the current-turn viewer and a
  waiting note for the other.
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** — `debates/show`: `turbo_stream_from @debate, channel: "DebateChannel"` +
  `turbo_stream_from [@debate, current_user], channel: "DebateChannel" if @debate.participant?(current_user)`.
  Split `_debate_status` → `_debate_status` (label, agnostic) + new `_debate_actions` (Accept/Decline/Conclude,
  takes `viewer:`); `_turn_composer` takes `viewer: local_assigns.fetch(:viewer) { current_user }`.
  `Debate#post_turn` (after `with_lock`): `broadcast_append_later_to @debate, target: dom_id(self,:transcript),
  partial: "debates/debate_turn", locals: { turn }` + per-participant `broadcast_replace_later_to [self, p],
  target: dom_id(self,:composer), partial: "debates/turn_composer", locals: { debate: self, viewer: p }`.
  `accept!`/`conclude!` broadcast `_debate_status` (to @debate) + `_debate_actions` (per-participant). **Keep
  the Slice-4 controller turbo_stream responses unchanged** (Turbo id-dedup handles the double-append).
- [ ] **Step 4: Run → PASS; full suite green. Commit.**

---

# Phase 4 — System + gates + docs

### Task 4.1: cuprite + gates + docs
- [ ] **Step 1:** `db:test:prepare`. `spec/system/debate_verdict_spec.rb` (reuse `login_as_system`): a
  spectator votes on a concluded debate → the tally bar updates. (Real-time two-session is out of scope —
  assert the `turbo_stream_from` tag renders on the show page instead.) Run twice; stabilize with waits.
- [ ] **Step 2:** `standardrb --fix`; full suite green. brakeman 0; bundler-audit clean.
- [ ] **Step 3:** README + `docs/superpowers/HANDOVER.md` "Slice 8 (Debate Increments) — DONE" + a
  **"Program complete"** note (all roadmap features shipped; remaining = deferred niceties + Project 3).
  Note dev has no job worker (timeout runs in prod recurring only).
- [ ] **Step 4: Full suite green; gates clean. Commit.**

## Definition of done
Spectator verdict (visible-spectator-only, one immutable vote, compute-on-read tally); real-time turns via
authorized `DebateChannel` broadcasts (viewer-scoped composer/actions, id-dedup, no turn-path rewrite);
timeout auto-conclude (touch-tracked idleness, `conclude!(by: nil)` notifies both); suite green incl.
cuprite; brakeman 0. **Program complete.**

## Deferred
`debate_won`; changeable verdict; live tally for non-voters; two-session real-time test; Project 3.
