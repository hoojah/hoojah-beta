# Cloudinary + Google Auth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move profile-photo uploads to the `cloudinary` gem + ActiveStorage (server-side), and add Google (OmniAuth) sign-up/sign-in with email auto-linking.

**Architecture:** Track A adds the `cloudinary` gem as an ActiveStorage service; `User` gains a `has_one_attached :avatar` that takes precedence over the legacy `photo` string column, and the old client-side unsigned widget is removed. Track B adds `omniauth-google-oauth2`, `provider`/`uid` columns, a Devise callbacks controller, and wires the existing "Continue with Google" login button (+ a new one on signup).

**Tech Stack:** Rails 8.1, Ruby 3.4.9, Devise 5, Pundit, ActiveStorage, Cloudinary gem, omniauth-google-oauth2, RSpec + FactoryBot + Cuprite system specs, Tailwind v4, importmap Stimulus.

**Working directory:** `/Users/deepsight/.config/superpowers/worktrees/hoojah-beta/cloudinary-google-auth` (worktree on branch `feature/cloudinary-google-auth`, off `master`).

**All commands** are prefixed with the test env / warning suppression the project uses. Ruby is mise-managed and auto-activates in this dir.

**Test-DB note (read once):** the Postgres `hoojah_test` DB is shared with the main checkout, so `db:test:prepare` (which purges) fails with `PG::ObjectInUse`. **Never purge.** Apply schema changes to the test DB with `RAILS_ENV=test bin/rails db:migrate` (additive, no purge). If a migration blocks on a lock, terminate idle connections first:
```bash
psql "$(bin/rails runner 'print ActiveRecord::Base.connection_db_config.configuration_hash[:url] || ENV["DATABASE_URL"]' 2>/dev/null)" -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='hoojah_test' AND pid <> pg_backend_pid() AND state='idle';" 2>/dev/null || true
```

---

## File Structure

**Track A (Cloudinary):**
- Modify: `Gemfile` (+ `cloudinary`)
- Modify: `config/storage.yml` (+ `cloudinary:` service)
- Modify: `config/environments/development.rb:32`, `production.rb:51` (service → `:cloudinary`); `test.rb:45` stays `:test`
- Create: `db/migrate/<ts>_create_active_storage_tables.active_storage.rb` (generated)
- Modify: `app/models/user.rb` (+ `has_one_attached :avatar`, + attachment validation)
- Modify: `app/helpers/design_system_helper.rb` (+ `ds_avatar_url`)
- Modify: `app/views/ui/_avatar.html.erb` (attached avatar → photo → tile)
- Modify: `app/views/users/_profile_edit.html.erb` (file_field, drop widget wiring, update docstring)
- Modify: `app/controllers/users_controller.rb:75-77` (permit `:avatar`)
- Delete: `app/javascript/controllers/cloudinary_upload_controller.js`
- Modify: `app/views/layouts/application.html.erb:33-39` (drop widget script + comment)
- Modify: `config/initializers/content_security_policy.rb` (drop widget/api Cloudinary hosts, keep `res.cloudinary.com` img)

**Track B (Google):**
- Modify: `Gemfile` (+ `omniauth-google-oauth2`, `omniauth-rails_csrf_protection`)
- Create: `db/migrate/<ts>_add_omniauth_to_users.rb`
- Modify: `app/models/user.rb` (+ `:omniauthable`, `from_omniauth`, `generate_username`)
- Modify: `config/routes.rb:21-24` (+ `omniauth_callbacks` controller)
- Modify: `config/initializers/devise.rb` (+ `config.omniauth :google_oauth2`)
- Create: `app/controllers/users/omniauth_callbacks_controller.rb`
- Modify: `app/views/devise/sessions/new.html.erb:60-71` (wire existing Google button)
- Modify: `app/views/devise/registrations/new.html.erb:85` (add Google button)
- Test support: `spec/support/omniauth.rb` (OmniAuth test mode)

---

# TRACK A — Cloudinary gem + ActiveStorage

## Task A1: Add cloudinary gem + ActiveStorage service config

**Files:**
- Modify: `Gemfile`
- Modify: `config/storage.yml`
- Modify: `config/environments/development.rb:32`, `config/environments/production.rb:51`

- [ ] **Step 1: Add the gem.** In `Gemfile`, after the `devise` line (line 18), add:
```ruby
# Cloudinary storage service for ActiveStorage (profile photos)
gem "cloudinary", "~> 2.2"
```

- [ ] **Step 2: Install.** Run: `bundle install`
Expected: `Bundle complete!`, `cloudinary` resolves.

