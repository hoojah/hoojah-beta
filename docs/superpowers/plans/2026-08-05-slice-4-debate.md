# Slice 4: One-on-One Debate (MVP) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** Turn-based one-on-one debate: challenge (from an argument) → accept/decline → alternating turns
→ conclude → public read-only transcript.

**Architecture:** `Debate` + `DebateTurn` tables (separate from the Hujah tree); an in-model state machine
mirroring `cast_vote`; **derived** `current_turn_user` (no column — the `unique [debate_id, position]`
index is the concurrency guard); thin controllers with per-action Pundit; request-driven Turbo Streams.

**Tech Stack:** Rails 8.1.3.1 / Ruby 3.4.9 (mise), Devise, Pundit, friendly_id, Turbo/Stimulus, rack-attack.
**Source spec:** `docs/superpowers/specs/2026-08-05-slice-4-debate-design.md` — READ IT (esp. §2 state
machine, §4 the exact `authorize` calls, §6 policies).

## Canonical commands (HANDOVER.md)
- Bundle: `source .mise-build-env.sh && mise exec ruby@3.4.9 -- bundle install`
- Rails: `mise exec ruby@3.4.9 -- bin/rails <args>`; Specs: `RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec <path>` (iterate `--exclude-pattern "spec/system/**/*"`).
- Test DB: `mise exec ruby@3.4.9 -- bin/rails db:test:prepare`. Gates: `... brakeman -q`, `... bundler-audit check --update`, `... standardrb`.

Branch `slice-4-debate`. Commit per task, no Claude/Anthropic attribution. **Never create data via
`bin/rails runner` in RAILS_ENV=test.** Baseline: `113/0/2` (96 non-system).

---

# Phase 1 — Models + state machine

### Task 1.1: Migrations + Notification enum/assoc
**Files:** 3 migrations; modify `app/models/notification.rb`.
- [ ] **Step 1:** `g migration CreateDebates` — `debates` per spec §1 (hujah_id/challenger_id/opponent_id
  FKs, challenger_stance/opponent_stance/status integers null:false, slug string null:false, timestamps;
  indexes incl. `add_index :debates, [:hujah_id,:challenger_id,:opponent_id], unique: true, where: "status IN (0,1)", name: "no_dup_live_debate"`, unique slug). `g migration CreateDebateTurns` — per §1
  (debate_id/user_id FKs, body text, position integer null:false; `add_index :debate_turns,
  [:debate_id,:position], unique: true`, index user_id). `g migration AddDebateToNotifications` —
  `add_column :notifications, :debate_id, :bigint` (nullable, no FK, matching the loose notification style).
- [ ] **Step 2:** migrate + `db:test:prepare`.
- [ ] **Step 3:** `Notification`: append enum `debate_challenge: 7, debate_declined: 8, debate_your_turn: 9,
  debate_concluded: 10` (do NOT renumber); add `belongs_to :debate, optional: true`.
- [ ] **Step 4:** boot check; commit.

