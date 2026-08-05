# Slice 3: Social Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** Follow/unfollow (public) + a Following feed + @mentions, on the shipped Hotwire app.

**Architecture:** A `Follow` join (owner-forced, self-follow blocked at model+DB), Pundit `FollowPolicy`,
Turbo-Stream follow button; a `Hujah#timeline_for` scope branched into the existing feed; @mentions parsed
inline (create-only, idempotent) with a **tokenize-before-format** render so the mention substitution never
lands inside auto_link'd HTML.

**Tech Stack:** Rails 8.1.3.1 / Ruby 3.4.9 (mise), Devise 5.0.4, Pundit, Turbo, Notification model, rack-attack.
**Source spec:** `docs/superpowers/specs/2026-08-05-slice-3-social-foundation-design.md` (read first).

## Canonical commands (from HANDOVER.md)
- Bundle: `source .mise-build-env.sh && mise exec ruby@3.4.9 -- bundle install`
- Rails: `mise exec ruby@3.4.9 -- bin/rails <args>`; Specs: `RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec <path>`
- Test DB: `mise exec ruby@3.4.9 -- bin/rails db:test:prepare`; iterate with `--exclude-pattern "spec/system/**/*"`.
- Gates: `... brakeman -q`, `... bundler-audit check --update`, `... standardrb`.

Branch `slice-3-social-foundation`. Commit per task, no Claude/Anthropic attribution. **Never create data via
`bin/rails runner` in RAILS_ENV=test** (transactional fixtures, no DatabaseCleaner). Baseline: `95/0/2`.

---

# Phase 1 — Follow model + policy + notification

### Task 1.1: Follow model + migration + User associations
**Files:** migration; `app/models/follow.rb`; modify `app/models/user.rb`, `app/models/notification.rb`.
Test: `spec/models/follow_spec.rb`, `spec/factories/follows.rb`.

- [ ] **Step 1: Migration** — `mise exec ruby@3.4.9 -- bin/rails g migration CreateFollows`:
```ruby
class CreateFollows < ActiveRecord::Migration[8.1]
  def change
    create_table :follows do |t|
      t.references :follower, null: false, foreign_key: { to_table: :users }
      t.references :followed, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :follows, [:follower_id, :followed_id], unique: true
    add_check_constraint :follows, "follower_id <> followed_id", name: "no_self_follow"
  end
end
```
Migrate + `db:test:prepare`.

- [ ] **Step 2: Failing spec** — `spec/models/follow_spec.rb`:
```ruby
require 'rails_helper'
RSpec.describe Follow, type: :model do
  let(:a) { create(:user) }; let(:b) { create(:user) }
  it 'is valid between two different users and notifies the followed' do
    expect { a.active_follows.create!(followed: b) }
      .to change { Notification.where(user: b, category: 'new_follower').count }.by(1)
  end
  it 'rejects self-follow and duplicates' do
    expect(Follow.new(follower: a, followed: a)).not_to be_valid
    a.active_follows.create!(followed: b)
    expect(Follow.new(follower: a, followed: b)).not_to be_valid
  end
end
```
Add `spec/factories/follows.rb` (`association :follower, factory: :user; association :followed, factory: :user`).

- [ ] **Step 3: Run → FAIL.**

- [ ] **Step 4: Model** — `app/models/follow.rb` per spec §1 (belongs_to follower/followed, uniqueness scope,
  `not_self` validation, `after_create_commit :notify_followed`). `User`: add
  `has_many :active_follows, class_name: "Follow", foreign_key: :follower_id, dependent: :destroy`;
  `has_many :following, through: :active_follows, source: :followed`;
  `has_many :passive_follows, class_name: "Follow", foreign_key: :followed_id, dependent: :destroy`;
  `has_many :followers, through: :passive_follows, source: :follower`. `Notification`: extend the enum with
  `mention: 5, new_follower: 6` (append; do NOT renumber).

- [ ] **Step 5: Run → PASS; full suite green. Commit.**