- [ ] **Step 3: Add the storage service.** Append to `config/storage.yml`:
```yaml
cloudinary:
  service: Cloudinary
```

- [ ] **Step 4: Point dev + prod at Cloudinary.** In `config/environments/development.rb` change line 32 from `config.active_storage.service = :local` to:
```ruby
  config.active_storage.service = :cloudinary
```
In `config/environments/production.rb` change line 51 the same way:
```ruby
  config.active_storage.service = :cloudinary
```
Leave `config/environments/test.rb:45` as `config.active_storage.service = :test`.

- [ ] **Step 5: Verify boot (no CLOUDINARY_URL needed to boot).** Run:
```bash
RAILS_ENV=test bin/rails runner 'puts ActiveStorage::Blob.service.class' 2>&1 | tail -3
```
Expected: prints `ActiveStorage::Service::DiskService` (test env → disk). No crash = gem loaded cleanly.

- [ ] **Step 6: Commit.**
```bash
git add Gemfile Gemfile.lock config/storage.yml config/environments/development.rb config/environments/production.rb
git commit -m "Slice: add cloudinary gem + ActiveStorage service"
```

## Task A2: Install ActiveStorage tables

**Files:**
- Create: `db/migrate/<ts>_create_active_storage_tables.active_storage.rb`
- Modify: `db/schema.rb`

- [ ] **Step 1: Generate the migration.** Run: `bin/rails active_storage:install`
Expected: "Copied migration …create_active_storage_tables.active_storage.rb".

- [ ] **Step 2: Migrate dev + test.** Run:
```bash
bin/rails db:migrate
RAILS_ENV=test bin/rails db:migrate
```
Expected: creates `active_storage_blobs`, `active_storage_attachments`, `active_storage_variant_records` in both. `db/schema.rb` now lists them.

- [ ] **Step 3: Verify.** Run:
```bash
RAILS_ENV=test bin/rails runner 'puts ActiveRecord::Base.connection.table_exists?(:active_storage_blobs)'
```
Expected: `true`.

- [ ] **Step 4: Commit.**
```bash
git add db/migrate db/schema.rb
git commit -m "Slice: install ActiveStorage tables"
```

## Task A3: User#avatar attachment + validation (TDD)

**Files:**
- Modify: `app/models/user.rb`
- Test: `spec/models/user_spec.rb`

- [ ] **Step 1: Write failing tests.** Append to `spec/models/user_spec.rb` (inside the top-level `describe User` block):
```ruby
  describe "avatar attachment" do
    let(:user) { create(:user) }
    let(:png) do
      Rack::Test::UploadedFile.new(
        StringIO.new("\x89PNG\r\n\x1a\n".b + ("0".b * 100)), "image/png", original_filename: "a.png"
      )
    end

    it "accepts an image attachment" do
      user.avatar.attach(io: StringIO.new("fakeimg"), filename: "a.png", content_type: "image/png")
      expect(user).to be_valid
      expect(user.avatar).to be_attached
    end

    it "rejects a non-image content type" do
      user.avatar.attach(io: StringIO.new("nope"), filename: "a.txt", content_type: "text/plain")
      expect(user).not_to be_valid
      expect(user.errors[:avatar].join).to match(/PNG|image/i)
    end

    it "rejects an oversized image" do
      user.avatar.attach(io: StringIO.new("x" * (6 * 1024 * 1024)), filename: "big.png", content_type: "image/png")
      expect(user).not_to be_valid
      expect(user.errors[:avatar].join).to match(/5 MB|smaller/i)
    end
  end
```

- [ ] **Step 2: Run — expect failure.** Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/user_spec.rb -e "avatar attachment"`
Expected: FAIL (`avatar` not defined / no validation).

- [ ] **Step 3: Implement.** In `app/models/user.rb`, after the `devise` line (line 30) add the attachment; near the other constants add limits; after `validate :photo_from_cloudinary` (line 45) add the validator; in the private section add the method.

After line 30:
```ruby
  has_one_attached :avatar
```
Near `RESERVED_USERNAMES` (after line ~35), add:
```ruby
  MAX_AVATAR_BYTES = 5.megabytes
  ALLOWED_AVATAR_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze
```
After line 45 (`validate :photo_from_cloudinary`):
```ruby
  validate :avatar_is_valid_image