### Task 1.2: Debate + DebateTurn models + state machine (TDD)
**Files:** `app/models/{debate,debate_turn}.rb`, `app/models/{user,hujah}.rb` (associations),
`config/initializers/friendly_id.rb` (already exists). Test: `spec/models/debate_spec.rb`,
`spec/factories/{debates,debate_turns}.rb`.
- [ ] **Step 1: Failing spec** — `spec/models/debate_spec.rb` covering:
```ruby
require 'rails_helper'
RSpec.describe Debate, type: :model do
  let(:hujah) { create(:hujah) }
  let(:challenger) { create(:user) }; let(:opponent) { create(:user) }
  def build_debate(cs: 1, os: 3)
    challenger.challenged_debates.create!(hujah: hujah, opponent: opponent,
      challenger_stance: cs, opponent_stance: os)
  end
  it 'notifies the opponent on challenge (pending)' do
    expect { build_debate }.to change { Notification.where(user: opponent, category: 'debate_challenge').count }.by(1)
  end
  it 'rejects equal stances and self-challenge' do
    expect { build_debate(cs: 1, os: 1) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(challenger.challenged_debates.build(hujah: hujah, opponent: challenger, challenger_stance: 1, opponent_stance: 3)).not_to be_valid
  end
  it 'accept! -> active, challenger moves first, notifies debate_your_turn to challenger' do
    d = build_debate
    expect { d.accept!(by: opponent) }.to change { Notification.where(user: challenger, category: 'debate_your_turn').count }.by(1)
    expect(d).to be_active
    expect(d.current_turn_user).to eq(challenger)
  end
  it 'only opponent can accept/decline, only when pending' do
    d = build_debate
    expect(d.accept!(by: challenger)).to be(false)   # not the opponent
    d.accept!(by: opponent)
    expect(d.decline!(by: opponent)).to be(false)     # not pending
  end
  it 'post_turn enforces turn order + alternation + notifies the other' do
    d = build_debate; d.accept!(by: opponent)
    expect(d.post_turn(by: opponent, body: "x")).to be(false)   # not challenger's... it IS challenger's turn
    expect(d.post_turn(by: challenger, body: "c1")).to be_truthy
    expect(d.current_turn_user).to eq(opponent)
    expect(d.post_turn(by: challenger, body: "again")).to be(false) # out of turn
    expect { d.post_turn(by: opponent, body: "o1") }
      .to change { Notification.where(user: challenger, category: 'debate_your_turn').count }.by(1)
    expect(d.turns.order(:position).pluck(:body)).to eq(%w[c1 o1])
  end
  it 'conclude! by either participant -> concluded + notifies the other' do
    d = build_debate; d.accept!(by: opponent)
    expect { d.conclude!(by: challenger) }.to change { Notification.where(user: opponent, category: 'debate_concluded').count }.by(1)
    expect(d).to be_concluded
    expect(d.current_turn_user).to be_nil
  end
end
```
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** `app/models/debate.rb`:
```ruby
class Debate < ApplicationRecord
  extend FriendlyId
  friendly_id :slug_source, use: :slugged

  belongs_to :hujah
  belongs_to :challenger, class_name: "User"
  belongs_to :opponent, class_name: "User"
  has_many :turns, class_name: "DebateTurn", dependent: :destroy

  enum :status, { pending: 0, active: 1, concluded: 2, declined: 3 }

  validates :challenger_stance, :opponent_stance, presence: true
  validate  { errors.add(:opponent_stance, "must oppose") if challenger_stance == opponent_stance }
  validate  { errors.add(:opponent_id, "must differ") if challenger_id == opponent_id }

  after_create_commit :notify_challenge

  def slug_source = ActionController::Base.helpers.strip_tags(hujah.body.to_s).split.first(8).join(" ")

  def current_turn_user
    return nil unless active?
    last = turns.order(:position).last
    last.nil? ? challenger : (last.user_id == challenger_id ? opponent : challenger)
  end

  def current_round = (turns.count / 2) + 1

  def participant?(user) = user && [challenger_id, opponent_id].include?(user.id)
  def other(user) = user.id == challenger_id ? opponent : challenger

  def accept!(by:)
    return false unless pending? && by == opponent
    update!(status: :active)
    notify(challenger, :debate_your_turn); true
  end

  def decline!(by:)
    return false unless pending? && by == opponent
    update!(status: :declined)
    notify(challenger, :debate_declined); true
  end

  def post_turn(by:, body:)
    with_lock do
      return false unless active? && by == current_turn_user
      turns.create!(user: by, body: body, position: (turns.maximum(:position) || 0) + 1)
    end
    notify(other(by), :debate_your_turn); true
  end

  def conclude!(by:)
    return false unless active? && participant?(by)
    update!(status: :concluded)
    notify(other(by), :debate_concluded); true
  end

  private

  def notify_challenge = notify(opponent, :debate_challenge)
  def notify(user, category)
    Notification.create!(user:, category:, hujah_id:, subject_user_id: (user == challenger ? opponent_id : challenger_id), debate_id: id)
  end
end
```
`app/models/debate_turn.rb`: `belongs_to :debate; belongs_to :user; validates :body, presence: true`.
`User`: `has_many :challenged_debates, class_name: "Debate", foreign_key: :challenger_id, dependent: :destroy`;
`has_many :defended_debates, class_name: "Debate", foreign_key: :opponent_id, dependent: :destroy`;
`has_many :debate_turns, dependent: :destroy`. `Hujah`: `has_many :debates, dependent: :destroy`. Factories.
- [ ] **Step 4: Run → PASS; full suite green. Commit.**