### Task 1.2: FollowPolicy
**Files:** `app/policies/follow_policy.rb`; `spec/policies/follow_policy_spec.rb`.
- [ ] **Step 1: Failing spec** — create? true for a present user / false for nil; destroy? true only for the
  follow's follower.
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3:** `FollowPolicy < ApplicationPolicy`: `def create? = user.present?`;
  `def destroy? = user.present? && record.follower_id == user.id`.
- [ ] **Step 4: Run → PASS. Commit.**

---

# Phase 2 — Follow controller (Turbo) + throttle

### Task 2.1: FollowsController + routes + Turbo button + rack-attack
**Files:** modify `config/routes.rb`, `config/initializers/rack_attack.rb`; create
`app/controllers/follows_controller.rb`, `app/views/follows/{create,destroy}.turbo_stream.erb`,
`app/views/users/_follow_button.html.erb`, `app/views/users/_follower_count.html.erb`; modify
`app/views/users/_profile_header.html.erb`. Test: `spec/requests/follow_spec.rb`.

- [ ] **Step 1: Routes** —
```ruby
post   "/u/:username/follow", to: "follows#create",  as: :follow_user
delete "/u/:username/follow", to: "follows#destroy", as: :unfollow_user
```
(Main `routes.rb`, NOT `Api::V1` — CSRF must stay on.)

- [ ] **Step 2: Failing request spec** — `spec/requests/follow_spec.rb`:
```ruby
require 'rails_helper'
RSpec.describe 'Follows', type: :request do
  let(:me) { create(:user) }; let(:target) { create(:user, username: "target") }
  it 'requires login' do
    post "/u/target/follow"
    expect(response).to redirect_to(new_user_session_path)
  end
  it 'follows via turbo_stream and is idempotent' do
    sign_in me
    post "/u/target/follow", headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
    expect(me.following).to include(target)
    expect(response.media_type).to eq('text/vnd.turbo-stream.html')
    post "/u/target/follow", headers: { 'Accept' => 'text/vnd.turbo-stream.html' } # double
    expect(me.following.where(id: target.id).count).to eq(1)   # no dup, no 500
  end
  it 'unfollows' do
    sign_in me; me.active_follows.create!(followed: target)
    delete "/u/target/follow", headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
    expect(me.reload.following).not_to include(target)
  end
end
```

- [ ] **Step 3: Run → FAIL.**

- [ ] **Step 4: Controller** — `app/controllers/follows_controller.rb`:
```ruby
class FollowsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_target

  def create
    authorize Follow.new(follower: current_user, followed: @target), :create?
    current_user.active_follows.find_or_create_by(followed: @target)
    render_button
  rescue ActiveRecord::RecordNotUnique
    render_button
  end

  def destroy
    @follow = current_user.active_follows.find_by(followed: @target)
    authorize @follow, :destroy? if @follow
    skip_authorization if @follow.nil?
    @follow&.destroy
    render_button
  end

  private

  def set_target = @target = User.find_by!(username: params[:username])
  def render_button
    respond_to do |f|
      f.turbo_stream # create/destroy.turbo_stream.erb both render the same two replaces
      f.html { redirect_to profile_path(@target.username), status: :see_other }
    end
  end
end
```

- [ ] **Step 5: Views + throttle** — both `create.turbo_stream.erb` and `destroy.turbo_stream.erb`:
  `turbo_stream.replace dom_id(@target, :follow_button)` (renders `_follow_button` — shows Follow or
  Following based on `current_user&.following&.include?(@target)`) + `turbo_stream.replace
  dom_id(@target, :follower_count)`. `_follow_button` uses `button_to follow_user_path` /
  `unfollow_user_path(method: :delete)`. Wire both into `_profile_header` (button + count chip, each
  wrapped in its `dom_id`). rack-attack: add
  `throttle("follow/user", limit: 20, period: 1.minute) { |r| r.env["warden"]&.user&.id if r.path.match?(%r{\A/u/[^/]+/follow\z}) && (r.post? || r.delete?) }`.