```
In the `private` section (near `photo_from_cloudinary`), add:
```ruby
  def avatar_is_valid_image
    return unless avatar.attached?
    unless ALLOWED_AVATAR_TYPES.include?(avatar.blob.content_type)
      errors.add(:avatar, "must be a PNG, JPEG, GIF, or WebP image")
    end
    if avatar.blob.byte_size > MAX_AVATAR_BYTES
      errors.add(:avatar, "must be smaller than 5 MB")
    end
  end
```

- [ ] **Step 4: Run — expect pass.** Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/user_spec.rb -e "avatar attachment"`
Expected: 3 examples, 0 failures.

- [ ] **Step 5: Commit.**
```bash
git add app/models/user.rb spec/models/user_spec.rb
git commit -m "Slice: User#avatar attachment with image validation"
```

## Task A4: Avatar URL helper + _avatar partial (TDD)

**Files:**
- Modify: `app/controllers/application_controller.rb` (include `ActiveStorage::SetCurrent`)
- Modify: `app/helpers/design_system_helper.rb`
- Modify: `app/views/ui/_avatar.html.erb`
- Test: `spec/helpers/design_system_helper_spec.rb` (**already exists** — append inside the existing `RSpec.describe DesignSystemHelper` block, do NOT recreate the file or re-declare `require`/`RSpec.describe`)

- [ ] **Step 1: Write failing helper test.** Inside the existing `RSpec.describe DesignSystemHelper, type: :helper do` block in `spec/helpers/design_system_helper_spec.rb`, add a new `describe "#ds_avatar_url"` block:
```ruby
  describe "#ds_avatar_url" do
    around do |ex|
      old = ActiveStorage::Current.url_options
      ActiveStorage::Current.url_options = { host: "http://test.host" }
      ex.run
      ActiveStorage::Current.url_options = old
    end

    it "returns the attached avatar url when attached" do
      user = create(:user)
      user.avatar.attach(io: StringIO.new("img"), filename: "a.png", content_type: "image/png")
      # freeze_time so the two DiskService#url calls generate byte-identical signed URLs
      freeze_time do
        expect(helper.ds_avatar_url(user)).to eq(user.avatar.url)
      end
    end

    it "falls back to the photo string when no avatar is attached" do
      user = create(:user)
      user.update_column(:photo, "https://res.cloudinary.com/hoojah/image/upload/x.gif")
      expect(helper.ds_avatar_url(user)).to eq("https://res.cloudinary.com/hoojah/image/upload/x.gif")
    end

    it "returns nil when neither is present" do
      user = create(:user)
      user.update_column(:photo, "")
      expect(helper.ds_avatar_url(user)).to be_nil
    end
  end
```
(Close only the new `describe` block — the surrounding `RSpec.describe DesignSystemHelper` block already exists.)

- [ ] **Step 2: Run — expect failure.** Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/helpers/design_system_helper_spec.rb`
Expected: FAIL (`ds_avatar_url` undefined).

- [ ] **Step 3a: Set ActiveStorage url_options per-request.** In `app/controllers/application_controller.rb`, add `include ActiveStorage::SetCurrent` (near the top, alongside the existing includes). Without it, rendering an attached avatar via the Disk service in any request/system spec raises `ArgumentError: Cannot generate URL … set ActiveStorage::Current.url_options`. Harmless in production (Cloudinary URLs don't need it).

- [ ] **Step 3b: Implement helper.** In `app/helpers/design_system_helper.rb` add:
```ruby
  # Resolve a user's avatar image URL: prefer an uploaded ActiveStorage avatar,
  # fall back to the legacy Cloudinary `photo` string, else nil (caller renders the tile).
  def ds_avatar_url(user)
    return user.avatar.url if user.avatar.attached?
    user.photo.presence
  end
```

- [ ] **Step 4: Run — expect pass.** Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/helpers/design_system_helper_spec.rb`
Expected: 3 examples, 0 failures.

- [ ] **Step 5: Update the partial.** In `app/views/ui/_avatar.html.erb`, the actual line 42 is `<% tile = local_assigns[:variant] == :tile || user.photo.blank? %>` (glued to the closing `%>` of the doc comment — preserve `local_assigns[:variant]`). Replace that line with two lines that resolve the URL via the helper and use blank-url as the tile trigger:
```erb
<% avatar_url = ds_avatar_url(user) %>
<% tile = local_assigns[:variant] == :tile || avatar_url.blank? %>
```
and in the photo branch replace `image_tag user.photo, ...` with `image_tag avatar_url, ...` (keep the existing `class:` / `alt:` / size attributes exactly).

