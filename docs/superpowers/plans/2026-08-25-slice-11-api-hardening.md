# Slice 11 — Api::V1 Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the last open security items with live-traffic exposure on the JSON API — private/blocked/per-post-restricted authors' content leaking through `HujahSerializer` (nested `children`/`parent`), `UserSerializer` (`hujahs` list), and the API feed index (which serves replies); plus the `flag_params` 500-before-authorize, the notifications-index 500-on-deleted-hujah, and the dead CORS initializer.

**Architecture:** Reuse and extend the *existing* Slice-7b / 2026 visibility primitives rather than inventing new gates. Two canonical predicates already live in controllers — the reply-visibility one in `HujahsController#show:43-51`, and the profile-hujah one in `UsersController#profile_tab_list:107-116`. Extract each once onto the model (`Hujah#visible_children_for`, `User#visible_hujahs_for`) and call it from BOTH the HTML controller and the JSON serializer, so the two surfaces share one gate and cannot drift. Pass the Devise session `current_user` into serializer params so filtering happens in SQL (no new N+1). `parent` is a single record, guarded with `visible_to?` + a block check directly.

**Tech Stack:** Rails 8.1, jsonapi-serializer 2.2.0, Pundit, RSpec request specs. No new gems, no new tables, no migrations.

**jsonapi-serializer arity (verified):** `FastJsonapi.call_proc` (`helpers.rb:8-18`) calls a conditional/attribute proc with `(record, params)` by its arity, so a two-arg `proc { |hujah, params| ... }` and a `do |hujah, params|` block both receive `params`. The existing `current_user_vote` block already uses the two-arg form here.

**Owner decisions already made (SECURITY-FINDINGS.md):**
- **A1** (Api::V1 read parity) — the only OPEN item with live-traffic exposure. Serializer-nested content + user endpoint + API feed.
- **A2** (`flag_params`) — decided 2026-08-19: adopt `require` (→ 400, not 500). Breaking change accepted (no legacy native client hits `Api::V1`).
- **A4** (M1 CORS) — decided: **delete the file outright**.
- **A5/L4** (`require_master_key`) — deploy track, **not in this slice**.
- **A3** (2a public counts) / **A6** (votes unique index) / **A7** (count leaks) — **not in this slice** (Slice 13 / separate).

**Pre-implementation Fable leak-audit incorporated (2026-08-25):** the audit caught two A1-class leaks the first draft missed — `UserSerializer#hujahs` (Task 6) and the reply-serving API index (Task 5) — plus the parent block-guard (Task 4) and the notifications 500 (Task 9). Finding 6 (the `vote?` policy lacks the block check `create?` has, on BOTH surfaces) is out of scope and recorded as a new ledger item in Task 10.

---

## File Structure

- `app/models/hujah.rb` — **new** `visible_children_for(viewer)`.
- `app/models/user.rb` — **new** `visible_hujahs_for(viewer)`.
- `app/controllers/hujahs_controller.rb` — `#show` calls `visible_children_for` (behaviour-preserving).
- `app/controllers/users_controller.rb` — `profile_tab_list` else-branch calls `visible_hujahs_for` (behaviour-preserving).
- `app/serializers/hujah_serializer.rb` — `children`/`children_count`/`parent` viewer-aware.
- `app/serializers/user_serializer.rb` — `hujahs`/`hujah_count` viewer-aware.
- `app/controllers/api/v1/hujahs_controller.rb` — `#index` top-level + block filter; `current_user:` param on `#index`/`#show`.
- `app/controllers/api/v1/users_controller.rb` — `current_user:` param on `#show`.
- `app/controllers/api/v1/flags_controller.rb` — `flag_params` uses `require`.
- `app/serializers/notification_serializer.rb` — nil-safe `hujah` accessor.
- `config/initializers/cors.rb` — **deleted**; `Gemfile`/`Gemfile.lock` — remove `rack-cors`.
- Specs: `spec/models/{hujah,user}_spec.rb`, `spec/requests/api/v1/{hujahs,flags,users,notifications}_spec.rb`, **new** `spec/requests/api/v1/api_visibility_spec.rb`.

---

## Task 1: Extract `Hujah#visible_children_for(viewer)`

**Files:**
- Modify: `app/models/hujah.rb` (after `visible_to?`, ~line 62)
- Test: `spec/models/hujah_spec.rb`

- [ ] **Step 1: Write the failing test**

Add to `spec/models/hujah_spec.rb`:

```ruby
describe "#visible_children_for" do
  let(:author) { create(:user) }
  let(:parent) { create(:hujah, user: author) }
  let(:viewer) { create(:user) }

  it "includes a public author's reply for anyone (incl. anonymous)" do
    child = create(:hujah, user: create(:user), parent: parent)
    expect(parent.visible_children_for(nil)).to include(child)
    expect(parent.visible_children_for(viewer)).to include(child)
  end

  it "hides a private author's reply from a stranger and from anonymous" do
    child = create(:hujah, user: create(:user, private: true), parent: parent)
    expect(parent.visible_children_for(nil)).not_to include(child)
    expect(parent.visible_children_for(viewer)).not_to include(child)
  end

  it "shows a private author's reply to an accepted follower and to the author" do
    priv  = create(:user, private: true)
    child = create(:hujah, user: priv, parent: parent)
    priv.passive_follows.create!(follower: viewer, status: :accepted)
    expect(parent.visible_children_for(viewer)).to include(child)
    expect(parent.visible_children_for(priv)).to include(child)
  end

  it "hides a reply authored by someone in the viewer's hidden set (block)" do
    blocked = create(:user)
    child   = create(:hujah, user: blocked, parent: parent)
    viewer.blocks_made.create!(blocked: blocked)
    expect(parent.visible_children_for(viewer)).not_to include(child)
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/hujah_spec.rb -e "#visible_children_for"`
Expected: FAIL — `NoMethodError: undefined method 'visible_children_for'`.

- [ ] **Step 3: Implement**

Add to `app/models/hujah.rb` (immediately after `visible_to?`):

```ruby
  # Reply-visibility gate for a single parent's children — the SQL counterpart to
  # #visible_to? for a REPLY list. Extracted verbatim from HujahsController#show so
  # the HTML thread and the JSON API serializer share ONE gate (a private/blocked
  # author's reply must be hidden identically on both surfaces). One query, no N+1.
  # Signed-in: drop hidden (blocked/blocked-by) authors, then the per-viewer privacy
  # predicate; anonymous: public authors only. Accepted followers (+ self) see a
  # private author's reply via following_ids.
  def visible_children_for(viewer)
    scope = children.includes(:user).order(updated_at: :desc)
    scope = scope.where.not(user_id: viewer.hidden_user_ids) if viewer
    visible_ids = viewer ? viewer.following_ids + [viewer.id] : []
    scope.joins(:user).where("users.private = false OR hujahs.user_id IN (?)", visible_ids)
  end
```

- [ ] **Step 4: Run to verify pass**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/hujah_spec.rb -e "#visible_children_for"`
Expected: PASS (4 examples).

- [ ] **Step 5: Commit**

```bash
git add app/models/hujah.rb spec/models/hujah_spec.rb
git commit -m "Slice 11 Task 1: extract Hujah#visible_children_for (shared reply-visibility gate)"
```

---

## Task 2: Refactor `HujahsController#show` onto `visible_children_for`

**Files:**
- Modify: `app/controllers/hujahs_controller.rb:43-51`
- Test: existing `spec/requests/private_visibility_spec.rb` + `spec/requests/hujahs_spec.rb` (regression guard)

- [ ] **Step 1: Replace the inline predicate**

Replace lines 43–51 of `app/controllers/hujahs_controller.rb` (the `@children = ...` block ending in the `joins(:user).where("users.private = false ...")` line) with:

```ruby
    # Slice 11: the Slice-7/7b reply-visibility predicate now lives on the model
    # (Hujah#visible_children_for) so the HTML thread and the JSON API serializer
    # share ONE gate and cannot drift. Same query, same order, no N+1.
    @children = @hujah.visible_children_for(current_user)
```

- [ ] **Step 2: Run the regression specs**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/private_visibility_spec.rb spec/requests/hujahs_spec.rb`
Expected: PASS — behaviour unchanged (`current_user` is nil for anonymous, which `visible_children_for` handles).

- [ ] **Step 3: Commit**

```bash
git add app/controllers/hujahs_controller.rb
git commit -m "Slice 11 Task 2: HujahsController#show reuses Hujah#visible_children_for"
```

---

## Task 3: Extract `User#visible_hujahs_for(viewer)` + refactor `profile_tab_list`

**Files:**
- Modify: `app/models/user.rb` (near `visible_to?`, ~line 74)
- Modify: `app/controllers/users_controller.rb:107-115` (the `profile_tab_list` else-branch)
- Test: `spec/models/user_spec.rb` + existing `spec/requests/private_visibility_spec.rb` (regression)

This is the profile-hujah counterpart of Task 1: encapsulate the `profile_tab_list` else-branch (top-level, per-post-visibility-gated by self/accepted-follower/other) so the HTML profile "Hoojahs" tab and the API `UserSerializer#hujahs` (Task 6) share one gate.

