# Slice 7: Block Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** Bidirectional Block — enforced at the Pundit policy layer (reject reply/follow/challenge) + content
filters (feeds, reply threads, trending) via one `User#hidden_user_ids` helper.
**Source spec:** `docs/superpowers/specs/2026-08-05-slice-7-block-design.md` (read first).

## Canonical commands (HANDOVER.md)
- Rails: `mise exec ruby@3.4.9 -- bin/rails <args>`; Specs: `RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec <path>` (iterate `--exclude-pattern "spec/system/**/*"`). `db:test:prepare` after migrations. Gates: brakeman/bundler-audit/standardrb.

Branch `slice-7-block`. Commit per task, no attribution. **Never create data via `bin/rails runner` in
RAILS_ENV=test.** Baseline `161/0/2` (149 non-system).

---

# Phase 1 — Block model + policy + controller

### Task 1.1: Block model + User assoc + hidden_user_ids
**Files:** migration `CreateBlocks`; `app/models/block.rb`; modify `app/models/user.rb`. Test:
`spec/models/block_spec.rb`, `spec/factories/blocks.rb`.
- [ ] **Step 1: Migration** — `blocks (references blocker null:false FK users, references blocked null:false
  FK users, timestamps)`, `add_index [:blocker_id,:blocked_id] unique`, index blocked_id,
  `add_check_constraint :blocks, "blocker_id <> blocked_id", name: "no_self_block"`. Migrate + `db:test:prepare`.
- [ ] **Step 2: Failing spec** — `spec/models/block_spec.rb`: self-block invalid; unique; `hidden_user_ids`
  bidirectional (A.blocks_made B → B ∈ A.hidden AND A ∈ B.hidden).
- [ ] **Step 3: Implement** — `Block` (belongs_to blocker/blocked class_name User, uniqueness scope,
  not_self validation). `User`: `has_many :blocks_made, class_name: "Block", foreign_key: :blocker_id,
  dependent: :destroy`; `has_many :blocks_received, class_name: "Block", foreign_key: :blocked_id, dependent:
  :destroy`; the memoized `hidden_user_ids` per spec §1. Update the stale comment at `hujah.rb:16-17`.
- [ ] **Step 4: Run → PASS; full suite green. Commit.**

### Task 1.2: BlocksController + BlockPolicy + routes + reciprocal-follow removal + throttle
**Files:** `config/routes.rb`, `config/initializers/rack_attack.rb`, `app/controllers/blocks_controller.rb`,
`app/policies/block_policy.rb`, `app/views/blocks/index.html.erb`, `app/views/blocks/{create,destroy}.turbo_stream.erb`,
`app/views/users/_follow_button.html.erb` (Block/Unblock states). Test: `spec/requests/block_spec.rb`,
`spec/policies/block_policy_spec.rb`.
- [ ] **Step 1: Routes** — `post/delete "/u/:username/block"` (block_user/unblock_user), `get "/blocks"`.
- [ ] **Step 2: Failing specs** — `block_policy_spec` (create? user present; destroy? owner);
  `block_spec` request: unauth block → login; block creates + **removes reciprocal follows both ways**;
  double-block idempotent (no 500); unblock; `#destroy` on non-existent block no 500.
- [ ] **Step 3: Implement** — `BlockPolicy` (`create? = user.present?`, `destroy? = record.blocker_id ==
  user.id`). `BlocksController` per spec §4: `create` (`authorize Block.new(...), :create?`; transaction →
  `find_or_create_by` rescue RecordNotUnique + `Follow.where(follower: [me,@target], followed:
  [me,@target]).delete_all`; Turbo-Stream); `destroy` (mirror FollowsController — `authorize @block,
  :destroy? if @block` else `skip_authorization`); `index` (`skip_authorization`). rack-attack `block/user`
  throttle. `_follow_button` gains Block/Unblock states (Unblock when blocked-by-me; no Follow for a hidden
  pair).
- [ ] **Step 4: Run → PASS; full suite green. Commit.**

---