- [ ] **Step 5b: Prevent an avatar N+1.** `ds_avatar_url` calls `user.avatar.attached?`, which lazily queries `active_storage_attachments` per user unless preloaded. Grep app code for user-list loads that render `ui/_avatar` (`grep -rn "includes(:user)\|preload(:user)\|with(:user)" app/`), and for each call site that renders avatars, add the attachment to the include, e.g. `includes(user: {avatar_attachment: :blob})` (or `.with_attached_avatar` on a `User` relation). Keep the change minimal and only where avatars are actually rendered in a list. Note in the commit which call sites changed.

- [ ] **Step 6: Run avatar-rendering specs.** Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/helpers/design_system_helper_spec.rb` and any partial spec if present.
Expected: PASS.

- [ ] **Step 7: Commit.**
```bash
git add app/helpers/design_system_helper.rb app/views/ui/_avatar.html.erb spec/helpers/design_system_helper_spec.rb
git commit -m "Slice: ds_avatar_url helper; _avatar prefers attached avatar"
```

## Task A5: Profile-edit file upload; remove client-side widget (TDD)

**Files:**
- Modify: `app/controllers/users_controller.rb:75-77`
- Modify: `app/views/users/_profile_edit.html.erb`
- Delete: `app/javascript/controllers/cloudinary_upload_controller.js`
- Modify: `app/views/layouts/application.html.erb:33-39`
- Modify: `config/initializers/content_security_policy.rb`
- Modify: `spec/system/profile_spec.rb` (rewrite the old-widget assertion)
- Modify: `spec/support/capybara.rb` (Cuprite host blocklist)
- Test: `spec/requests/profile_spec.rb` and `spec/system/profile_spec.rb`

- [ ] **Step 1: Write failing request test.** In the existing `spec/requests/profile_spec.rb` (the profile-update request spec), add:
```ruby
  it "attaches an uploaded avatar via multipart PATCH" do
    user = create(:user)
    sign_in user
    file = Rack::Test::UploadedFile.new(
      StringIO.new("\x89PNG\r\n\x1a\n".b + ("0".b * 50)), "image/png", original_filename: "me.png"
    )
    patch "/u/#{user.username}", params: { user: { avatar: file } }
    expect(user.reload.avatar).to be_attached
  end
```

- [ ] **Step 2: Run — expect failure.** Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/profile_spec.rb -e "attaches an uploaded avatar"`
Expected: FAIL (avatar not permitted → not attached).

- [ ] **Step 3: Permit `:avatar`.** In `app/controllers/users_controller.rb` change the `user_params` permit list (line 76) to include `:avatar`:
```ruby
    params.require(:user).permit(:full_name, :username, :location, :link, :headline, :photo, :private, :avatar)
```

- [ ] **Step 4: Run — expect pass.** Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/profile_spec.rb -e "attaches an uploaded avatar"`
Expected: PASS.

- [ ] **Step 5: Swap the form UI to a file field.** In `app/views/users/_profile_edit.html.erb`:
  - Line 57: change `data-controller="dialog cloudinary-upload"` to `data-controller="dialog"`.
  - Ensure the form (line 78) is multipart — `form_with` is multipart automatically when it contains a file field, but set it explicitly: change to `form_with model: user, url: profile_path(user.username), method: :patch, html: { multipart: true }, class: "p-4" do |f|`.
  - Replace the "Update photo" button (lines 94-98) and the hidden photo field (line 99) with:
```erb
        <%= f.label :avatar, "Photo", class: "block text-xs font-semibold text-faint mb-1" %>
        <%= f.file_field :avatar, accept: "image/png,image/jpeg,image/gif,image/webp",
              class: "block text-sm" %>