- [ ] **Step 6: Run → PASS; full suite green. Commit.**

### Task 2.2: Followers / following lists
**Files:** modify `config/routes.rb`, `app/controllers/users_controller.rb`; create
`app/views/users/{followers,following}.html.erb`. Test: extend `spec/requests/profile_spec.rb`.
- [ ] **Step 1: Routes** — `get "/u/:username/followers" => "users#followers"`, `.../following => "users#following"`.
- [ ] **Step 2: Failing spec** — signed-out can view target's followers/following (public), lists the users.
- [ ] **Step 3: Actions** — `followers`/`following` load `@user = User.find_by!(username:)`, `skip_authorization`,
  render the list (reuse a small user-row partial). Counts on the profile header use `@user.followers.size`
  / `@user.following.size`.
- [ ] **Step 4: Run → PASS. Commit.**

---

# Phase 3 — Following feed

### Task 3.1: `Hujah#timeline_for` + index filter branch
**Files:** modify `app/models/hujah.rb`, `app/controllers/hujahs_controller.rb`,
`app/views/hujahs/index.html.erb` (+ `_feed_tabs`, `_load_more`). Test: `spec/requests/timeline_spec.rb`.

- [ ] **Step 1: Failing spec** — `spec/requests/timeline_spec.rb`:
```ruby
require 'rails_helper'
RSpec.describe 'Following feed', type: :request do
  let(:me) { create(:user) }; let(:followed) { create(:user) }; let(:stranger) { create(:user) }
  before do
    me.active_follows.create!(followed: followed)
    @mine = create(:hujah, user: me); @theirs = create(:hujah, user: followed)
    @other = create(:hujah, user: stranger)
  end
  it 'shows own + followed, not strangers, when signed in' do
    sign_in me
    get "/", params: { filter: "following" }
    expect(response.body).to include(@mine.slug).and include(@theirs.slug)
    expect(response.body).not_to include(@other.slug)
  end
  it 'falls back to the global feed for an anonymous following request (no 500)' do
    get "/", params: { filter: "following" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(@other.slug)   # global feed
  end
end
```
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** — `Hujah` scope `timeline_for` (spec §4: `where(parent_id: nil).where(user_id:
  user.following_ids + [user.id])`). `HujahsController#index`:
```ruby
base = if params[:filter] == "following" && user_signed_in?
  Hujah.timeline_for(current_user).includes(:user).order(updated_at: :desc)
else
  Hujah.where(parent_id: nil).includes(:user).order(updated_at: :desc)
end
@pagy, @hujahs = pagy(:countless, base)
```
- [ ] **Step 4: Views** — `_feed_tabs` (Everyone | Following links; Following only when `user_signed_in?`);
  `index.html.erb` renders tabs + empty-state when the following feed is empty; `_load_more` carries
  `filter: params[:filter]` in its `page` link.
- [ ] **Step 5: Run → PASS; full suite green. Commit.**

---

# Phase 4 — @mentions

### Task 4.1: `format_body` tokenized mention rendering (injection-safe)
**Files:** modify `app/helpers/hujahs_helper.rb`, `app/models/hujah.rb` (add `MENTION_RE`). Test:
`spec/helpers/hujahs_helper_spec.rb`.
- [ ] **Step 1: Failing spec** — extend `spec/helpers/hujahs_helper_spec.rb`:
```ruby
it 'links a real @handle to the profile' do
  expect(helper.format_body("hi @rudz")).to include('href="/u/rudz"')
end
it 'does NOT break an email or @-URL (no spliced quote, no truncated href)' do
  out = helper.format_body("ping foo@bar.com and https://medium.com/@who")
  expect(out).to include('mailto:foo@bar.com')          # email anchor intact
  expect(out).to include('https://medium.com/@who')     # URL intact
  expect(out).not_to include('href="/u/bar"')           # email @ not mentioned
  expect(out).not_to include('href="/u/who"')           # URL @ not mentioned
end
it 'escapes hostile handles (no live tag)' do
  expect(helper.format_body('@evil"><script>')).not_to include('<script>')
end
```
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** — add `MENTION_RE = /(?<!\w)@([a-zA-Z0-9_]+)/` on `Hujah`; rewrite `format_body`
  per spec §6 (tokenize on raw text with `"#{i}"`, `simple_format` + `auto_link`, then
  `gsub(/(\d+)/)` → the `ERB::Util`-escaped anchor).
