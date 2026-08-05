# Slice 5: Vote-Privacy Hardening + Analytics (MVP) Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** (A) stop the `new_vote` notification leaking first-voter identity; (B) an owner-only `/dashboard`
showing the user's own aggregate content stats (zero new tables).

**Source spec:** `docs/superpowers/specs/2026-08-05-slice-5-privacy-analytics-design.md` (read first).

## Canonical commands (HANDOVER.md)
- Rails: `mise exec ruby@3.4.9 -- bin/rails <args>`; Specs: `RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec <path>` (iterate `--exclude-pattern "spec/system/**/*"`). `db:test:prepare` after migrations. Gates: brakeman/bundler-audit/standardrb.

Branch `slice-5-privacy-analytics`. Commit per task, no Claude/Anthropic attribution. **Never create data
via `bin/rails runner` in RAILS_ENV=test.** Baseline: `141/0/2` (123 non-system).

---

# Phase 1 — Part A: vote-privacy fix

### Task 1.1: Drop new_vote voter-id + backfill
**Files:** modify `app/models/hujah.rb`; new backfill migration. Test: `spec/models/hujah_cast_vote_spec.rb`.
- [ ] **Step 1: Failing test** — add to `spec/models/hujah_cast_vote_spec.rb`:
```ruby
it 'does not record the voter identity on the new_vote notification (privacy)' do
  owner = create(:user); voter = create(:user); h = create(:hujah, user: owner)
  h.cast_vote(by: voter, choice: 1)
  n = Notification.where(user: owner, category: 'new_vote').last
  expect(n.subject_user_id).to be_nil
end
```
- [ ] **Step 2: Run → FAIL** (currently sets `subject_user_id: by.id`).
- [ ] **Step 3: Fix** — in `app/models/hujah.rb` `cast_vote`, delete the ` subject_user_id: by.id` argument
  from the `new_vote` `Notification.create!` (leave the other notification callbacks untouched).
- [ ] **Step 4: Backfill migration** — `g migration BackfillNewVoteSubjectUser`:
```ruby
class BackfillNewVoteSubjectUser < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!
  def up = Notification.where(category: 4).update_all(subject_user_id: nil) # 4 = new_vote
  def down; end
end
```
  (use the enum integer `4` in the migration to avoid coupling to the model constant.) Migrate + `db:test:prepare`.
- [ ] **Step 5: Serializer regression** — add a request spec (or extend `spec/requests/api/v1/notifications_spec.rb`)
  asserting a `new_vote` notification serializes with **no `subject_user`** while a `new_hoojah_response`
  still carries one. Run → PASS.
- [ ] **Step 6: Full suite green. Commit.**

---

# Phase 2 — Part B: analytics dashboard