```
  - Update the frozen docstring (lines 53-55): remove the references to the Cloudinary upload button / hidden photo field / `cloudinary-upload` controller, and note that photo upload is now a plain multipart `file_field :avatar` PATCHed to `/u/:username` (ActiveStorage + Cloudinary service). Keep the freeze on the PATCH URL and `dom_id(user, :edit_dialog)`.

- [ ] **Step 6: Delete the Stimulus controller.** Run:
```bash
git rm app/javascript/controllers/cloudinary_upload_controller.js
```

- [ ] **Step 7: Remove the widget `<script>` from the layout.** In `app/views/layouts/application.html.erb`, remove line 39 (`<script src="//widget.cloudinary.com/global/all.js" ...>`). Since Drift still needs the `unless Rails.env.test?` wrapper (lines 38, 40+), keep the wrapper but update the comment (lines 33-37) to drop the Cloudinary mention (now "Drift live chat" only). If Drift is the only remaining item, keep the conditional block for Drift.

- [ ] **Step 8: Trim CSP.** In `config/initializers/content_security_policy.rb` remove the Cloudinary widget/api hosts that the removed widget needed, keeping `res.cloudinary.com` for image delivery:
  - `script_src` (line 5): remove `"https://widget.cloudinary.com"`.
  - `connect_src` (line 8): remove `"https://api.cloudinary.com"`.
  - `frame_src` (line 9): remove `"https://widget.cloudinary.com"` (leave Drift; if it becomes empty, set `policy.frame_src "https://*.drift.com"`).
  - **Keep** `img_src ... "https://res.cloudinary.com"` (line 7) — avatars (legacy + new AS-Cloudinary) are served from there.

- [ ] **Step 9: Rewrite the old-widget system spec.** `spec/system/profile_spec.rb` has an example (~line 45) `"wires the Cloudinary photo button to a hidden field the widget fills"` asserting `have_button("Update photo", disabled: :all)` and `have_field("user[photo]", type: :hidden)`. Both are removed. Rewrite that example to assert the new file field, e.g.:
```ruby
    it "offers a photo file field on the edit form" do
      # ...open the edit dialog as the existing example does...
      expect(page).to have_field("user[avatar]", type: :file)
    end
```
Keep the dialog-opening setup identical to the surrounding examples.

- [ ] **Step 9b: Update the Cuprite host blocklist.** In `spec/support/capybara.rb`, remove the `widget.cloudinary.com` / `api.cloudinary.com` entries from the blocked-hosts list and update the accompanying comment (they're gone from the app now). **Keep `res.cloudinary.com`** — legacy `photo` URLs still render from there.

- [ ] **Step 9c: Run the profile specs.** Run:
```bash
rm -rf public/assets
RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/profile_spec.rb spec/system/profile_spec.rb 2>&1 | tail -25
```
Expected: profile edit/update specs PASS; nothing references the removed `cloudinary-upload` controller.

- [ ] **Step 10: Commit.**
```bash
git add -A
git commit -m "Slice: profile avatar via multipart file_field; remove client-side Cloudinary widget"
```

---

# TRACK B — Google Sign-up / Sign-in

## Task B1: Add OmniAuth gems

**Files:**
- Modify: `Gemfile`

- [ ] **Step 1: Add gems.** In `Gemfile`, after the `cloudinary` line, add:
```ruby
# Google OAuth2 sign-in via Devise/OmniAuth
gem "omniauth-google-oauth2", "~> 1.1"
gem "omniauth-rails_csrf_protection", "~> 1.0"
```

- [ ] **Step 2: Install.** Run: `bundle install`
Expected: `Bundle complete!`; both gems resolve.

- [ ] **Step 3: Commit.**
```bash
git add Gemfile Gemfile.lock
git commit -m "Slice: add omniauth-google-oauth2 + rails_csrf_protection"
```

## Task B2: provider/uid migration

**Files:**
- Create: `db/migrate/<ts>_add_omniauth_to_users.rb`
- Modify: `db/schema.rb`

- [ ] **Step 1: Generate.** Run: `bin/rails g migration AddOmniauthToUsers provider:string uid:string`

- [ ] **Step 2: Edit for a concurrent unique index.** Replace the generated migration body with:
```ruby
class AddOmniauthToUsers < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :users, :provider, :string
    add_column :users, :uid, :string
    add_index :users, [:provider, :uid], unique: true, algorithm: :concurrently
  end
