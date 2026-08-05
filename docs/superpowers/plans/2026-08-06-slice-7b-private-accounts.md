# Slice 7b: Private Accounts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** `users.private` + follow request→approve + `visible_to?` gating of every content surface.
**Source spec:** `docs/superpowers/specs/2026-08-06-slice-7b-private-accounts-design.md` — READ IT (the
"Visibility gates" list is the security-critical checklist; each gate needs a test).

## Canonical commands (HANDOVER.md)
- Rails: `mise exec ruby@3.4.9 -- bin/rails <args>`; Specs: `RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec <path>` (iterate `--exclude-pattern "spec/system/**/*"`). `db:test:prepare` after migrations. Gates: brakeman/bundler-audit/standardrb.

Branch `slice-7b-private`. Commit per task, no attribution. **Never create data via `bin/rails runner` in
RAILS_ENV=test.** Baseline `185/0/2` (163 non-system).

---

# Phase 1 — Schema + models (private, follow status, visible_to?)

### Task 1.1: Migrations + Follow status + accepted-only scopes + visible_to?
**Files:** migrations (add `users.private`, `follows.status`, backfill); modify `app/models/{user,follow,hujah,notification}.rb`.
Test: `spec/models/visibility_spec.rb`.
- [ ] **Step 1: Migrations** — `add_column :users, :private, :boolean, default: false, null: false` (+ index);
  `add_column :follows, :status, :integer, default: 0, null: false`; a data migration
  `Follow.update_all(status: 1)` (backfill existing → accepted). Migrate + `db:test:prepare`.
- [ ] **Step 2:** `Notification` enum append `follow_request: 12, follow_accepted: 13`.
- [ ] **Step 3: Failing spec** — `spec/models/visibility_spec.rb`:
```ruby
require 'rails_helper'
RSpec.describe 'Visibility', type: :model do
  let(:owner) { create(:user, private: true) }
  let(:follower) { create(:user) }; let(:stranger) { create(:user) }
  before { follower.active_follows.create!(followed: owner, status: :accepted) }
  it 'visible_to? — private: self + accepted follower only' do
    expect(owner.visible_to?(owner)).to be(true)
    expect(owner.visible_to?(follower)).to be(true)
    expect(owner.visible_to?(stranger)).to be(false)
    expect(owner.visible_to?(nil)).to be(false)
    expect(create(:user).visible_to?(stranger)).to be(true) # public
  end
  it 'pending requester is NOT visible' do
    req = create(:user); req.active_follows.create!(followed: owner, status: :pending)
    expect(owner.visible_to?(req)).to be(false)
  end
  it 'following/followers count accepted only' do
    p = create(:user); p.active_follows.create!(followed: owner, status: :pending)
    expect(owner.followers).to include(follower)
    expect(owner.followers).not_to include(p)
  end
end
```
- [ ] **Step 4: Run → FAIL.**
- [ ] **Step 5: Implement** — `Follow`: `enum :status, { pending: 0, accepted: 1 }`, scope `accepted`.
  `User`: `private?` (generated); rewire `has_many :following, -> { where(follows: { status: :accepted }) },
  through: :active_follows, source: :followed` (+ passive/`followers`); `visible_to?`/`accepted_follower?`
  per spec. `Hujah`: `def visible_to?(v) = user.visible_to?(v)`.
- [ ] **Step 6: Run → PASS; full suite green (existing follow specs — confirm counts still work). Commit.**

### Task 1.2: Follow-flow notifications + badge gating (model)
**Files:** modify `app/models/follow.rb`. Test: `spec/models/follow_flow_spec.rb`.
- [ ] **Step 1: Failing spec** — public target → accepted + `new_follower` + `first_follower` badge;
  private target → pending + `follow_request` (NO new_follower, NO badge); status pending→accepted (update)
  → `follow_accepted` + `new_follower` + badge.
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** — `Follow`: replace the unconditional `after_create_commit :notify_followed`
  with: `after_create_commit` → branch `accepted?` (notify_followed `new_follower` + `UserBadge.award(followed,
  "first_follower")`) vs `pending?` (`Notification.create!(user: followed, category: :follow_request,
  subject_user_id: follower_id)`); `after_update_commit :notify_accepted, if: -> { saved_change_to_status? &&
  accepted? }` → `follow_accepted` to follower + `new_follower` + badge. (The badge award must NOT fire on
  pending — the v1 bug.)
- [ ] **Step 4: Run → PASS; full suite green. Commit.**

---

# Phase 2 — Follow request controller + button + cards

### Task 2.1: FollowsController pending + FollowRequestsController + policy + button
**Files:** modify `config/routes.rb`, `app/controllers/follows_controller.rb`, `app/views/users/_follow_button.html.erb`,
`app/views/notifications/_notification_card.html.erb`; create `app/controllers/follow_requests_controller.rb`,
`app/policies/follow_request_policy.rb`. Test: `spec/requests/follow_request_spec.rb`, `spec/policies/follow_request_policy_spec.rb`.
- [ ] **Step 1: Routes** — `patch/delete "/follow_requests/:id", to: "follow_requests#update"/"#destroy"` (NO
  index — deferred).
- [ ] **Step 2: Failing specs** — `follow_request_spec`: following a private user → pending (button shows
  "Requested"); the followed user accepts (`PATCH`) → accepted + notifications; declines (`DELETE`) →
  removed; a NON-followed user can't accept/decline (403). `follow_request_policy_spec`.
