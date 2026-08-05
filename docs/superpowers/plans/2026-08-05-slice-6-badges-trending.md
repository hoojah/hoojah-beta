# Slice 6: Badges + Trending Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** 4 event-driven achievement badges (profile chips + notification) + a cached trending sidebar.
No background jobs. **Source spec:** `docs/superpowers/specs/2026-08-05-slice-6-badges-trending-design.md`.

## Canonical commands (HANDOVER.md)
- Rails: `mise exec ruby@3.4.9 -- bin/rails <args>`; Specs: `RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec <path>` (iterate `--exclude-pattern "spec/system/**/*"`). `db:test:prepare` after migrations. Gates: brakeman/bundler-audit/standardrb.

Branch `slice-6-badges-trending`. Commit per task, no attribution. **Never create data via `bin/rails runner`
in RAILS_ENV=test.** Baseline `149/0/2` (131 non-system).

---

# Phase 1 — Badges

### Task 1.1: Badge registry + UserBadge model + award + notification enum
**Files:** migration `CreateUserBadges`; `app/models/{badge,user_badge}.rb`; modify `app/models/{user,notification}.rb`.
Test: `spec/models/user_badge_spec.rb`, `spec/factories/user_badges.rb`.
- [ ] **Step 1: Migration** — `user_badges (references user null:false FK, badge_key string null:false, timestamps)`,
  `add_index :user_badges, [:user_id, :badge_key], unique: true`, index user_id. Migrate + `db:test:prepare`.
- [ ] **Step 2:** `Notification` enum append `badge_earned: 11` (no renumber).
- [ ] **Step 3: Failing spec** — `spec/models/user_badge_spec.rb`:
```ruby
require 'rails_helper'
RSpec.describe UserBadge, type: :model do
  let(:u) { create(:user) }
  it 'awards once + notifies once, idempotent' do
    expect { UserBadge.award(u, "first_hoojah") }
      .to change { u.user_badges.count }.by(1)
      .and change { Notification.where(user: u, category: 'badge_earned').count }.by(1)
    expect { UserBadge.award(u, "first_hoojah") }.not_to change { u.user_badges.count }
  end
  it 'rejects an unknown badge_key' do
    expect(UserBadge.new(user: u, badge_key: "nope")).not_to be_valid
  end
  it 'User#badges is nil-safe on a stale registry key' do
    u.user_badges.create!(badge_key: "first_hoojah")
    UserBadge.where(user: u).update_all(badge_key: "removed_badge") # simulate a renamed/removed key
    expect { u.badges }.not_to raise_error
    expect(u.badges).to eq([])
  end
end
```
- [ ] **Step 4: Run → FAIL.**
- [ ] **Step 5: Implement** — `app/models/badge.rb` (`Badge::REGISTRY` with the 4 keys + name/description/icon);
  `app/models/user_badge.rb` (`belongs_to :user`, `validates :badge_key, inclusion: { in: Badge::REGISTRY.keys }`,
  `self.award(user, key)` per spec §1 — `exists?` guard, `create!`, notify, `rescue RecordNotUnique`).
  `User`: `has_many :user_badges, dependent: :destroy`; `def badges = user_badges.filter_map { |ub| Badge::REGISTRY[ub.badge_key] }`.
- [ ] **Step 6: Run → PASS; full suite green. Commit.**

### Task 1.2: Award hooks + notification card + serializer + profile chips
**Files:** modify `app/models/{hujah,follow,debate}.rb`, `app/views/notifications/_notification_card.html.erb`,
`app/serializers/notification_serializer.rb`, `app/views/users/_profile_header.html.erb`. Test:
`spec/models/badge_awards_spec.rb`.
- [ ] **Step 1: Failing spec** — `spec/models/badge_awards_spec.rb`:
```ruby
require 'rails_helper'
RSpec.describe 'Badge awards', type: :model do
  it 'first_hoojah on a top-level create; first_argument on a child' do
    u = create(:user)
    top = create(:hujah, user: u)
    expect(u.user_badges.pluck(:badge_key)).to include("first_hoojah")
    child_author = create(:user)
    create(:hujah, user: child_author, parent: top)
    expect(child_author.user_badges.pluck(:badge_key)).to include("first_argument")
  end
  it 'first_follower on follow; first_debate on conclude (both participants)' do
    a = create(:user); b = create(:user)
    a.active_follows.create!(followed: b)
    expect(b.user_badges.pluck(:badge_key)).to include("first_follower")
    hujah = create(:hujah); arg = create(:hujah, parent: hujah, user: b, vote: 3)
    d = a.challenged_debates.create!(hujah: hujah, opponent: b, challenger_stance: 1, opponent_stance: 3)
    d.accept!(by: b); d.conclude!(by: a)
    expect(a.user_badges.pluck(:badge_key)).to include("first_debate")
    expect(b.user_badges.pluck(:badge_key)).to include("first_debate")
  end
  it 'casting a vote still commits the vote (no milestone check poisons the tx)' do
    owner = create(:user); voter = create(:user); h = create(:hujah, user: owner)
    expect { h.cast_vote(by: voter, choice: 1) }.to change { h.reload.agree_count }.by(1)
  end
end
```
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** — add the `UserBadge.award(...)` calls to `Hujah after_create_commit`,
  `Follow after_create_commit`, `Debate#conclude!` (after the status update) per spec §1. **Do NOT touch
  `cast_vote`'s transaction.** `_notification_card`: `badge_earned` branch (Lucide `award` + registry name)
  + a mark-read `button_to`. `NotificationSerializer`: computed `badge` attribute (`{key,name,icon}` from
  the registry when `category == 'badge_earned'`). `_profile_header`: render `user.badges` as Lucide chips
  (public).