# Phase 2 — Policy rejections + content filters

### Task 2.1: Policy-layer interaction rejections
**Files:** modify `app/policies/{hujah,follow,debate}_policy.rb`, `app/controllers/hujahs_controller.rb`.
Test: `spec/requests/block_enforcement_spec.rb`.
- [ ] **Step 1: Failing spec** — `spec/requests/block_enforcement_spec.rb`: after A blocks B —
  B replying to A's hoojah → 403 + no `new_hoojah_response` notification; B following A → denied + no
  `new_follower`; B challenging A to a debate → denied + no `debate_challenge`; a mention of A by B → no
  `mention` notification (Task 2.2 also covers mention). A `new_vote` by B on A's hoojah IS still created.
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement:**
  - `HujahPolicy#create?` → `user.present? && (record.parent_id.nil? || !user.hidden_user_ids.include?(record.parent&.user_id))`.
  - **`HujahsController#create`**: build `@hujah = current_user.hujahs.new(compose_params)` (with parent_id)
    BEFORE authorization, then `authorize @hujah` (instance, not `authorize Hujah`) so the policy can read
    `record.parent.user_id`. Keep the existing missing-parent 404 handling.
  - `FollowPolicy#create?` → `user.present? && !user.hidden_user_ids.include?(record.followed_id)`.
  - `DebatePolicy#create?` → `user.present? && !user.hidden_user_ids.include?(record.opponent_id)`.
- [ ] **Step 4: Run → PASS; full suite green (existing compose/follow/debate specs still pass for
  non-blocked pairs). Commit.**

### Task 2.2: Content filters (feeds, replies, trending, mentions)
**Files:** modify `app/models/hujah.rb` (`timeline_for`, `notify_mentions`),
`app/controllers/{hujahs,trending}_controller.rb`. Test: `spec/requests/block_visibility_spec.rb`.
- [ ] **Step 1: Failing spec** — `block_visibility_spec`: after A blocks B — A's global feed + following
  feed + B's hoojah's `@children` on A's show page exclude B's content and vice versa; a stranger sees
  both; A's `/trending` excludes B's hoojah; anonymous `/` + `/trending` unfiltered; a mention of A by B
  creates no `mention` notification.
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** — `timeline_for` append `.where.not(user_id: user.hidden_user_ids)`; global feed
  branch (`HujahsController#index`) add `.where.not(user_id: current_user.hidden_user_ids)` when signed in;
  `HujahsController#show` filter `@children` by `current_user.hidden_user_ids` when signed in;
  `TrendingController#index` reject per viewer; `notify_mentions` add `.where.not(id: author.hidden_user_ids)`.
- [ ] **Step 4: Run → PASS; full suite green; brakeman 0. Commit.**

---

# Phase 3 — System + gates + docs

### Task 3.1: cuprite + gates + docs
- [ ] **Step 1:** `db:test:prepare`. `spec/system/block_spec.rb` (reuse `login_as_system`): block from a
  profile → Follow button becomes Unblock; the blocked user's hoojah disappears from the feed on reload.
  Run twice; stabilize with Capybara waits.
- [ ] **Step 2:** `standardrb --fix`; full suite green. brakeman 0; bundler-audit clean.
- [ ] **Step 3:** README + `docs/superpowers/HANDOVER.md` "Slice 7 (Block) — DONE": bidirectional block
  (policy rejections + content filters), reciprocal-follow removal; documented direct-URL boundary +
  deferred `Api::V1` filters; still-open (Slice 7b private accounts + mute; Slice 8 debate increments).
- [ ] **Step 4: Full suite green; gates clean. Commit.**

## Definition of done
Bidirectional block: reply/follow/challenge rejected at the policy layer (no content, no notification);
feeds + reply threads + trending exclude blocked pairs; blocking removes reciprocal follows; block/unblock
UI + list; suite green incl. cuprite; brakeman 0.

## Deferred
Mute; private accounts (Slice 7b); Api::V1 block filters; debate increments (Slice 8).