- [ ] **Step 3: Implement** — `FollowsController#create`: `find_or_initialize_by(followed: @target)` + set
  status per spec (`@target.private? ? :pending : :accepted` if new_record) + save (rescue RecordNotUnique).
  `FollowRequestsController` (`authenticate_user!`; `set_follow` = `Follow.find(params[:id])`;
  `authorize @follow, :update?`/`:destroy?`; update → accept, destroy → decline). `FollowRequestPolicy`
  (`update?`/`destroy? = record.followed_id == user.id`). `_follow_button` 3-state (Following / Requested via
  `active_follows.pending.exists?` / Follow). `_notification_card`: `follow_request` branch with
  accept/decline `button_to`s + `follow_accepted` branch.
- [ ] **Step 4: Run → PASS; full suite green. Commit.**

---

# Phase 3 — The visibility gates (security-critical; one test per gate)

### Task 3.1: Content gates
**Files:** modify `app/controllers/{hujahs,users,trending}_controller.rb`, `app/models/{hujah,user}.rb`,
`app/policies/{hujah,debate}_policy.rb`, `app/views/notifications/_notification_card.html.erb`,
`app/serializers/notification_serializer.rb`, `app/controllers/api/v1/{hujahs,users}_controller.rb`,
`app/views/users/{show or _profile_header}` (gated view). Test: `spec/requests/private_visibility_spec.rb`.
- [ ] **Step 1: Failing spec** — `spec/requests/private_visibility_spec.rb`, one example PER gate (spec's
  Testing "Every gate" list): global feed excludes private for anon+stranger; accepted follower's Following
  feed includes; gated profile (no hoojah list) for stranger; hoojah show 403/redirect for non-follower;
  `@children` hides a private replier from anon+stranger, shows to accepted follower; **followers list
  gated**; **concluded debate transcript hidden** from a non-follower of a private participant; **notification
  body** of a private hoojah not rendered to a stranger; **`Api::V1` hoojah index/show + user show** gate a
  private author; `HujahPolicy#create?` rejects a reply to an unseen private parent. Public unchanged.
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement each gate per spec §"Visibility gates"** (1–11):
  1. Global feed else-branch `.joins(:user).where(users: { private: false })` **unconditional**.
  2. (following feed automatic via accepted-only ids).
  3. `Hujah.trending` candidates exclude private; `User after_update_commit { Rails.cache.delete("trending:v1")
     if saved_change_to_private? }`.
  4. `UsersController#show` gated-view branch (`!@user.visible_to?(current_user)` → limited fields, no hoojahs).
  5. `HujahsController#show` → `authorize @hujah`; `HujahPolicy#show? = record.user.visible_to?(user)`.
  6. `@children` unconditional SQL visibility predicate (spec §6).
  7. `UsersController#followers`/`#following` gated when `!@user.visible_to?(current_user)`.
  8. `DebatePolicy#show?` + `Scope` gate on both participants' visibility.
  9. `_notification_card` hoojah branch + `NotificationSerializer#hujah` guarded on `visible_to?`.
  10. `HujahPolicy#create?` += `record.parent.visible_to?(user)`.
  11. `Api::V1::HujahsController#index/#show` + `Api::V1::UsersController#show` gate via `visible_to?`.
- [ ] **Step 4: Run → PASS; full suite green; brakeman 0. Commit.**

### Task 3.2: Private toggle
**Files:** modify `app/controllers/users_controller.rb` (or the registrations/profile update path),
`app/views/users/_profile_edit.html.erb`. Test: extend `spec/requests/profile_spec.rb`.
- [ ] **Step 1: Failing spec** — owner toggles `private` on; toggling back to public auto-accepts pending
  requests (`update_all`).
- [ ] **Step 2:** add `:private` to the profile `user_params`; a checkbox in `_profile_edit`; on
  private→public (detect the change) `current_user.passive_follows.pending.update_all(status: :accepted)`.
- [ ] **Step 3: Run → PASS; full suite green. Commit.**

---

# Phase 4 — System + gates + docs

### Task 4.1: cuprite + gates + docs
- [ ] **Step 1:** `db:test:prepare`. `spec/system/private_spec.rb` (reuse `login_as_system`): a user makes
  their account private → a stranger sees the gated profile; the owner accepts a follow request → the
  requester then sees the content. Run twice; stabilize with waits.
- [ ] **Step 2:** `standardrb --fix`; full suite green. brakeman 0; bundler-audit clean.
- [ ] **Step 3:** README + `docs/superpowers/HANDOVER.md` "Slice 7b (Private Accounts) — DONE": private flag +
  request/approve + all gates (list them); documented deferrals (`/follow_requests` inbox page, full Api::V1
  parity); still-open (Slice 8 debate increments; Project 3).
- [ ] **Step 4: Full suite green; gates clean. Commit.**

## Definition of done
Private accounts: request→approve follow, every content surface (feeds, trending+cache, profile, hoojah
show, @children, follower lists, debate transcripts, notification bodies, gated Api::V1 read endpoints)
gates a private author via `visible_to?`; 3-state button; toggle; suite green incl. cuprite; brakeman 0.

## Deferred
`/follow_requests` inbox page; full Api::V1 parity; then debate Increments (Slice 8), Project 3.