- [ ] **Step 4: Run → PASS; full suite green; brakeman 0. Commit.**

---

# Phase 2 — Trending

### Task 2.1: Hujah.trending + TrendingController + sidebar
**Files:** modify `app/models/hujah.rb`, `config/routes.rb`, `app/views/hujahs/index.html.erb`,
`app/views/shared/_navbar.html.erb`; create `app/controllers/trending_controller.rb`,
`app/views/trending/{index,_trending}.html.erb`. Test: `spec/models/hujah_trending_spec.rb`,
`spec/requests/trending_spec.rb`.
- [ ] **Step 1: Failing model spec** — `spec/models/hujah_trending_spec.rb`:
```ruby
require 'rails_helper'
RSpec.describe 'Hujah.trending', type: :model do
  before { Rails.cache.clear }
  it 'orders recent higher-activity hoojahs by score' do
    hot = create(:hujah, agree_count: 50, neutral_count: 10, disagree_count: 10)
    cold = create(:hujah, agree_count: 1)
    ids = Hujah.trending.map(&:id)
    expect(ids).to include(hot.id)
    expect(ids.index(hot.id)).to be < (ids.index(cold.id) || 999)
  end
  it 'caches the id list (second call does not recompute)' do
    create(:hujah, agree_count: 5)
    Hujah.trending
    expect(Rails.cache.exist?("trending:v1")).to be(true)
  end
end
```
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** — `Hujah.trending` per spec §2 (`Rails.cache.fetch("trending:v1", expires_in:
  15.minutes)` computing HN gravity on totals over `parent_id: nil` + `updated_at > 48.hours.ago`
  candidates, caching ordered ids, reloading `where(id:).includes(:user)` in cache order).
- [ ] **Step 4: Run → PASS.**
- [ ] **Step 5: Controller + views + route** — `get "/trending", to: "trending#index"`;
  `TrendingController#index` (`skip_authorization`, `@hujahs = Hujah.trending`); `_trending` partial (compact
  links + empty state); `trending/index.html.erb` (standalone page). `hujahs/index`: wrap the existing feed
  column in a minimal `lg` grid with an `<aside class="hidden lg:block">` holding
  `turbo_frame_tag "trending", src: trending_path, loading: :lazy`. Nav link to `/trending`. Request spec
  `spec/requests/trending_spec.rb`: `/trending` is public (no login) + renders (incl. empty state).
- [ ] **Step 6: Run → PASS; full suite green. Commit.**

---

# Phase 3 — System + gates + docs

### Task 3.1: cuprite + gates + docs
- [ ] **Step 1:** `db:test:prepare`. `spec/system/{badges,trending}_spec.rb`: a badge chip shows on a profile
  after the user earns first_hoojah; the feed shows the trending sidebar frame on a wide viewport (reuse
  `login_as_system`; set a wide `viewport`). Run twice; stabilize with Capybara waits.
- [ ] **Step 2:** `standardrb --fix`; full suite green. brakeman 0; bundler-audit clean.
- [ ] **Step 3:** README + `docs/superpowers/HANDOVER.md` "Slice 6 (Badges + Trending) — DONE": 4 badges +
  trending; still-open (vote-milestone/debate_won badges, Block/mute Slice 7, debate increments Slice 8).
- [ ] **Step 4: Full suite green; gates clean. Commit.**

## Definition of done
4 event-driven badges award idempotently + notify + show on profiles; `cast_vote` unaffected; trending
sidebar/page cached + public; suite green incl. cuprite; brakeman 0.

## Deferred
Vote-milestone + debate_won badges; recurring-job trending; Block/mute (Slice 7); debate increments (Slice 8).