- [ ] **Step 1: Write the failing test**

Add to `spec/models/user_spec.rb`:

```ruby
describe "#visible_hujahs_for" do
  let(:owner)  { create(:user) }
  let(:viewer) { create(:user) }

  it "returns only visible_public top-level hoojahs to a stranger/anonymous" do
    pub  = create(:hujah, user: owner, visibility: :visible_public)
    create(:hujah, user: owner, visibility: :followers_only)
    create(:hujah, user: owner, visibility: :private_only)
    create(:hujah, user: owner, visibility: :visible_public, parent: create(:hujah)) # a reply
    expect(owner.visible_hujahs_for(nil)).to contain_exactly(pub)
    expect(owner.visible_hujahs_for(viewer)).to contain_exactly(pub)
  end

  it "adds followers_only for an accepted follower" do
    pub = create(:hujah, user: owner, visibility: :visible_public)
    fo  = create(:hujah, user: owner, visibility: :followers_only)
    create(:hujah, user: owner, visibility: :private_only)
    owner.passive_follows.create!(follower: viewer, status: :accepted)
    expect(owner.visible_hujahs_for(viewer)).to contain_exactly(pub, fo)
  end

  it "returns all top-level hoojahs to the owner themselves" do
    a = create(:hujah, user: owner, visibility: :visible_public)
    b = create(:hujah, user: owner, visibility: :private_only)
    expect(owner.visible_hujahs_for(owner)).to contain_exactly(a, b)
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/user_spec.rb -e "#visible_hujahs_for"`
Expected: FAIL — `NoMethodError: undefined method 'visible_hujahs_for'`.

- [ ] **Step 3: Implement on the model**

Add to `app/models/user.rb` (after `accepted_follower?`, ~line 78):

```ruby
  # Profile "Hoojahs" tab visibility — top-level hoojahs this viewer may see,
  # gated by per-post visibility (2026). Extracted from UsersController#profile_tab_list
  # so the HTML profile and the API UserSerializer share ONE gate. Block filtering is
  # intentionally absent: every row here is authored by `self`, and Block does not hide
  # a user's own profile (Slice 7 direct-URL boundary) — the account-level gate is the
  # caller's responsibility (HTML: _gated_header; API: users#show visible_to? → 404).
  def visible_hujahs_for(viewer)
    base =
      if viewer == self
        hujahs
      elsif accepted_follower?(viewer)
        hujahs.where(visibility: [:visible_public, :followers_only])
      else
        hujahs.where(visibility: :visible_public)
      end
    base.where(parent_id: nil).includes(:user).order(updated_at: :desc)
  end
```

- [ ] **Step 4: Refactor the controller onto it**

In `app/controllers/users_controller.rb#profile_tab_list`, replace the `else` branch (lines 107-115, the `scoped = if current_user == @user ... end` block plus the trailing `scoped.where(parent_id: nil)...` line) with:

```ruby
    else
      # Slice 11: the per-post-visibility profile predicate now lives on the model
      # (User#visible_hujahs_for) so the HTML "Hoojahs" tab and the API UserSerializer
      # share ONE gate and cannot drift.
      @user.visible_hujahs_for(current_user)
    end
```