end
```

- [ ] **Step 3: Migrate dev + test.** Run:
```bash
bin/rails db:migrate
RAILS_ENV=test bin/rails db:migrate
```
Expected: `users` gains `provider`, `uid`, and a unique `[provider, uid]` index. (Existing rows are NULL,NULL — Postgres treats NULLs as distinct, so no uniqueness collision.)

- [ ] **Step 4: Commit.**
```bash
git add db/migrate db/schema.rb
git commit -m "Slice: add provider/uid to users"
```

## Task B3: User omniauthable + from_omniauth + generate_username (TDD)

**Files:**
- Modify: `app/models/user.rb`
- Test: `spec/models/user_spec.rb`

- [ ] **Step 1: Write failing tests.** Append to `spec/models/user_spec.rb`:
```ruby
  describe ".generate_username" do
    it "slugifies to allowed characters" do
      expect(User.generate_username("Jane.Doe")).to eq("janedoe")
    end

    it "appends a numeric suffix on collision" do
      create(:user, username: "janedoe")
      expect(User.generate_username("jane.doe")).to eq("janedoe2")
    end

    it "avoids reserved usernames" do
      expect(User.generate_username("admin")).not_to eq("admin")
    end
  end

  describe ".from_omniauth" do
    def auth(email:, name: "Jane Doe", uid: "123")
      OmniAuth::AuthHash.new(
        provider: "google_oauth2", uid: uid,
        info: { email: email, name: name }
      )
    end

    it "creates a new user with a generated username and random password" do
      expect {
        @user = User.from_omniauth(auth(email: "new.person@gmail.com"))
      }.to change(User, :count).by(1)
      expect(@user).to be_persisted
      expect(@user.username).to eq("newperson")
      expect(@user.provider).to eq("google_oauth2")
      expect(@user.uid).to eq("123")
    end

    it "auto-links to an existing account by email" do
      existing = create(:user, email: "taken@gmail.com")
      expect {
        found = User.from_omniauth(auth(email: "TAKEN@gmail.com", uid: "999"))
        expect(found.id).to eq(existing.id)
      }.not_to change(User, :count)
      expect(existing.reload.uid).to eq("999")
    end

    it "returns the same user on repeat login by provider+uid" do
      first = User.from_omniauth(auth(email: "again@gmail.com", uid: "555"))
      expect {
        second = User.from_omniauth(auth(email: "again@gmail.com", uid: "555"))
        expect(second.id).to eq(first.id)
      }.not_to change(User, :count)
    end
  end
```

- [ ] **Step 2: Run — expect failure.** Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/user_spec.rb -e "omniauth" -e "generate_username"`
Expected: FAIL (methods undefined).

- [ ] **Step 3: Implement.** In `app/models/user.rb`:
  - Change the `devise` call (lines 29-30) to add `:omniauthable`:
```ruby
  devise :database_authenticatable, :registerable,
    :recoverable, :rememberable, :validatable,
    :omniauthable, omniauth_providers: [:google_oauth2]
```
  - Add class methods (near the top of the class, after `self.random_photo`):
```ruby
  def self.from_omniauth(auth)
    if (user = find_by(provider: auth.provider, uid: auth.uid))
      return user
    end

    email = auth.info.email.to_s.downcase.strip
    if (user = find_by(email: email))
      user.update_columns(provider: auth.provider, uid: auth.uid)
      return user
    end

    # Seed the username from the email local-part (matches the spec), falling back to the name.
    seed = email.split("@").first.presence || auth.info.name
    create(
      provider: auth.provider,
      uid: auth.uid,
      email: email,
      full_name: auth.info.name.presence || email.split("@").first,
      username: generate_username(seed),
      password: Devise.friendly_token[0, 20]
    )
  end

  def self.generate_username(seed)
    base = seed.to_s.downcase.gsub(/[^a-z0-9_]/, "")
    base = "user" if base.blank? || RESERVED_USERNAMES.include?(base)
    candidate = base
    n = 1
    while exists?(username: candidate) || RESERVED_USERNAMES.include?(candidate)
      n += 1
      candidate = "#{base}#{n}"
    end
    candidate
  end
```

- [ ] **Step 4: Run — expect pass.** Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/user_spec.rb -e "omniauth" -e "generate_username"`
Expected: all PASS.

- [ ] **Step 5: Commit.**
```bash
git add app/models/user.rb spec/models/user_spec.rb
git commit -m "Slice: User.from_omniauth + generate_username; omniauthable"
```

## Task B4: Routes + Devise config + callbacks controller (TDD)

**Files:**
- Modify: `config/routes.rb:21-24`
- Modify: `config/initializers/devise.rb`
- Create: `app/controllers/users/omniauth_callbacks_controller.rb`
- Create: `spec/support/omniauth.rb`
- Test: `spec/requests/omniauth_callbacks_spec.rb` (create)

- [ ] **Step 1: Add OmniAuth test-mode support.** Create `spec/support/omniauth.rb`:
```ruby
OmniAuth.config.test_mode = true
OmniAuth.config.logger = Rails.logger

RSpec.configure do |config|
  config.before(:each) do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end
end

def mock_google_auth(email:, name: "Jane Doe", uid: "abc123")
  OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
    provider: "google_oauth2", uid: uid,
    info: { email: email, name: name }
  )
