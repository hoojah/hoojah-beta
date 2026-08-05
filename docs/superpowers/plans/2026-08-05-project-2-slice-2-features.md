# Project 2 — Slice 2: Features + Pundit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use
> checkbox (`- [ ]`) syntax.

**Goal:** Add compose/respond, profile (view+edit), notifications, flag, and share to the Hotwire app;
adopt Pundit; close the notifications IDOR/leak, the `link` XSS (M7), and harden flags/photo — on both the
HTML and `Api::V1` surfaces.

**Architecture:** Pundit is adopted first (app-wide `verify_authorized` exempting Devise; per-action
authorize/skip; 4 policies; Slice 1's before_action IDOR checks migrated to policies). Then model-level
hardening (validations + a compose notification callback), then the five screens as Hotwire (native
`<dialog>` modals, a `close_dialog` custom Turbo Stream action, Cloudinary/share Stimulus controllers).

**Tech Stack:** Rails 8.1.3.1, Ruby 3.4.9 (mise), Devise 5.0.4, Pundit ~>2.5, Turbo/Stimulus, Tailwind,
cuprite. **Source spec:** `docs/superpowers/specs/2026-08-05-project-2-slice-2-features-design.md` (read first).

---

## Canonical commands (from HANDOVER.md — use verbatim)

- **Bundle:** `source .mise-build-env.sh && mise exec ruby@3.4.9 -- bundle install`
- **Rails/rake:** `mise exec ruby@3.4.9 -- bin/rails <args>`
- **Specs:** `RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec <path>`
- **Test DB (schema only):** `mise exec ruby@3.4.9 -- bin/rails db:test:prepare`
- **Gates:** `mise exec ruby@3.4.9 -- bundle exec brakeman -q` / `... bundler-audit check --update` /
  `... standardrb`

Branch: `project-2-slice-2-features`. Commit after every task (no Claude/Anthropic attribution).
**Baseline:** suite is green at `50 examples, 0 failures, 2 pending` before this slice. After every task
the suite must be green except specs a task is explicitly mid-rewrite (notifications/flags in Phase 4/5).

---

## File structure

**Created:** `app/policies/application_policy.rb`, `app/policies/{hujah,notification,user,flag}_policy.rb`;
`app/controllers/{users,notifications,flags}_controller.rb` (HTML) + compose actions on
`app/controllers/hujahs_controller.rb`; `app/javascript/controllers/{dialog,cloudinary_upload,share}_controller.js`;
views under `app/views/{hujahs,users,notifications,shared}/**`; request/system specs.

**Modified:** `Gemfile`, `config/routes.rb`, `app/controllers/application_controller.rb`, every
`app/controllers/api/v1/*` + `app/controllers/votes_controller.rb`, `app/models/{user,hujah,notification}.rb`,
`app/javascript/application.js`, `config/initializers/rack_attack.rb`,
`spec/requests/api/v1/{notifications,flags,votes,hujahs}_spec.rb`, `README.md`, `HANDOVER.md`.

---

# Phase 0 — Pundit foundation (lands first, full-suite gate)

### Task 0.1: Add Pundit + ApplicationPolicy + wire ApplicationController

**Files:** Modify `Gemfile`, `app/controllers/application_controller.rb`. Create
`app/policies/application_policy.rb`.

- [ ] **Step 1: Gem** — add `gem 'pundit', '~> 2.5'`; `source .mise-build-env.sh && mise exec ruby@3.4.9 -- bundle install`.

- [ ] **Step 2: ApplicationController** — replace with:

```ruby
class ApplicationController < ActionController::Base
  include Pundit::Authorization

  after_action :verify_authorized, unless: :devise_controller?

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  private

  def user_not_authorized
    respond_to do |format|
      format.html { redirect_back fallback_location: root_path, alert: "Not allowed." }
      format.any  { head :forbidden }
    end
  end
end
```

- [ ] **Step 3: ApplicationPolicy** — `app/policies/application_policy.rb` (standard Pundit scaffold:
  `initialize(user, record)`, default deny predicates, nested `Scope`).

- [ ] **Step 4: Boot** — `mise exec ruby@3.4.9 -- bin/rails runner 'puts "ok"'` → `ok`.

- [ ] **Step 5: Commit** — `git commit -m "Slice 2: add Pundit + ApplicationPolicy; verify_authorized (Devise-exempt)"`

### Task 0.2: Policies + wire every controller (the all-or-nothing pass)

**Files:** Create `app/policies/{hujah,notification,user,flag}_policy.rb`. Modify
`app/controllers/votes_controller.rb`, `app/controllers/api/v1/{votes,hujahs,notifications,flags,users}_controller.rb`,
`app/controllers/hujahs_controller.rb`. Test: `spec/policies/*_spec.rb` + the existing request specs.

- [ ] **Step 1: Write policy specs first** — e.g. `spec/policies/hujah_policy_spec.rb`:

```ruby
require 'rails_helper'
RSpec.describe HujahPolicy do
  let(:owner) { create(:user) }
  let(:other) { create(:user) }
  let(:hujah) { create(:hujah, user: owner) }

  it 'permits destroy only for the owner' do
    expect(HujahPolicy.new(owner, hujah).destroy?).to be(true)
    expect(HujahPolicy.new(other, hujah).destroy?).to be(false)
    expect(HujahPolicy.new(nil, hujah).destroy?).to be(false)
  end
  it 'permits vote/create for any logged-in user' do
    expect(HujahPolicy.new(owner, hujah).vote?).to be(true)
    expect(HujahPolicy.new(nil, hujah).vote?).to be(false)
  end
end
```
(Also `notification_policy_spec.rb`: owner-only update/destroy + `Scope` returns only the user's;
`user_policy_spec.rb`: update? == self; `flag_policy_spec.rb`: create? == user.present?.)

- [ ] **Step 2: Run → FAIL** (policies undefined).

- [ ] **Step 3: Policies:**

```ruby
# app/policies/hujah_policy.rb
class HujahPolicy < ApplicationPolicy
  def create? = user.present?
  def vote?   = user.present?
  def destroy? = user.present? && record.user_id == user.id
end

# app/policies/notification_policy.rb
class NotificationPolicy < ApplicationPolicy
  def update?  = owner?
  def destroy? = owner?
  def owner? = user.present? && record.user_id == user.id
  class Scope < ApplicationPolicy::Scope
    def resolve = user ? scope.where(user: user) : scope.none
  end
end

# app/policies/user_policy.rb
class UserPolicy < ApplicationPolicy
  def update? = user.present? && record.id == user.id
end

# app/policies/flag_policy.rb
class FlagPolicy < ApplicationPolicy
  def create? = user.present?
end
```

- [ ] **Step 4: Wire the controllers (per-action, exactly once).** In each, replace Slice 1's
  `before_action` IDOR checks with `authorize`, and add `skip_authorization` to public reads:
  - `app/controllers/api/v1/votes_controller.rb#create`: drop `before_action :authenticate_user!`? **No —
    keep `authenticate_user!`** (fail-fast 401), then `authorize @hujah, :vote?` (after loading `@hujah`).
  - `app/controllers/api/v1/hujahs_controller.rb`: `index`/`show`/`create`/`new` → `skip_authorization`
    (create is authed at controller-level already; keep it simple — `skip_authorization` on the public
    reads, `authorize Hujah` on create is optional but do `skip_authorization` for index/show/new).
    `destroy` → replace `require_owner!` with `authorize hujah` (loads `@hujah`, `HujahPolicy#destroy?`).
  - `app/controllers/api/v1/notifications_controller.rb`: `index` → `@notifications =
    policy_scope(Notification)`; `update`/`destroy` → `authorize @notification`. Delete `find_user`/`@user`.
    Add `before_action :authenticate_user!`.
  - `app/controllers/api/v1/flags_controller.rb`: `before_action :authenticate_user!`; `create` →
    `authorize Flag`; drop `:user_id` from `flag_params`.
  - `app/controllers/api/v1/users_controller.rb`: `show` → `skip_authorization`; `update` →
    `authorize @user` (load `@user = current_user`).
  - `app/controllers/votes_controller.rb` (HTML): `authorize @hujah, :vote?`.

- [ ] **Step 5: Update existing request specs** to stay green with the new 401/403 semantics (they were
  written in Slice 1 to assert unauth→401, non-owner→403 — confirm they still pass; adjust only if the
  status source changed from `authenticate_user!` to Pundit).

- [ ] **Step 6: Full suite + auth-flow assertions** — add `spec/requests/pundit_rollout_spec.rb`:

```ruby
require 'rails_helper'
RSpec.describe 'Auth flows survive Pundit rollout', type: :request do
  it 'login/signup/logout/password pages still render' do
    get '/login';        expect(response).to have_http_status(:ok)
    get '/signup';       expect(response).to have_http_status(:ok)
    get '/password/new'; expect(response).to have_http_status(:ok)
  end
  it 'a signed-in user can sign out' do
    sign_in create(:user)
    delete '/logout'
    expect(response).to have_http_status(:see_other).or have_http_status(:found)
  end
end
```

Run the FULL suite — must be green (0 failures). If any `Api::V1` action 500s with
`AuthorizationNotPerformedError`, that action is missing its authorize/skip — fix it.

- [ ] **Step 7: Commit** — `git commit -m "Slice 2: policies + per-action authorize/skip across all controllers; migrate Slice 1 IDOR checks to Pundit"`

---

# Phase 1 — Model hardening

### Task 1.1: User validations (link XSS/M7, photo host, username)

**Files:** Modify `app/models/user.rb`. Test: `spec/models/user_spec.rb` (extend).

- [ ] **Step 1: Failing tests** — add:

```ruby
it 'rejects a non-http link (M7)' do
  u = build(:user, link: "javascript:alert(1)")
  expect(u).not_to be_valid
  expect(build(:user, link: "https://ok.example")).to be_valid
  expect(build(:user, link: "")).to be_valid
end
it 'accepts only a hoojah Cloudinary photo host (exact host)' do
  expect(build(:user, photo: "https://res.cloudinary.com/hoojah/image/upload/x.jpg")).to be_valid
  expect(build(:user, photo: "https://res.cloudinary.com.evil.com/hoojah/x.jpg")).not_to be_valid
  expect(build(:user, photo: "https://res.cloudinary.com@evil.com/hoojah/x.jpg")).not_to be_valid
  expect(build(:user, photo: "http://res.cloudinary.com/hoojah/x.jpg")).not_to be_valid
end
it 'rejects reserved / malformed usernames' do
  expect(build(:user, username: "login")).not_to be_valid
  expect(build(:user, username: "has space")).not_to be_valid
end
```

- [ ] **Step 2: Run → FAIL.**

- [ ] **Step 3: Implement** in `app/models/user.rb`:

```ruby
RESERVED_USERNAMES = %w[login signup logout password edit cancel new hoojah hoojahs u users
                        notifications rails api admin].freeze

validates :username, format: { with: /\A[a-zA-Z0-9_]+\z/ },
                     exclusion: { in: RESERVED_USERNAMES }
validates :link, format: { with: %r{\Ahttps?://}i }, allow_blank: true
validate :photo_from_cloudinary

def photo_from_cloudinary
  return if photo.blank?
  uri = URI.parse(photo)
  ok = uri.scheme == "https" && uri.host == "res.cloudinary.com" && uri.path.start_with?("/hoojah/")
  errors.add(:photo, "must be a Hoojah Cloudinary URL") unless ok
rescue URI::InvalidURIError
  errors.add(:photo, "is not a valid URL")
end

def unread_notifications_count = notifications.unread.count
```
(Keep the existing presence/uniqueness on username; drop the redundant `length: { minimum: 1 }`.)
**Guard existing data:** the `after_create :assign_random_photo` sets a `res.cloudinary.com/hoojah/...`
URL — confirm `User.random_photo` hosts match the validation (they do). Existing users' photos are
Cloudinary; the factory photo must also pass — update the factory if needed.

- [ ] **Step 4: Run → PASS**; full suite green. **Step 5: Commit.**

### Task 1.2: Hujah compose notification callback + has_children? fix; Notification subject_user

**Files:** Modify `app/models/hujah.rb`, `app/models/notification.rb`,
`app/controllers/api/v1/hujahs_controller.rb`. Test: `spec/models/hujah_spec.rb`,
`spec/models/notification_spec.rb`.

- [ ] **Step 1: Failing test** — `spec/models/hujah_compose_spec.rb`:

```ruby
require 'rails_helper'
RSpec.describe 'Hujah response notification', type: :model do
  it 'notifies the parent owner on a reply, once' do
    owner = create(:user); replier = create(:user)
    parent = create(:hujah, user: owner)
    expect {
      replier.hujahs.create!(body: "reply", parent_id: parent.id, vote: 1)
    }.to change { Notification.where(user: owner, category: 'new_hoojah_response').count }.by(1)
  end
  it 'does not notify for a top-level hoojah' do
    expect { create(:hujah, parent_id: nil) }
      .not_to change { Notification.where(category: 'new_hoojah_response').count }
  end
end
```

- [ ] **Step 2: Run → FAIL.**

- [ ] **Step 3: Implement** — `app/models/hujah.rb`:

```ruby
after_create_commit :notify_parent_owner, if: :has_parent?

def has_children? = children.exists?   # was: children != 0 (always true)

private

def notify_parent_owner
  Notification.create!(user_id: parent.user_id, category: :new_hoojah_response,
                       hujah_id: parent.id, subject_user_id: user_id)
end
```
`app/models/notification.rb`: add `belongs_to :subject_user, class_name: "User", optional: true`.
`app/controllers/api/v1/hujahs_controller.rb#create`: **delete** the inline
`Notification.create!(... category: 3 ...)` block (the callback handles it now); keep the render.

- [ ] **Step 4: Run → PASS**; re-run `spec/requests/api/v1/hujahs_spec.rb` (create still notifies). Full
  suite green. **Step 5: Commit.**

---

# Phase 2 — Compose / respond

### Task 2.1: HujahsController#new/#create (HTML) + routes

**Files:** Modify `config/routes.rb`, `app/controllers/hujahs_controller.rb`. Create
`app/views/hujahs/new.html.erb`, `app/views/hujahs/_compose_form.html.erb`,
`app/views/hujahs/_parent_card.html.erb`, `app/views/hujahs/_stance_picker.html.erb`. Test:
`spec/requests/compose_spec.rb`, `spec/system/compose_spec.rb`.

- [ ] **Step 1: Routes** — add:

```ruby
get  "/hoojah/new",           to: "hujahs#new",    as: :new_hujah
get  "/hoojah/:slug/respond", to: "hujahs#new",    as: :respond_hujah
post "/hoojah",               to: "hujahs#create"
```

- [ ] **Step 2: Failing request spec** — `spec/requests/compose_spec.rb`:

```ruby
require 'rails_helper'
RSpec.describe 'Compose', type: :request do
  let(:user) { create(:user) }

  it 'requires login to open the form' do
    get new_hujah_path
    expect(response).to redirect_to(new_user_session_path)
  end
  it 'creates a top-level hoojah and redirects to it' do
    sign_in user
    expect { post "/hoojah", params: { hujah: { body: "My take" } } }
      .to change(Hujah, :count).by(1)
    expect(response).to have_http_status(:see_other)
  end
  it 'creates a response with a stance + notifies the parent owner' do
    sign_in user
    parent = create(:hujah, user: create(:user))
    expect {
      post "/hoojah", params: { hujah: { body: "reply", parent_id: parent.id, vote: 1 } }
    }.to change { Notification.where(category: 'new_hoojah_response').count }.by(1)
    expect(Hujah.last.vote).to eq([1]).or eq(1) # matches the model's vote column shape
  end
  it 'rejects a spoofed missing parent_id' do
    sign_in user
    post "/hoojah", params: { hujah: { body: "x", parent_id: 999_999 } }
    expect(response).to have_http_status(:not_found).or have_http_status(:unprocessable_content)
  end
end
```

- [ ] **Step 3: Run → FAIL.**

- [ ] **Step 4: Controller** — `app/controllers/hujahs_controller.rb` (add):

```ruby
before_action :authenticate_user!, only: [:new, :create]

def new
  skip_authorization
  @parent = params[:slug] && Hujah.friendly.find(params[:slug])
  @hujah = Hujah.new
end

def create
  authorize Hujah
  @parent = params.dig(:hujah, :parent_id).presence && Hujah.find(params[:hujah][:parent_id])
  @hujah = current_user.hujahs.new(compose_params)
  if @hujah.save
    redirect_to hujah_path(@hujah.slug), status: :see_other
  else
    @parent ||= nil
    render :new, status: :unprocessable_content
  end
end

private

def compose_params
  params.require(:hujah).permit(:body, :parent_id, :vote)
end
```
(A missing `parent_id` → `Hujah.find` raises `RecordNotFound` → Rails 404, satisfying the spec. `body`
stored raw.)

- [ ] **Step 5: Views** — compose form (textarea, avatar), parent card + stance picker when `@parent`.
  Faithful port of `git show f5b50de:app/javascript/components/Hujah/form.js`. Stance picker = Tailwind
  radio group (agree/neutral/disagree), default to the current user's vote on the parent
  (`@parent.current_user_vote(logged_in: true, current_user_id: current_user.id)`), no Stimulus needed
  (CSS `:checked`). The Slice 1 feed/show "Add hoojah" buttons link to `respond_hujah_path(hujah.slug)`.

- [ ] **Step 6: Run request spec → PASS.** Write `spec/system/compose_spec.rb` (fill textarea, submit,
  land on the new hoojah) — runs in Phase 6 with cuprite.

- [ ] **Step 7: Full suite green. Commit.**

---

# Phase 3 — Profile (view + edit) + dialog/cloudinary Stimulus

### Task 3.1: `dialog` + `cloudinary_upload` Stimulus + close_dialog Turbo action

**Files:** Create `app/javascript/controllers/{dialog,cloudinary_upload}_controller.js`. Modify
`app/javascript/application.js`.

- [ ] **Step 1:** `dialog_controller.js` per the spec's Stimulus-conventions block (targets `["dialog"]`,
  `open`/`close`/`backdropClose`/`restoreFocus`/`teardown`). `cloudinary_upload_controller.js`
  (`createUploadWidget` in `connect`, arrow callback, hidden target + bubbling input event, `window.cloudinary`
  guard). Register in `application.js`: the `turbo:before-cache` teardown loop + `Turbo.StreamActions.close_dialog`.