- [ ] **Step 5: Run model + profile regression specs**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/user_spec.rb -e "#visible_hujahs_for" spec/requests/private_visibility_spec.rb`
Expected: PASS — the extraction is behaviour-identical to the old else-branch.

- [ ] **Step 6: Commit**

```bash
git add app/models/user.rb app/controllers/users_controller.rb spec/models/user_spec.rb
git commit -m "Slice 11 Task 3: extract User#visible_hujahs_for (shared profile-hoojah gate)"
```

---

## Task 4: Make `HujahSerializer` viewer-aware — closes A1 nested-content leak

**Files:**
- Modify: `app/serializers/hujah_serializer.rb`
- Test: new `spec/requests/api/v1/api_visibility_spec.rb`

- [ ] **Step 1: Write the failing request spec**

Create `spec/requests/api/v1/api_visibility_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Api::V1 visibility parity", type: :request do
  let(:public_author) { create(:user) }
  let(:parent)        { create(:hujah, user: public_author, visibility: :visible_public) }

  describe "GET /api/v1/hoojah/:slug — nested children" do
    it "omits a private author's reply from the JSON children for an anonymous caller" do
      priv = create(:user, private: true)
      create(:hujah, user: priv, parent: parent, body: "secret reply")
      get "/api/v1/hoojah/#{parent.slug}"
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("secret reply")
      expect(response.body).not_to include(priv.username)
    end

    it "omits a blocked author's reply from the JSON children for the blocker" do
      me      = create(:user)
      blocked = create(:user)
      create(:hujah, user: blocked, parent: parent, body: "blocked reply")
      me.blocks_made.create!(blocked: blocked)
      sign_in me
      get "/api/v1/hoojah/#{parent.slug}"
      expect(response.body).not_to include("blocked reply")
    end

    it "still includes a public author's reply" do
      create(:hujah, user: create(:user), parent: parent, body: "open reply")
      get "/api/v1/hoojah/#{parent.slug}"
      expect(response.body).to include("open reply")
    end

    it "reports children_count as the VISIBLE count, not the raw count" do
      create(:hujah, user: create(:user), parent: parent, body: "open reply")
      create(:hujah, user: create(:user, private: true), parent: parent, body: "secret reply")
      get "/api/v1/hoojah/#{parent.slug}"
      expect(JSON.parse(response.body).dig("data", "attributes", "children_count")).to eq(1)
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/api/v1/api_visibility_spec.rb`
Expected: FAIL — private/blocked reply bodies appear; `children_count` is the raw count.

- [ ] **Step 3: Rewrite the serializer**

Replace `app/serializers/hujah_serializer.rb` in full:

```ruby
class HujahSerializer
  include JSONAPI::Serializer

  attributes :body, :agree_count, :neutral_count, :disagree_count, :vote, :slug

  # Slice 11 (A1): children_count reflects only the replies this viewer may see —
  # returning the raw count alongside a filtered `children` array would itself leak
  # that hidden replies exist. Shares Hujah#visible_children_for with `children`.
  attribute :children_count do |hujah, params|
    hujah.visible_children_for(params[:current_user]).size
  end

  # this is the owner of the hujah, not the current user
  attribute :user do |hujah|
    {
      id: hujah.user.id,
      type: "user",
      attributes: {
        username: hujah.user.username,
        full_name: hujah.user.full_name,
        photo: hujah.user.photo
      }
    }
  end

  # Slice 11 (A1): only expose the parent block when the parent is visible to the
  # viewer (privacy via #visible_to?) AND not authored by someone the viewer blocked —
  # a private/blocked parent author must not leak through a public reply's `parent`.
  # One record → guard directly (no list, no N+1).
  attribute :parent, if: proc { |hujah, params|
    hujah.parent_id &&
      hujah.parent.visible_to?(params[:current_user]) &&
      !params[:current_user]&.hidden_user_ids&.include?(hujah.parent.user_id)
  } do |hujah|
    {
      id: hujah.parent.id,
      type: "hujah",
      attributes: {
        body: hujah.parent.body,
        slug: hujah.parent.slug,
        user: {
          attributes: {
            username: hujah.parent.user.username,
            full_name: hujah.parent.user.full_name,
            photo: hujah.parent.user.photo
          }
        }
      }
    }
  end

  # Slice 11 (A1): iterate ONLY the viewer-visible children (private-account + block
  # filtered in SQL via Hujah#visible_children_for) — the previous `hujah.children.each`
  # leaked private/blocked authors' reply bodies + usernames to any API caller.
  attribute :children, if: proc { |hujah, params| hujah.visible_children_for(params[:current_user]).any? } do |hujah, params|
    hujah.visible_children_for(params[:current_user]).map do |child|
      {
        id: child.id,
        type: "hujah",
        attributes: {
          body: child.body,
          vote: child.vote,
          agree_count: child.agree_count,
          neutral_count: child.neutral_count,
          disagree_count: child.disagree_count,
          slug: child.slug,
          user: {
            attributes: {
              username: child.user.username,
              full_name: child.user.full_name,
              photo: child.user.photo
            }
          }
        }
      }
    end
  end

  attribute :current_user_vote do |hujah, params|
    hujah.current_user_vote(logged_in: params[:logged_in], current_user_id: params[:current_user_id])
  end
end
```

> `visible_children_for` runs up to 3× per hujah (count, `if:`, body) — one SQL each, matching the OLD profile (`children.count` + `children.length` + `children.each`). Not a regression; memoization is a separate C2 concern.

- [ ] **Step 4: Wire `current_user:` into the serializer params (both call sites)**

In `app/controllers/api/v1/hujahs_controller.rb`, add `current_user: current_user` to the `params:` hash in BOTH `#index` (line 12) and `#show` (line 33):