- [ ] **Step 4: Run → PASS. Commit.**

### Task 4.2: `Hujah#notify_mentions` (inline, create-only, idempotent)
**Files:** modify `app/models/hujah.rb`. Test: `spec/models/hujah_mentions_spec.rb`.
- [ ] **Step 1: Failing spec** — `spec/models/hujah_mentions_spec.rb`:
```ruby
require 'rails_helper'
RSpec.describe 'Hujah mentions', type: :model do
  let(:author) { create(:user) }; let(:m1) { create(:user, username: "mentioned1") }
  it 'notifies each existing mentioned user once, skips self + unknown, caps at 10' do
    create(:user, username: "self") # ensure username uniqueness helper if needed
    expect {
      author.hujahs.create!(body: "hey @mentioned1 @mentioned1 @nobody @#{author.username}")
    }.to change { Notification.where(user: m1, category: 'mention').count }.by(1)
    expect(Notification.where(category: 'mention', subject_user_id: author.id).count).to eq(1)
  end
end
```
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** — `after_create_commit :notify_mentions` + the private method per spec §6
  (`scan(MENTION_RE).flatten.uniq.first(10)`, `User.where(username:).where.not(id: user_id)`, `exists?`
  idempotency guard, `Notification.create!` category `:mention`). Add the `mention`/`new_follower` branches
  + Lucide icons (`at-sign`/`user-plus`) to `app/views/notifications/_notification_card.html.erb`.
- [ ] **Step 4: Run → PASS; full suite green. Commit.**

---

# Phase 5 — System tests, gates, docs

### Task 5.1: cuprite system specs
**Files:** `spec/system/{follow,timeline,mention}_spec.rb`.
- [ ] **Step 1:** `db:test:prepare` first. Follow: visit a profile signed in, click Follow → button flips to
  Following + count increments without reload. Timeline: Following tab shows own+followed. Mention: a hoojah
  body with `@user` renders a link to `/u/user`. (Reuse the Slice 2 cuprite/Capybara support that skips
  third-party scripts + disables rack-attack for `type: :system`.)
- [ ] **Step 2:** Run `rspec spec/system` a couple times; stabilize any flake with Capybara waits (no sleep).
- [ ] **Step 3: Commit.**

### Task 5.2: Gates + docs
- [ ] **Step 1:** `standardrb --fix`; full suite green.
- [ ] **Step 2:** brakeman 0 (watch the new `format_body`/`html_safe` — brakeman may flag it; confirm the
  tokenized version is genuinely safe and, if brakeman still warns, add a reviewed inline annotation with
  justification rather than reverting the safe design); bundler-audit clean.
- [ ] **Step 3:** README + `docs/superpowers/HANDOVER.md` "Slice 3 — DONE" (follow/feed/mentions; still-open:
  Debate, Analytics + new_vote privacy fix, Badges, Trending, Block/mute — per the roadmap).
- [ ] **Step 4: Full suite green; brakeman 0; bundler-audit clean; standardrb clean. Commit.**

## Definition of done
Follow/unfollow (Turbo, throttled, idempotent), followers/following lists, Following feed (signed-in;
anon falls back to global), @mentions (injection-safe render + inline idempotent notify). Full suite green
incl. cuprite; brakeman 0; bundler-audit clean; StandardRB clean.

## Deferred (later program slices)
Badges, Trending, Block/mute + private accounts, bookmarks; Debate, Analytics, Privacy-hardening.