end
```
Ensure `spec/rails_helper.rb` loads `spec/support/**/*.rb` (it does via the standard `Dir[Rails.root.join("spec/support/**/*.rb")].each { |f| require f }`; if that line is commented out, uncomment it).

- [ ] **Step 2: Write failing request test.** Create `spec/requests/omniauth_callbacks_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "Google OmniAuth callbacks", type: :request do
  it "signs in and redirects on success" do
    mock_google_auth(email: "oauth.new@gmail.com", uid: "u1")
    post "/auth/google_oauth2"          # request phase (POST, CSRF-protected)
    follow_redirect!                     # → /auth/google_oauth2/callback
    expect(response).to redirect_to(root_path).or redirect_to(dashboard_path)
    expect(User.find_by(uid: "u1")).to be_present
  end

  it "redirects to login on failure" do
    OmniAuth.config.mock_auth[:google_oauth2] = :invalid_credentials
    post "/auth/google_oauth2"
    follow_redirect!
    expect(response).to redirect_to(new_user_session_path)
  end
end
```
(If `dashboard_path` is not the post-sign-in target, adjust to the app's `after_sign_in_path_for`; check `ApplicationController`/routes for the root. `root_path` is a safe fallback.)

- [ ] **Step 3: Run — expect failure.** Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/omniauth_callbacks_spec.rb`
Expected: FAIL (route/controller missing).

- [ ] **Step 4: Register the provider.** In `config/initializers/devise.rb`, near the commented omniauth example (line ~277), add inside the `Devise.setup` block:
```ruby
  config.omniauth :google_oauth2, ENV["GOOGLE_CLIENT_ID"], ENV["GOOGLE_CLIENT_SECRET"],
    { scope: "email,profile", prompt: "select_account" }
```

- [ ] **Step 5: Add the callbacks controller to routes.** In `config/routes.rb`, change the `devise_for` block (lines 21-24) to:
```ruby
devise_for :users,
  controllers: {
    registrations: "users/registrations",
    omniauth_callbacks: "users/omniauth_callbacks"
  },
  path: "",
  path_names: {sign_in: "login", sign_out: "logout", sign_up: "signup"}
```

- [ ] **Step 6: Create the callbacks controller.** Create `app/controllers/users/omniauth_callbacks_controller.rb`:
```ruby
class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  # Devise controller → ApplicationController's verify_authorized is auto-skipped.
  def google_oauth2
    @user = User.from_omniauth(request.env["omniauth.auth"])

    if @user&.persisted?
      sign_in_and_redirect @user, event: :authentication
      set_flash_message(:notice, :success, kind: "Google") if is_navigational_format?
    else
      messages = @user&.errors&.full_messages&.join("\n").presence || "Could not sign you in with Google."
      redirect_to new_user_session_path, alert: messages
    end
  end

  def failure
    redirect_to new_user_session_path, alert: "Could not sign you in with Google."
  end
end
```

- [ ] **Step 7: Run — expect pass.** Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/omniauth_callbacks_spec.rb`
Expected: PASS. (If the success test's redirect target mismatches, set it to the app's real post-login path.)

- [ ] **Step 8: Commit.**
```bash
git add config/routes.rb config/initializers/devise.rb app/controllers/users/omniauth_callbacks_controller.rb spec/support/omniauth.rb spec/requests/omniauth_callbacks_spec.rb
git commit -m "Slice: Google omniauth routes, config, callbacks controller"
```

## Task B5: "Continue with Google" buttons (TDD)

**Files:**
- Modify: `app/views/devise/sessions/new.html.erb:60-71`
- Modify: `app/views/devise/registrations/new.html.erb:85`
- Test: `spec/system/google_sign_in_spec.rb` (create)

- [ ] **Step 1: Write failing system test.** Create `spec/system/google_sign_in_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "Sign in with Google", type: :system, js: true do
  it "shows the button on login and signs the user in" do
    mock_google_auth(email: "sys.oauth@gmail.com", uid: "sys1", name: "Sys Oauth")
    OmniAuth.config.test_mode = true

    visit "/login"
    expect(page).to have_button("Continue with Google").or have_link("Continue with Google")
    click_on "Continue with Google"

    expect(page).to have_current_path(root_path).or have_current_path(dashboard_path)
    expect(User.find_by(uid: "sys1")).to be_present
  end

  it "shows the button on signup" do
    visit "/signup"
    expect(page).to have_button("Continue with Google").or have_link("Continue with Google")
  end