```ruby
    # #index
    serialized_hujahs = HujahSerializer.new(hujahs, params: {logged_in: user_signed_in?, current_user_id: current_user&.id, current_user: current_user}).serializable_hash
    # #show
    serialized_hujah = HujahSerializer.new(hujah, params: {logged_in: user_signed_in?, current_user_id: current_user&.id, current_user: current_user}).serializable_hash
```

- [ ] **Step 5: Run to verify pass**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/api/v1/api_visibility_spec.rb spec/requests/api/v1/hujahs_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/serializers/hujah_serializer.rb app/controllers/api/v1/hujahs_controller.rb spec/requests/api/v1/api_visibility_spec.rb
git commit -m "Slice 11 Task 4: HujahSerializer children/children_count/parent viewer-gated (closes A1 nested)"
```

---

## Task 5: Api::V1 feed index — top-level only + block filter — closes A1 feed gap

**Files:**
- Modify: `app/controllers/api/v1/hujahs_controller.rb:10-11`
- Test: `spec/requests/api/v1/api_visibility_spec.rb`

The index has **no `where(parent_id: nil)`** (HTML global feed has it), so it serves replies — a public reply under a `followers_only`/`private_only`/private-author parent leaks its body. It also does not drop **blocked** authors for a signed-in caller.

- [ ] **Step 1: Add the failing specs**

Append to `spec/requests/api/v1/api_visibility_spec.rb`:

```ruby
  describe "GET /api/v1/hoojah — feed index" do
    it "does not serve replies (a public reply under a restricted parent must not leak)" do
      restricted_parent = create(:hujah, user: create(:user), visibility: :private_only)
      create(:hujah, user: public_author, parent: restricted_parent, body: "leaky reply")
      get "/api/v1/hoojah"
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("leaky reply")
    end

    it "omits a blocked author's top-level hoojah for a signed-in caller" do
      me      = create(:user)
      blocked = create(:user)
      create(:hujah, user: blocked, visibility: :visible_public, body: "blocked top-level")
      me.blocks_made.create!(blocked: blocked)
      sign_in me
      get "/api/v1/hoojah"
      expect(response.body).not_to include("blocked top-level")
    end

    it "still shows a blocked author's hoojah to an unrelated signed-out caller" do
      blocked = create(:user)
      create(:hujah, user: blocked, visibility: :visible_public, body: "still public")
      get "/api/v1/hoojah"
      expect(response.body).to include("still public")
    end
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/api/v1/api_visibility_spec.rb -e "feed index"`
Expected: FAIL — the reply and the blocked top-level currently appear.

- [ ] **Step 3: Fix the index query**

In `app/controllers/api/v1/hujahs_controller.rb#index`, replace the `hujahs = Hujah.joins(:user)...` assignment (lines 10-11) with:

```ruby
    # Slice 11 (A1): TOP-LEVEL only (`parent_id: nil`) — the index previously served
    # replies too, leaking a public reply's body from under a restricted/private parent
    # (Hujah#visible_to? is false for it via parent recursion). Matches the HTML global
    # feed shape. Follower-aware parity for restricted top-level claims stays deferred.
    hujahs = Hujah.where(parent_id: nil).joins(:user).where(users: {private: false})
      .where(visibility: :visible_public).order(updated_at: :desc)
    # Drop blocked/blocked-by authors for a signed-in caller — mirrors the HTML feed.
    # Anonymous callers are unfiltered (no social graph).
    hujahs = hujahs.where.not(user_id: current_user.hidden_user_ids) if user_signed_in?
```

- [ ] **Step 4: Run to verify pass**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/api/v1/api_visibility_spec.rb`
Expected: PASS (all examples).

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/v1/hujahs_controller.rb spec/requests/api/v1/api_visibility_spec.rb
git commit -m "Slice 11 Task 5: Api::V1 feed index is top-level + block-filtered (closes A1 feed gap)"
```

---

## Task 6: Make `UserSerializer` viewer-aware — closes A1 user-endpoint leak

**Files:**
- Modify: `app/serializers/user_serializer.rb`
- Modify: `app/controllers/api/v1/users_controller.rb:11` (pass `current_user:`)
- Test: new examples in `spec/requests/api/v1/users_spec.rb`

`UserSerializer#hujahs` iterates `user.hujahs.each` fully unfiltered — a public account's `private_only`/`followers_only` claim bodies leak via `GET /api/v1/:username`, and replies-under-invisible-parents leak too. Filter through `User#visible_hujahs_for` (Task 3). `hujah_count` follows suit for consistency.

- [ ] **Step 1: Write the failing spec**

Add to `spec/requests/api/v1/users_spec.rb`:

```ruby
  describe "per-post visibility of the profile hoojah list" do
    let(:owner) { create(:user) }

    it "omits a public account's private_only and followers_only bodies from a stranger" do
      create(:hujah, user: owner, visibility: :visible_public,   body: "public claim")
      create(:hujah, user: owner, visibility: :followers_only,   body: "followers claim")
      create(:hujah, user: owner, visibility: :private_only,     body: "private claim")

      get "/api/v1/#{owner.username}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("public claim")
      expect(response.body).not_to include("followers claim")
      expect(response.body).not_to include("private claim")
    end

    it "shows followers_only bodies to an accepted follower" do
      viewer = create(:user)
      owner.update!(private: false)
      create(:hujah, user: owner, visibility: :followers_only, body: "followers claim")
      owner.passive_follows.create!(follower: viewer, status: :accepted)

      sign_in viewer
      get "/api/v1/#{owner.username}"

      expect(response.body).to include("followers claim")
    end

    it "reports hujah_count as the visible top-level count" do
      create(:hujah, user: owner, visibility: :visible_public)
      create(:hujah, user: owner, visibility: :private_only)
      get "/api/v1/#{owner.username}"
      expect(JSON.parse(response.body).dig("data", "attributes", "hujah_count")).to eq(1)
    end
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/api/v1/users_spec.rb -e "per-post visibility"`
Expected: FAIL — restricted bodies appear; `hujah_count` is the raw count.

- [ ] **Step 3: Rewrite the serializer's `hujahs` + `hujah_count`**

In `app/serializers/user_serializer.rb`, replace `hujah_count` (lines 6-8) and the `hujahs` attribute (lines 14-41):

```ruby
  # Slice 11 (A1): only the top-level hoojahs this viewer may see (per-post visibility),
  # via User#visible_hujahs_for — shared with the HTML profile "Hoojahs" tab. Count
  # follows the same filter so it can't reveal that hidden claims exist.
  attribute :hujah_count do |user, params|
    user.visible_hujahs_for(params[:current_user]).size
  end

  attribute :vote_count do |user|
    user.votes.length
  end

  attribute :hujahs, if: proc { |user, params| user.visible_hujahs_for(params[:current_user]).any? } do |user, params|
    user.visible_hujahs_for(params[:current_user]).map do |child_hujah|
      {
        id: child_hujah.id,
        type: "hujah",
        attributes: {
          body: child_hujah.body,
          vote: child_hujah.vote,
          agree_count: child_hujah.agree_count,
          neutral_count: child_hujah.neutral_count,
          disagree_count: child_hujah.disagree_count,
          slug: child_hujah.slug,
          user: {
            attributes: {
              username: child_hujah.user.username,
              full_name: child_hujah.user.full_name,
              photo: child_hujah.user.photo
            }
          }
        }
      }
    end
  end
```

Keep the `attributes :username, :full_name, :photo, :location, :headline, :link` line and `vote_count` as-is. (Move `vote_count` above `hujahs` if the edit is cleaner; order does not matter to the output.)

- [ ] **Step 4: Pass `current_user:` from the controller**

In `app/controllers/api/v1/users_controller.rb#show`, change the serializer build (line 11):

```ruby
      render json: UserSerializer.new(user, params: {current_user: current_user}).serializable_hash
```

(Leave `#update`'s `UserSerializer.new(@user)` as-is — it serializes the caller's own record; `visible_hujahs_for(nil)` there would still be safe, but for symmetry pass `params: {current_user: @user}`.)

- [ ] **Step 5: Run to verify pass**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/api/v1/users_spec.rb`
Expected: PASS (new + existing).

- [ ] **Step 6: Commit**

```bash
git add app/serializers/user_serializer.rb app/controllers/api/v1/users_controller.rb spec/requests/api/v1/users_spec.rb
git commit -m "Slice 11 Task 6: UserSerializer hujahs/hujah_count viewer-gated (closes A1 user endpoint)"
```

---

## Task 7: `flag_params` uses `require` — closes A2 (500 → 400)

**Files:**
- Modify: `app/controllers/api/v1/flags_controller.rb:22`
- Test: `spec/requests/api/v1/flags_spec.rb`

- [ ] **Step 1: Write the failing spec**

Add to `spec/requests/api/v1/flags_spec.rb`:

```ruby
  it "returns 400 (not 500) when the flag key is missing" do
    sign_in create(:user)
    post "/api/v1/flags", params: {}, as: :json
    expect(response).to have_http_status(:bad_request)
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/api/v1/flags_spec.rb -e "flag key is missing"`
Expected: FAIL — currently a `NoMethodError` on nil → 500.

- [ ] **Step 3: Adopt `require`**

In `app/controllers/api/v1/flags_controller.rb`:

```ruby
  def flag_params
    # Slice 11 (A2): `require` so a POST with no `flag` key returns 400 (Rails maps
    # ParameterMissing → :bad_request) instead of a NoMethodError-on-nil 500 that fired
    # BEFORE `authorize`. Breaking change accepted 2026-08-19 (no legacy native client
    # hits Api::V1); the HTML FlagsController already uses `require`.
    params.require(:flag).permit(:hujah_id, :subject)
  end