- [ ] **Step 2:** No unit test framework for JS here; verify via boot + the Phase 6 system specs. Confirm
  `mise exec ruby@3.4.9 -- bin/rails runner 'app.get "/"; puts app.response.status'` → 200 and importmap
  resolves (no console pin for cloudinary — it's `window.cloudinary`).

- [ ] **Step 3: Commit.**

### Task 3.2: UsersController show/edit/update + /u/:username

**Files:** Modify `config/routes.rb`, create `app/controllers/users_controller.rb`. Create
`app/views/users/{show,edit}.html.erb`, `app/views/users/_profile_header.html.erb`,
`app/views/users/_profile_edit.html.erb` (dialog), `app/views/users/update.turbo_stream.erb`,
`app/views/users/_user_hujah.html.erb`. Test: `spec/requests/profile_spec.rb`, `spec/system/profile_spec.rb`.

- [ ] **Step 1: Routes** —

```ruby
get   "/u/:username",      to: "users#show", as: :profile
get   "/u/:username/edit", to: "users#edit", as: :edit_profile
patch "/u/:username",      to: "users#update"
```

- [ ] **Step 2: Failing request spec** — `spec/requests/profile_spec.rb`:

```ruby
require 'rails_helper'
RSpec.describe 'Profile', type: :request do
  let(:user) { create(:user, username: "rudz") }

  it 'shows a public profile with the user hoojahs' do
    create(:hujah, user: user, body: "hello world")
    get "/u/rudz"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("@rudz").and include("hello world")
  end
  it 'lets the owner update and rejects a bad link (M7) / bad photo host' do
    sign_in user
    patch "/u/rudz", params: { user: { headline: "hi", link: "javascript:alert(1)" } },
          headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
    expect(user.reload.headline).not_to eq("hi") # validation blocked the whole update
    patch "/u/rudz", params: { user: { photo: "https://res.cloudinary.com.evil.com/hoojah/x.jpg" } }
    expect(user.reload.photo).not_to include("evil.com")
  end
  it 'forbids editing someone else' do
    sign_in create(:user)
    patch "/u/rudz", params: { user: { headline: "hacked" } }
    expect(response).to have_http_status(:forbidden)
    expect(user.reload.headline).not_to eq("hacked")
  end
end
```

- [ ] **Step 3: Run → FAIL.**

- [ ] **Step 4: Controller** — `app/controllers/users_controller.rb`:

```ruby
class UsersController < ApplicationController
  before_action :authenticate_user!, only: [:edit, :update]
  before_action :set_user

  def show
    skip_authorization
    @hujahs = @user.hujahs.includes(:user).order(updated_at: :desc)
  end

  def edit
    authorize @user
  end

  def update
    authorize @user
    if @user.update(user_params)
      respond_to do |f|
        f.turbo_stream # update.turbo_stream.erb (refresh header + close_dialog)
        f.html { redirect_to profile_path(@user.username), status: :see_other }
      end
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_user = @user = User.find_by!(username: params[:username])
  def user_params = params.require(:user).permit(:full_name, :username, :location, :link, :headline, :photo)
end
```

- [ ] **Step 5: Views** — profile header (faithful port of `UserProfile.jsx`), the user's hoojahs
  (`_user_hujah` small card), an edit `<dialog>` (`_profile_edit`, wired to `dialog` + `cloudinary_upload`
  controllers, `aria-labelledby="dialog-title-profile-edit"`, `id="<%= dom_id(@user, :edit_dialog) %>"`).
  `update.turbo_stream.erb` replaces the profile header + emits `<turbo-stream action="close_dialog"
  target="<%= dom_id(@user, :edit_dialog) %>">`.

- [ ] **Step 6: Run request spec → PASS**; full suite green. Write `spec/system/profile_spec.rb` (open
  dialog, edit, save, close) for Phase 6. **Step 7: Commit.**

---

# Phase 4 — Notifications

### Task 4.1: NotificationsController + rewrite the API IDOR spec

**Files:** Modify `config/routes.rb`, `app/controllers/api/v1/notifications_controller.rb`. Create
`app/controllers/notifications_controller.rb`, `app/views/notifications/index.html.erb`,
`app/views/notifications/_notification_card.html.erb`, `app/views/notifications/destroy.turbo_stream.erb`.
Rewrite `spec/requests/api/v1/notifications_spec.rb`. Test: `spec/requests/notifications_spec.rb`.

- [ ] **Step 1: Rewrite the API characterization spec to assert SECURE behavior** —
  `spec/requests/api/v1/notifications_spec.rb`:

```ruby
require 'rails_helper'
RSpec.describe 'Api::V1::Notifications', type: :request do
  let(:me) { create(:user) }
  let(:other) { create(:user) }

  it 'index returns only the current user notifications' do
    mine = create(:notification, user: me)
    create(:notification, user: other)
    sign_in me
    get "/api/v1/#{me.username}/notifications"
    body = JSON.parse(response.body)
    ids = body["data"].map { |n| n["id"].to_i }
    expect(ids).to eq([mine.id])
  end
  it 'forbids updating/destroying another user notification' do
    theirs = create(:notification, user: other)
    sign_in me
    put "/api/v1/#{me.username}/notifications/#{theirs.id}", params: { notification: { read: true } }
    expect(response).to have_http_status(:forbidden)
    delete "/api/v1/#{me.username}/notifications/#{theirs.id}"
    expect(response).to have_http_status(:forbidden)
    expect(Notification.exists?(theirs.id)).to be(true)
  end
  it 'requires auth' do
    get "/api/v1/#{me.username}/notifications"
    expect(response).to have_http_status(:unauthorized)
  end
end
```

- [ ] **Step 2: Run → FAIL** (index leaks, update/destroy unguarded).

- [ ] **Step 3: Harden the API controller** — `app/controllers/api/v1/notifications_controller.rb`:

```ruby
class Api::V1::NotificationsController < Api::V1::BaseController
  before_action :authenticate_user!

  def index
    notifications = policy_scope(Notification).order(created_at: :asc).includes(:hujah, :subject_user)
    render json: NotificationSerializer.new(notifications,
      params: { logged_in: true, current_user_id: current_user.id }).serializable_hash
  end

  def update
    authorize notification
    notification.update!(notification_params)
    render json: { status: 200 }
  end

  def destroy
    authorize notification
    notification.destroy
    render json: { message: "Notification deleted!", status: 200 }
  end

  private

  def notification = @notification ||= Notification.find(params[:id])
  def notification_params = params.require(:notification).permit(:read)
end
```
(`find_user`/`@user` deleted.)

- [ ] **Step 4: Run → PASS.**

- [ ] **Step 5: HTML controller + views** — `NotificationsController#index/#update/#destroy` at
  `/notifications`, `/notifications/:id`. `index` = `policy_scope(Notification)`; `update` sets
  `read: true` + `redirect_to hujah_path(...)`; `destroy` → Turbo-Stream removes
  `dom_id(@notification)`. Card partial faithful to `Notifications/card.js` (3 categories, read/unread
  border, Lucide icons, trash). Add `spec/requests/notifications_spec.rb` (list own; read→redirect;
  delete→turbo_stream; another user's → 403). Routes:

```ruby
get    "/notifications",     to: "notifications#index",   as: :notifications
patch  "/notifications/:id", to: "notifications#update",  as: :notification
delete "/notifications/:id", to: "notifications#destroy"
```

- [ ] **Step 6: Run → PASS**; full suite green. **Step 7: Commit.**

---

# Phase 5 — Flag + Share + throttles

### Task 5.1: FlagsController (HTML + API fix) + flag dialog

**Files:** Modify `config/routes.rb`, `app/controllers/api/v1/flags_controller.rb`. Create
`app/controllers/flags_controller.rb`, `app/views/flags/create.turbo_stream.erb`,
`app/views/hujahs/_flag_dialog.html.erb`. Modify `spec/requests/api/v1/flags_spec.rb`. Test:
`spec/requests/flag_spec.rb`.

- [ ] **Step 1: Extend the API flags spec** — assert unauth→401 and a posted `user_id` is ignored
  (flag records under `current_user`).
- [ ] **Step 2: Run → FAIL** (no auth guard).
- [ ] **Step 3: Fix API** — `Api::V1::FlagsController`: `before_action :authenticate_user!`; `create` →
  `authorize Flag`; `flag_params` drops `:user_id` (permit `:hujah_id, :subject`).
- [ ] **Step 4: HTML** — route `post "/hoojah/:slug/flags", to: "flags#create", as: :hujah_flags`;
  `FlagsController#create` (`authenticate_user!`, `authorize Flag`, `current_user.flags.create!(hujah:, subject:)`)
  → `create.turbo_stream.erb` emits `close_dialog` + a confirmation. `_flag_dialog` = native `<dialog>`
  (dialog controller, `id="<%= dom_id(@hujah, :flag_dialog) %>"`, 3 reason buttons) on the show page.
- [ ] **Step 5: Run → PASS**; full suite green. **Step 6: Commit.**

### Task 5.2: Share menu + share_controller + rack-attack throttles

**Files:** Create `app/javascript/controllers/share_controller.js`,
`app/views/hujahs/_share_menu.html.erb`. Modify `config/initializers/rack_attack.rb`,
`app/views/hujahs/_hujah_header.html.erb`. Test: `spec/requests/share_spec.rb` (menu links present),
`spec/requests/rate_limit_spec.rb` (extend).

- [ ] **Step 1:** `_share_menu` = server-rendered `<a href>` intent links (wa.me / x.com/intent /
  t.me/share / reddit / facebook sharer / mailto) from the hoojah's absolute URL + body, + a `hidden`
  native-share button (`share_controller`, `values` title/text/url). Wire into `_hujah_header`.
- [ ] **Step 2:** `share_controller.js` per the conventions block (feature-detect, swallow AbortError).
- [ ] **Step 3: rack-attack** — add throttles: `throttle('compose/user', limit: 20, period: 1.minute)`
  keyed on the warden user for `POST /hoojah`; `throttle('flags/user', limit: 15, period: 1.minute)` for
  `POST /hoojah/*/flags`. Extend `spec/requests/rate_limit_spec.rb`.
- [ ] **Step 4:** Request spec asserts the share links render with no JS; run → PASS. **Step 5: Commit.**

---

# Phase 6 — System tests, gates, cleanup

### Task 6.1: cuprite system specs

**Files:** Create `spec/system/{compose,profile,flag,notifications,share}_spec.rb`.

- [ ] **Step 1:** Run `mise exec ruby@3.4.9 -- bin/rails db:test:prepare` first (clean DB).
- [ ] **Step 2:** System specs: compose→redirect to new hoojah; profile edit dialog opens, saves,
  closes (assert `close_dialog` fired — header updated, dialog `open` false); the Cloudinary widget iframe
  can open (or stub the widget — assert the button is wired); flag dialog opens + submit closes it;
  notification delete removes the card via Turbo-Stream; Web Share fallback menu shows links when
  `navigator.share` is absent (default in headless Chrome).
- [ ] **Step 3:** Run `RAILS_ENV=test RUBYOPT='-W0' … rspec spec/system` → all pass (Chrome present).
  If a Cloudinary iframe can't load in CI, assert the button/hidden-field wiring instead of a live upload.
- [ ] **Step 4: Commit.**

### Task 6.2: StandardRB + gates + docs

**Files:** run standardrb; `README.md`, `docs/superpowers/HANDOVER.md`.

- [ ] **Step 1:** `mise exec ruby@3.4.9 -- bundle exec standardrb --fix`; re-run full suite (green).
- [ ] **Step 2: Gates** — brakeman 0; bundler-audit clean. Fix any brakeman finding (esp. the new share
  links / redirects — ensure no open-redirect via the notification redirect target, which must be
  `hujah_path`, not a user-supplied URL).
- [ ] **Step 3:** `grep -rniE "react|params\[:user_id\]" app config | grep -v cloudinary` → no hits.
- [ ] **Step 4: Docs** — README (new screens); HANDOVER "Slice 2 — DONE" section: what shipped, the
  Pundit adoption, M7 closed, still-open (vote array→scalar, serializer N+1/prosopite, ActionCable,
  master-key, rack-cors, Project 3).
- [ ] **Step 5: Full suite green; brakeman 0; bundler-audit clean; standardrb clean. Commit.**

---

## Definition of done

- Compose/respond, profile view+edit, notifications, flag, share all work in Hotwire (faithful port).
- Pundit adopted; Slice 1 IDOR checks migrated; notifications IDOR/leak closed on HTML + API; flags
  hardened; **`link` XSS (M7) closed**; photo host-validated (exact host).
- Auth flows (login/signup/logout/password/account-update) unaffected by `verify_authorized`.
- Full suite green (incl. cuprite system specs); brakeman 0; bundler-audit clean; StandardRB clean.

## Deferred

Vote array→scalar; serializer N+1 + prosopite; ActionCable push; `require_master_key`; `rack-cors`;
Project 3 (Hotwire Native).