end
```

- [ ] **Step 2: Run — expect failure.** Run: `rm -rf public/assets && RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/system/google_sign_in_spec.rb`
Expected: FAIL (signup has no button; login button is inert `type="button"`).

- [ ] **Step 3: Wire the login button.** First update the header comment at `app/views/devise/sessions/new.html.erb:17-19` — it currently states the Google button is intentionally INERT ("do not turn it into a link/`button_to`…"). Rewrite it to say the button is now wired to Devise's `google_oauth2` OmniAuth request phase. Then replace the inert button block (lines 68-71) with a `button_to` POST (Turbo disabled so the request-phase redirect to Google is a full navigation):
```erb
  <%= button_to user_google_oauth2_omniauth_authorize_path,
        method: :post,
        form: { data: { turbo: false } },
        class: "w-full h-[52px] rounded-xl border border-field bg-card text-ink font-bold text-[14.5px] flex items-center justify-center gap-2.5" do %>
    <svg width="19" height="19" viewBox="0 0 48 48" aria-hidden="true"><path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/><path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/><path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/><path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/></svg>
    Continue with Google
  <% end %>
```

- [ ] **Step 4: Add the signup button.** In `app/views/devise/registrations/new.html.erb`, after the submit button (line 85), add an "or" divider + the same `button_to` block. Update the header comment (lines 21-24) to reflect that signup now offers Google. Insert:
```erb
  <div class="flex items-center gap-3 my-6">
    <div class="flex-1 h-px bg-hairline"></div>
    <span class="text-xs font-semibold text-faint">or</span>
    <div class="flex-1 h-px bg-hairline"></div>
  </div>

  <%= button_to user_google_oauth2_omniauth_authorize_path,
        method: :post,
        form: { data: { turbo: false } },
        class: "w-full h-[52px] rounded-xl border border-field bg-card text-ink font-bold text-[14.5px] flex items-center justify-center gap-2.5" do %>
    <svg width="19" height="19" viewBox="0 0 48 48" aria-hidden="true"><path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/><path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/><path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/><path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/></svg>
    Continue with Google
  <% end %>
```

- [ ] **Step 5: Run — expect pass.** Run: `rm -rf public/assets && RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/system/google_sign_in_spec.rb`
Expected: PASS. (In test mode OmniAuth short-circuits the callback; the button POST reaches `/auth/google_oauth2` and Devise's test-mode integration invokes the callback.)

- [ ] **Step 6: Commit.**
```bash
git add app/views/devise/sessions/new.html.erb app/views/devise/registrations/new.html.erb spec/system/google_sign_in_spec.rb
git commit -m "Slice: wire Continue-with-Google buttons on login + signup"
```

---

## Task C1: Full gate run + finalize

**Files:** none (verification only), then merge.

- [ ] **Step 1: StandardRB.** Run: `bundle exec standardrb` — fix any offenses (`--fix`), re-run until clean.

- [ ] **Step 2: Brakeman.** Run: `bundle exec brakeman -q` — expect no new warnings. (OmniAuth CSRF is handled by `omniauth-rails_csrf_protection`; note if brakeman flags anything.)

- [ ] **Step 3: Bundler-audit.** Run: `bundle exec bundler-audit check --update` — expect no vulnerabilities in the added gems.

- [ ] **Step 4: Full suite.** Run:
```bash
rm -rf public/assets
RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec 2>&1 | tail -30
```
Expected: 0 failures. Investigate any regression (esp. avatar rendering across feed/navbar/profile surfaces and CSP-related system specs).

- [ ] **Step 5: N+1 sanity.** Run: `grep -c 'N+1 queries detected' log/prosopite.log`. Prosopite is log-only (never a failing gate). Baseline is ~146. After Task A4's `avatar_attachment` eager-loading at the avatar-rendering call sites, the count should stay near baseline; a small increase is acceptable given `avatar.attached?` now runs on avatar renders. If it rose materially, confirm the eager-load was applied at the list call sites (it is not a merge blocker either way).

- [ ] **Step 6: Hand off to finishing-a-development-branch** to merge into `master` and push (see subagent-driven-development / finishing skill).

---

## Self-review notes (author)

- **Spec coverage:** Track A (gem, storage, AS install, attachment+validation, helper+partial, upload UI, widget removal, CSP) → Tasks A1–A5. Track B (gems, migration, model, routes/config/controller, UI) → Tasks B1–B5. Mechanics/gates/merge → C1. All spec sections mapped.
- **Type consistency:** `ds_avatar_url` used identically in helper + partial; `from_omniauth`/`generate_username`/`RESERVED_USERNAMES`/`ALLOWED_AVATAR_TYPES`/`MAX_AVATAR_BYTES` names consistent across tasks.
- **Known adjustables flagged inline:** post-sign-in redirect path (root vs dashboard) and any existing system-spec assertion on the old "Update photo" button — both called out where they occur.