```

- [ ] **Step 4: Run to verify pass**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/api/v1/flags_spec.rb`
Expected: PASS — new example green; existing examples (which post `{flag: {...}}`) unaffected.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/v1/flags_controller.rb spec/requests/api/v1/flags_spec.rb
git commit -m "Slice 11 Task 7: Api::V1 flag_params uses require (500 -> 400) — closes A2"
```

---

## Task 8: Delete the dead CORS initializer + gem — closes A4 (M1)

**Files:**
- Delete: `config/initializers/cors.rb`; Modify: `Gemfile` (+ `Gemfile.lock` via bundle)

- [ ] **Step 1: Confirm the initializer is the only consumer**

Run: `grep -rn "Rack::Cors\|rack-cors\|rack_cors" app config lib Gemfile`
Expected: hits only in `config/initializers/cors.rb` and the `Gemfile`. If anything else references it, STOP and re-scope.

- [ ] **Step 2: Delete the initializer**

Run: `git rm config/initializers/cors.rb`

- [ ] **Step 3: Remove the gem**

Delete the `gem "rack-cors"` line from `Gemfile`.

- [ ] **Step 4: Re-lock**

Run: `mise exec ruby@3.4.9 -- bundle install`
Expected: `rack-cors` removed from `Gemfile.lock`; clean resolve.

- [ ] **Step 5: Verify boot**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/api/v1/hujahs_spec.rb`
Expected: PASS — app boots without the initializer.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Slice 11 Task 8: delete dead rack-cors initializer + gem — closes M1 (A4)"
```

---

## Task 9: Notifications endpoint — nil-safe hujah + verify private/block

**Files:**
- Modify: `app/serializers/notification_serializer.rb:10-20`
- Test: `spec/requests/api/v1/notifications_spec.rb`

`NotificationSerializer#hujah` uses `Hujah.find(notification.hujah_id)` — raises `RecordNotFound` → **500s the entire notifications index** once any referenced hujah is deleted (`notifications.hujah` is `optional: true`; hujah destroy is a live endpoint with no notification cleanup). The `visible_to?` privacy guard itself is already correct (Slice 7b) and covers per-post visibility + reply recursion — the Fable audit confirmed the private-account concern is already closed; this task closes the 500 and adds the missing coverage.

- [ ] **Step 1: Add specs (deleted-hujah + private-account characterization)**

Add to `spec/requests/api/v1/notifications_spec.rb`:

```ruby
  describe "referenced hoojah visibility + robustness" do
    it "does not 500 the index when a referenced hoojah was deleted" do
      recipient = create(:user)
      hujah     = create(:hujah, user: create(:user))
      notif     = create(:notification, user: recipient, hujah: hujah, category: :new_hoojah_response)
      hujah.destroy
      notif.reload # hujah_id still set, row gone

      sign_in recipient
      get "/api/v1/notifications"

      expect(response).to have_http_status(:ok)
    end

    it "omits the hoojah block when its author is private and unseen by the recipient" do
      recipient = create(:user)
      priv      = create(:user, private: true)
      hujah     = create(:hujah, user: priv, visibility: :visible_public)
      create(:notification, user: recipient, hujah: hujah, category: :new_hoojah_response)

      sign_in recipient
      get "/api/v1/notifications"

      hujah_attrs = JSON.parse(response.body)["data"].map { |n| n.dig("attributes", "hujah") }.compact
      expect(hujah_attrs).to be_empty
    end
  end
```

- [ ] **Step 2: Run to verify**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/api/v1/notifications_spec.rb -e "referenced hoojah"`
Expected: the deleted-hujah example FAILS (500); the private-account example PASSES already.

- [ ] **Step 3: Make the accessor nil-safe**

In `app/serializers/notification_serializer.rb`, change the `hujah` attribute to use the `optional: true` association accessor instead of `Hujah.find`:

```ruby
  attribute :hujah do |notification|
    hujah = notification.hujah # optional belongs_to → nil, not RecordNotFound, if deleted
    if hujah && hujah.visible_to?(notification.user)
      {
        slug: hujah.slug,
        body: hujah.body
      }
    end
  end