---

# Phase 2 — Policies (TDD)

### Task 2.1: DebatePolicy (+Scope) + DebateTurnPolicy
**Files:** `app/policies/{debate_policy,debate_turn_policy}.rb`; specs.
- [ ] **Step 1: Failing specs** — `debate_policy_spec.rb`: show? (concluded→anyone incl nil; active→participants
  only); accept?/decline? (opponent+pending only); conclude? (participant+active); `Scope` (nil user → only
  concluded; a participant → concluded + their own; excludes others' active). `debate_turn_policy_spec.rb`:
  create? true only for `debate.current_turn_user` on an active debate; false for the other participant,
  non-participant, nil user, non-active debate.
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** per spec §6 exactly:
```ruby
class DebatePolicy < ApplicationPolicy
  def show?    = record.concluded? || record.participant?(user)
  def create?  = user.present?
  def accept?  = user.present? && user == record.opponent && record.pending?
  def decline? = accept?
  def conclude? = record.participant?(user) && record.active?
  class Scope < ApplicationPolicy::Scope
    def resolve
      if user
        scope.where(status: :concluded).or(scope.where(challenger_id: user.id)).or(scope.where(opponent_id: user.id))
      else
        scope.where(status: :concluded)
      end
    end
  end
end

class DebateTurnPolicy < ApplicationPolicy
  def create? = user.present? && record.debate.active? && record.debate.current_turn_user == user
end
```
- [ ] **Step 4: Run → PASS. Commit.**

---

# Phase 3 — Controllers + routes + throttles

### Task 3.1: Routes + DebatesController + DebateTurnsController + rack-attack
**Files:** `config/routes.rb`, `config/initializers/rack_attack.rb`,
`app/controllers/{debates,debate_turns}_controller.rb`, `app/controllers/hujahs_controller.rb` (Debates
lens), Turbo-stream views. Test: `spec/requests/debate_spec.rb`.
- [ ] **Step 1: Routes** — per spec §4 (the 6 routes). **Step 2: Throttles** — the 2 rack-attack throttles (§4).
- [ ] **Step 3: Failing request spec** — `spec/requests/debate_spec.rb` — the security matrix from spec
  Testing:
```ruby
require 'rails_helper'
RSpec.describe 'Debates', type: :request do
  let(:hujah) { create(:hujah) }
  let(:challenger) { create(:user) }; let(:opponent) { create(:user) }
  let!(:argument) { create(:hujah, parent: hujah, user: opponent, vote: 3) }

  def challenge!
    sign_in challenger
    post "/hoojah/#{hujah.slug}/debates", params: { argument_id: argument.id, challenger_stance: 1 }
    Debate.last
  end

  it 'creates a pending debate from an argument' do
    expect { challenge! }.to change(Debate, :count).by(1)
    expect(Debate.last.opponent).to eq(opponent)
  end
  it 'rejects a forged argument from another hoojah (422)' do
    other = create(:hujah); foreign = create(:hujah, parent: other, user: opponent, vote: 3)
    sign_in challenger
    post "/hoojah/#{hujah.slug}/debates", params: { argument_id: foreign.id, challenger_stance: 1 }
    expect(response).to have_http_status(:unprocessable_content)
  end
  it 'a non-current-turn participant cannot post a turn (403) — the C1 test' do
    d = challenge!; d.accept!(by: opponent)   # challenger's turn now
    sign_in opponent
    post "/debates/#{d.slug}/turns", params: { body: "not my turn" }
    expect(response).to have_http_status(:forbidden)
    expect(d.turns.count).to eq(0)
  end
  it 'the current-turn participant can post; the other then can' do
    d = challenge!; d.accept!(by: opponent)
    sign_in challenger
    post "/debates/#{d.slug}/turns", params: { body: "c1" }, headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
    expect(d.reload.turns.count).to eq(1)
  end
  it 'active debate hidden from non-participant; concluded public' do
    d = challenge!; d.accept!(by: opponent)
    sign_in create(:user)
    get "/debates/#{d.slug}"; expect(response).to have_http_status(:forbidden)
    d.conclude!(by: challenger)
    get "/debates/#{d.slug}"; expect(response).to have_http_status(:ok)
  end
end
```
- [ ] **Step 4: Run → FAIL.**
- [ ] **Step 5: Implement** `DebatesController` + `DebateTurnsController` per spec §4 — **exactly** the
  pinned `authorize @debate.turns.new(user: current_user), :create?` in DebateTurnsController; strong params
  `permit(:argument_id, :challenger_stance)` / `permit(:body)`; the `argument.parent_id == @hujah.id`
  check → 422; `rescue ActiveRecord::RecordNotUnique`; graceful validation failure → 422;
  accept/decline/conclude member actions authorize + call the model method. `HujahsController#show` adds
  `@debates = policy_scope(@hujah.debates)` (no new route; `show` stays `skip_authorization`). Turbo-stream
  views: `debate_turns/create` (append `_debate_turn` + replace `_turn_composer`); `debates/create`
  (append `_debate_card` to the lens + `close_dialog`); accept/decline/conclude replace `_debate_status`.
- [ ] **Step 6: Run → PASS; full suite green; brakeman 0. Commit.**

---

# Phase 4 — Views + Stimulus

### Task 4.1: Debate views + challenge dialog + composer
**Files:** `app/views/debates/{show,create,accept,decline,conclude}...`; partials `_debate_card`,
`_debate_transcript`, `_debate_turn`, `_turn_composer`, `_debate_status`, `_challenge_dialog`; modify
`app/views/hujahs/show.html.erb` (Debates lens) + `_child_card` (Challenge action); create
`app/javascript/controllers/debate_composer_controller.js`; CSS `field-sizing` in the Tailwind source.
- [ ] **Step 1:** Debate show renders `_debate_transcript` (`id=dom_id(@debate,:transcript)`, turns via
  `_debate_turn` with `format_body` + `local-time`) + `_turn_composer` (`id=dom_id(@debate,:composer)`,
  shown only when `@debate.current_turn_user == current_user`, else "waiting for @opponent") + status/actions.
- [ ] **Step 2:** Challenge dialog on `_child_card` — a `<dialog id="<%= dom_id(argument, :challenge_dialog) %>">`
  (via the existing `dialog_controller`) with a stance-confirm + `button_to` to `POST /hoojah/:slug/debates`
  (params argument_id + challenger_stance). The `debates/create.turbo_stream.erb` `close_dialog` target uses
  the **same** `dom_id(argument, :challenge_dialog)`.
- [ ] **Step 3:** `debate_composer_controller.js`: `static targets = ["field"]`; `connect() {
  this.fieldTarget.focus() }`. (Add a `submit` target + `toggleSubmit` only if a disabled-empty button is
  wanted.) Add `field-sizing: content` to the composer textarea class in `app/assets/tailwind/application.css`.
  The Debates lens on `hujahs/show` lists `@debates` (`_debate_card` linking to `/debates/:slug`).
- [ ] **Step 4:** Request assertions that the hoojah show page renders the Debates lens + the argument card
  gains a Challenge action; run → green. Write `spec/system/debate_spec.rb` (Phase 5). Commit.

---

# Phase 5 — System tests, gates, docs

### Task 5.1: cuprite system spec
- [ ] `db:test:prepare`. `spec/system/debate_spec.rb`: challenger opens the challenge dialog on an argument →
  submits → (as opponent) accept → alternating turns append in place, composer refocuses → conclude → the
  transcript is read-only. Reuse the Slice-3 `login_as_system` harness + the Slice-2 capybara support.
  Run twice; stabilize any flake with Capybara waits. Commit.

### Task 5.2: Gates + docs
- [ ] `standardrb --fix`; full suite green. brakeman 0; bundler-audit clean.
- [ ] README + `docs/superpowers/HANDOVER.md` "Slice 4 (Debate MVP) — DONE": what shipped; still-open
  (debate Increments 2a verdict / 2b real-time / 3 timeout; Privacy+Analytics; Badges incl. `debate_won`;
  Trending; Block/mute) per the roadmap.
- [ ] Full suite green; gates clean. Commit.

## Definition of done
Challenge→accept/decline→alternating turns→conclude, public concluded transcript, Debates lens; the C1
turn-authorization test + the full security matrix pass; throttles; brakeman 0; suite green incl. cuprite.

## Deferred
Debate Increments 2a/2b/3; then Privacy+Analytics, Badges/Trending, Block/mute (the rest of the program).