### Task 2.1: UserAnalytics PORO
**Files:** create `app/models/user_analytics.rb`. Test: `spec/models/user_analytics_spec.rb`.
- [ ] **Step 1: Failing spec** — `spec/models/user_analytics_spec.rb`:
```ruby
require 'rails_helper'
RSpec.describe UserAnalytics do
  let(:user) { create(:user) }
  subject(:a) { described_class.new(user) }
  it 'totals votes + arguments received over own hoojahs (denormalized counts, no votes scan)' do
    h = create(:hujah, user: user, agree_count: 3, neutral_count: 1, disagree_count: 1)
    create(:hujah, user: create(:user), parent: h) # an argument received
    expect(a.total_votes_received).to eq(5)
    expect(a.total_arguments_received).to eq(1)
  end
  it 'suppresses a per-hoojah split below k=5' do
    low = create(:hujah, user: user, agree_count: 1, neutral_count: 0, disagree_count: 0)
    hi  = create(:hujah, user: user, agree_count: 3, neutral_count: 1, disagree_count: 1)
    d = a.distributions.index_by(&:id)
    expect(d[low.id].suppressed?).to be(true)
    expect(d[hi.id].suppressed?).to be(false)
  end
end
```
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** — `app/models/user_analytics.rb`: `initialize(user)`; `K = 5`;
  `total_votes_received` = `Hujah.where(user_id: user.id).sum("agree_count + neutral_count + disagree_count")`;
  `total_arguments_received` = `Hujah.where(parent_id: Hujah.where(user_id: user.id).select(:id)).count`;
  `distributions` = the user's top-level hoojahs mapped to a small Struct/value object (`id, slug, body,
  agree/neutral/disagree counts, total, suppressed? = total < K, and pct helpers`), built from ONE
  `Hujah.where(user_id: user.id, parent_id: nil)` query (no per-hoojah query, no votes/users join).
- [ ] **Step 4: Run → PASS; full suite green. Commit.**

### Task 2.2: AnalyticsController + route + views + navbar
**Files:** modify `config/routes.rb`, `app/views/shared/_navbar.html.erb`; create
`app/controllers/analytics_controller.rb`, `app/views/analytics/show.html.erb`,
`app/views/analytics/_distribution_bar.html.erb`. Test: `spec/requests/analytics_spec.rb`,
`spec/system/analytics_spec.rb`.
- [ ] **Step 1: Route** — `get "/dashboard", to: "analytics#show", as: :dashboard`.
- [ ] **Step 2: Failing request spec** — `spec/requests/analytics_spec.rb`:
```ruby
require 'rails_helper'
RSpec.describe 'Analytics', type: :request do
  it 'requires login' do
    get "/dashboard"; expect(response).to redirect_to(new_user_session_path)
  end
  it 'shows the owner their totals + suppresses low-N splits' do
    user = create(:user)
    create(:hujah, user: user, agree_count: 3, neutral_count: 1, disagree_count: 1, body: "big one")
    create(:hujah, user: user, agree_count: 1, neutral_count: 0, disagree_count: 0, body: "small one")
    sign_in user
    get "/dashboard"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("5").and include("fewer than 5 votes")
  end
end
```
- [ ] **Step 3: Run → FAIL.**
- [ ] **Step 4: Controller** — `app/controllers/analytics_controller.rb`:
```ruby
class AnalyticsController < ApplicationController
  before_action :authenticate_user!
  def show
    skip_authorization
    @analytics = UserAnalytics.new(current_user)
  end
end
```
- [ ] **Step 5: Views** — `analytics/show.html.erb`: totals (votes/arguments received via `_stat`-style
  chips) + a list of `@analytics.distributions` each rendered by `_distribution_bar` (Tailwind width-% divs
  copied from `_vote_bars`' bar markup — agree/neutral/disagree segments + %), showing "fewer than 5 votes"
  when `dist.suppressed?`. Add a "Dashboard" link to `_navbar` (signed-in only, → `dashboard_path`).
- [ ] **Step 6: Run request spec → PASS; full suite green; brakeman 0. Commit.**

---

# Phase 3 — System + gates + docs

### Task 3.1: cuprite system spec + gates + docs
- [ ] **Step 1:** `db:test:prepare`. `spec/system/analytics_spec.rb` (reuse `login_as_system`): a signed-in
  user opens `/dashboard`, sees a distribution bar + totals, and a low-vote hoojah shows the suppressed
  label. Run twice; stabilize with Capybara waits.
- [ ] **Step 2:** `standardrb --fix`; full suite green. brakeman 0; bundler-audit clean.
- [ ] **Step 3:** README + `docs/superpowers/HANDOVER.md` "Slice 5 (Privacy + Analytics MVP) — DONE": Part A
  (new_vote voter-id leak closed + backfill), Part B (owner-only `/dashboard`, zero tables, k=5); note the
  tracked follow-up (public per-hoojah counts already unsuppressed — security 2a) + still-open roadmap
  (Badges/Trending, Block/mute, analytics trends, debate increments).
- [ ] **Step 4: Full suite green; gates clean. Commit.**

## Definition of done
`new_vote` notifications carry no voter identity (+ existing rows scrubbed); owner-only `/dashboard` shows
own aggregates with k=5 suppression, zero new tables, no votes→users join; suite green incl. cuprite;
brakeman 0.

## Deferred
Analytics trends + ranking; Badges/Trending; Block/mute; debate Increments; the tracked public-card
suppression follow-up.