```

- [ ] **Step 4: Run to verify pass**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/api/v1/notifications_spec.rb`
Expected: PASS (both new examples + existing).

- [ ] **Step 5: Commit**

```bash
git add app/serializers/notification_serializer.rb spec/requests/api/v1/notifications_spec.rb
git commit -m "Slice 11 Task 9: notifications serializer nil-safe hujah accessor (no 500 on deleted hoojah)"
```

---

## Task 10: Full-slice verification + security audit + ledger

- [ ] **Step 1: Full CI gate**

Run: `bin/ci`
Expected: all gates green (standardrb, brakeman 0, bundler-audit, full RSpec incl. system). Record the example-count delta vs the 864 baseline.

- [ ] **Step 2: prosopite N+1 check**

After a suite run: `grep -c 'N+1 queries detected' log/prosopite.log`.
Expected: no material increase over the ~179 redesign baseline (serializer changes reuse the existing per-record query profile). Investigate any jump before proceeding.

- [ ] **Step 3: rails-security-auditor pass**

Dispatch `rails-security-auditor:audit-security` scoped to this branch's diff. Confirm: A1 closed across `HujahSerializer`, `UserSerializer`, the feed index, and the notifications endpoint; A2 no longer 500s pre-authorize; A4 gone; `current_user:` param is Devise-session-derived (not forgeable); no new finding.

- [ ] **Step 4: Update the ledger + handover**

- `docs/superpowers/SECURITY-FINDINGS.md`: move **A1, A2, M1(A4)** from OPEN to a "Closed in Slice 11" section with commit SHAs. **Add a new tracked item** (finding 6): `HujahPolicy#vote?` lacks the `hidden_user_ids` check that `#create?` has — a blocker can still vote on a blocked author's *public* hujah, on BOTH HTML and API (shared policy, so no read-parity gap; a small policy hardening for a later slice). Note also that `UserSerializer#vote_count` and the remaining `*_count` columns stay unfiltered (A7 class, tracked). Leave A3 (Slice 13), A5/L4 (deploy), A6 (votes unique index) as-is.
- `docs/superpowers/HANDOVER.md`: add a Slice 11 section (branch, suite count, what shipped, what stays deferred).

- [ ] **Step 5: Final commit**

```bash
git add docs/superpowers/SECURITY-FINDINGS.md docs/superpowers/HANDOVER.md
git commit -m "Slice 11 Task 10: ledger + handover — A1/A2/M1 closed"
```

---

## Explicitly out of scope (tracked elsewhere — do NOT expand this slice)

- **A3 / finding 2a** (public per-hoojah count k=5 suppression) → **Slice 13**. This slice does not touch `agree/neutral/disagree_count` exposure on visible hoojahs.
- **A6** (votes `[hujah_id, user_id]` unique index / first-vote race) → separate data-integrity change.
- **A7** (unfiltered `vote_count`/tab-badge/hashtag counts) → same class as 2a; `children_count`/`hujah_count` are fixed here only because they sit inside serializers already being hardened.
- **A5 / L4** (`require_master_key`) → deploy track.
- **Finding 6** (`vote?` block check) → new ledger item, both surfaces, a later policy slice.
- **C2** (broader serializer N+1 / prosopite pass) → tracked; this slice must not *regress* N+1 but does not undertake the full audit.
- **Follower-aware Api::V1 index** (restricted top-level claims to eligible callers) → deferred to Project 3; this slice only makes the index *more* restrictive.

---

## Self-Review

**Spec coverage:** A1 hujah nested (Task 4) ✓; A1 feed replies + block (Task 5) ✓; A1 user endpoint (Task 6) ✓; A1 notifications privacy already-closed + verified + 500 fix (Task 9) ✓; shared-gate extraction preventing HTML/API drift (Tasks 1–3) ✓; A2 (Task 7) ✓; A4/M1 (Task 8) ✓; verification/audit/ledger incl. finding 6 (Task 10) ✓.

**Placeholder scan:** every code step shows complete code. No TBD/TODO/"handle edge cases".

**Type consistency:** `visible_children_for(viewer)` — model (T1), HTML controller (T2), serializer (T4). `visible_hujahs_for(viewer)` — model (T3), HTML controller (T3), serializer (T6). Serializer param key `current_user:` added identically at every `HujahSerializer`/`UserSerializer` call site (T4 Step 4, T6 Step 4). `params[:current_user]` read consistently.
