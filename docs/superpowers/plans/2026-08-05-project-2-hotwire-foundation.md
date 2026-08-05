# Project 2 — Slice 1: Hotwire Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended)
> or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax
> for tracking.

**Goal:** Replace the React 16 SPA with server-rendered Hotwire (Turbo + Stimulus) on importmap + Propshaft
+ Tailwind, move auth to Devise, and close the votes/hujah-destroy IDORs — delivering a working feed +
single-hujah + voting loop.

**Architecture:** Retire Webpacker/shakapacker/React/Node; Propshaft serves assets, importmap serves JS,
Tailwind compiles CSS. Devise replaces hand-rolled sessions (bcrypt column rename, no forced reset). The
JSON `Api::V1::*` API stays for native clients and gets the same auth fixes. Voting posts a `button_to`
form to a thin controller that calls `Hujah#cast_vote` and replaces a `_vote_bars` Turbo-Stream partial.

**Tech Stack:** Rails 8.1.3.1, Ruby 3.4.9 (via mise), Postgres 18, RSpec, Devise ~>5.0, importmap-rails,
propshaft, tailwindcss-rails, turbo-rails, stimulus-rails, pagy, friendly_id, lucide-rails, rails_autolink,
local_time, rack-attack, invisible_captcha, capybara+cuprite, standard.

**Source spec:** `docs/superpowers/specs/2026-08-05-project-2-hotwire-foundation-design.md` (read it first).

---

## Canonical commands (this machine — from HANDOVER.md)

Use these verbatim; do not substitute bare `bundle`/`rails`/`rspec`.

- **Bundle:** `source .mise-build-env.sh && mise exec ruby@3.4.9 -- bundle install`
- **Rails/rake:** `mise exec ruby@3.4.9 -- bin/rails <args>`
- **Run specs:** `RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec <path>`
- **Prepare test DB (schema only, no seeds):** `mise exec ruby@3.4.9 -- bin/rails db:test:prepare`
- **Boot check (dev):** `mise exec ruby@3.4.9 -- bin/rails runner 'puts "boot ok"'`
- **Security gates:** `mise exec ruby@3.4.9 -- bundle exec brakeman -q` /
  `mise exec ruby@3.4.9 -- bundle exec bundler-audit check --update`

Work happens on branch `project-2-hotwire-foundation`. Commit after every task.

## Baseline invariant

The 24 existing request specs (`spec/requests/**`) are the safety net. After **every** task, the full
suite must be green **except** the three characterization specs this plan deliberately rewrites
(`api/v1/votes_spec.rb`, the destroy block of `api/v1/hujahs_spec.rb`, `sessions_spec.rb`) — those are
updated in their own tasks and must be green again by end of Phase 2.

---

## File structure (decisions locked here)

**Deleted:** `app/javascript/**` (React), `app/javascript/packs/**`, `config/webpacker.yml`,
`package.json`, `babel.config.js`/`.babelrc` (if present), `app/controllers/sessions_controller.rb`,
`app/controllers/votes_controller.rb` (legacy top-level).

**Created:**
- `config/importmap.rb`, `app/javascript/application.js`, `app/javascript/controllers/**`
- `app/assets/stylesheets/application.tailwind.css`
- `app/controllers/hujahs_controller.rb` (HTML index/show), `app/controllers/votes_controller.rb`
  (HTML create — replaces the deleted legacy one), `app/controllers/api/v1/base_controller.rb`
- `app/views/hujahs/{index,show}.html.erb`, `app/views/hujahs/_hujah_card.html.erb`,
  `app/views/hujahs/_vote_bars.html.erb`, `app/views/hujahs/_response_filter.html.erb`,
  `app/views/hujahs/_hujah_header.html.erb`, `app/views/votes/create.turbo_stream.erb`,
  `app/views/hujahs/index.turbo_stream.erb` (load-more), `app/views/shared/_navbar.html.erb`,
  `app/views/shared/_pinned.html.erb`
- `app/helpers/hujahs_helper.rb` (`format_body`)
- `app/policies/*` — **none** (Slice 1 uses `before_action`, not Pundit)
- Devise views under `app/views/devise/**`, `app/views/users/**` for signup extras
- Stimulus: `app/javascript/controllers/response_filter_controller.js` (+ `vote_controller.js` only if
  a latency check requires it)
- Initializers: `config/initializers/rack_attack.rb`, `config/initializers/content_security_policy.rb`,
  `config/initializers/pagy.rb`
- Migrations under `db/migrate/**`

**Modified:** `Gemfile`, `.bundler-audit.yml`, `config/routes.rb`, `app/controllers/application_controller.rb`,
`app/controllers/api/v1/{votes,hujahs,users}_controller.rb`, `app/models/{user,hujah}.rb`,
`app/views/layouts/application.html.erb`, `spec/support/auth_helpers.rb`, `spec/rails_helper.rb`, `README.md`.

---

# Phase 0 — Asset pipeline swap (app boots on Hotwire)

### Task 0.1: Add Hotwire/Propshaft gems, remove shakapacker

**Files:** Modify: `Gemfile`

- [ ] **Step 1: Edit the Gemfile** — remove `gem 'shakapacker', '~> 6.6'` and its comment block, and
  `gem 'sass-rails', '>= 6'`. Add:

```ruby
# Asset pipeline + Hotwire (Project 2)
gem 'propshaft'
gem 'importmap-rails'
gem 'turbo-rails'
gem 'stimulus-rails'
gem 'tailwindcss-rails'
```

- [ ] **Step 2: Install**

Run: `source .mise-build-env.sh && mise exec ruby@3.4.9 -- bundle install`
Expected: resolves without shakapacker/sass-rails; propshaft + hotwire gems installed.

- [ ] **Step 3: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "Phase 0: swap shakapacker/sass-rails for propshaft+importmap+hotwire+tailwind gems"
```

### Task 0.2: Install Propshaft/importmap/turbo/stimulus/tailwind + delete React tree

**Files:** Create: `config/importmap.rb`, `app/javascript/application.js`,
`app/javascript/controllers/{index,application}.js`, `app/assets/stylesheets/application.tailwind.css`.
Delete: `app/javascript/packs/**`, `app/javascript/components/**`, `app/javascript/routes/**`,
`app/javascript/channels/**` (Action Cable JS re-added later if needed), `app/javascript/stylesheets/**`,
`config/webpacker.yml`, `package.json`, `yarn.lock`/`package-lock.json`, `babel.config.js`/`.babelrc`.
Modify: `app/views/layouts/application.html.erb`.

- [ ] **Step 1: Run the installers**

```bash
mise exec ruby@3.4.9 -- bin/rails importmap:install
mise exec ruby@3.4.9 -- bin/rails turbo:install
mise exec ruby@3.4.9 -- bin/rails stimulus:install
mise exec ruby@3.4.9 -- bin/rails tailwindcss:install
```
Expected: creates `config/importmap.rb`, `app/javascript/application.js`,
`app/javascript/controllers/**`, `app/assets/stylesheets/application.tailwind.css`, a `Procfile.dev`.
(If `turbo:install` tries to add `redis`/npm, decline — we use Solid Cable already.)

- [ ] **Step 2: Delete the React/Webpacker tree**

```bash
git rm -r app/javascript/packs app/javascript/components app/javascript/routes \
  app/javascript/stylesheets config/webpacker.yml package.json
git rm -f yarn.lock package-lock.json babel.config.js .babelrc 2>/dev/null || true
git rm -r app/javascript/channels 2>/dev/null || true
```
(Keep `app/javascript/application.js` + `app/javascript/controllers/**` created by the installers.)

- [ ] **Step 3: Rewrite the layout** — replace `app/views/layouts/application.html.erb` with:

```erb
<!DOCTYPE html>
<html>
  <head>
    <title>Hoojah</title>
    <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>
    <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
    <%= javascript_importmap_tags %>
  </head>
  <body class="body">
    <%= yield %>
    <script src="//widget.cloudinary.com/global/all.js" type="text/javascript"></script>
    <%# Drift re-added with a CSP nonce in Task 2.5 %>
  </body>
</html>
```

- [ ] **Step 4: Boot check**

Run: `mise exec ruby@3.4.9 -- bin/rails runner 'puts "boot ok"'`
Expected: prints `boot ok` with no Webpacker/Propshaft manifest errors.

- [ ] **Step 5: Run the full suite (baseline still green)**

Run: `mise exec ruby@3.4.9 -- bin/rails db:test:prepare && RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec`
Expected: same 24/0/2 as before (API specs don't touch the view layer).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Phase 0: install propshaft/importmap/turbo/stimulus/tailwind; delete React SPA + Webpacker"
```

### Task 0.3: Placeholder root renders through Hotwire

**Files:** Modify: `app/controllers/hujah_controller.rb`, `app/views/hujah/index.html.erb`, `config/routes.rb`.
Test: `spec/requests/root_spec.rb` (create).

- [ ] **Step 1: Write the failing test** — `spec/requests/root_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'Root', type: :request do
  it 'renders the HTML shell (not a JS pack)' do
    get '/'
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('text/html')
    expect(response.body).to include('id="hujah-feed"')
  end
end
```

- [ ] **Step 2: Run it — expect FAIL**

Run: `RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec spec/requests/root_spec.rb -f doc`
Expected: FAIL (body lacks `hujah-feed`, currently empty `index.html.erb`).

- [ ] **Step 3: Remove the SPA catch-all route** — in `config/routes.rb` delete the line
  `get '/*path' => 'hujah#index'` (React router no longer owns all paths). Keep `root 'hujah#index'` for
  now (replaced in Phase 4).

- [ ] **Step 4: Minimal placeholder view** — `app/views/hujah/index.html.erb`:

```erb
<main class="max-w-xl mx-auto px-4 py-6">
  <div id="hujah-feed"></div>
</main>
```

- [ ] **Step 5: Run test — expect PASS**

Run: `RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec spec/requests/root_spec.rb -f doc`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Phase 0: root renders Hotwire HTML shell; drop SPA catch-all route"
```

---

# Phase 1 — Devise authentication

### Task 1.1: Add Devise + strong_migrations, install, pin config

**Files:** Modify: `Gemfile`. Create: `config/initializers/devise.rb` (generated, then edited),
`config/initializers/strong_migrations.rb` (generated).

- [ ] **Step 1: Add gems** — in `Gemfile` default group add `gem 'devise', '~> 5.0'`; in
  `group :development, :test` add `gem 'strong_migrations', '~> 2.5'`; in `group :development` add
  `gem 'letter_opener'`.

- [ ] **Step 2: Install**

Run: `source .mise-build-env.sh && mise exec ruby@3.4.9 -- bundle install`
Expected: devise ~>5.0 resolves. (If 5.0 is unavailable, STOP and report — do not silently pin 4.x.)

- [ ] **Step 3: Run generators**

```bash
mise exec ruby@3.4.9 -- bin/rails generate devise:install
mise exec ruby@3.4.9 -- bin/rails generate strong_migrations:install
```

- [ ] **Step 4: Pin Devise config** — in `config/initializers/devise.rb` set explicitly (search for each
  key; the file ships them commented):

```ruby
config.stretches = 12                 # match has_secure_password bcrypt cost so $2a$12$ hashes round-trip
config.pepper = nil                   # MUST stay unset — a pepper would invalidate existing hashes
config.paranoid = true                # do not reveal whether an email is registered (enumeration)
config.password_length = 8..128       # closes finding M6 (no minimum length before)
config.reset_password_within = 6.hours
```

- [ ] **Step 5: Dev mailer host + letter_opener** — in `config/environments/development.rb`:

```ruby
config.action_mailer.default_url_options = { host: "localhost", port: 3000 }
config.action_mailer.delivery_method = :letter_opener
config.action_mailer.perform_deliveries = true
```
And in `config/environments/test.rb` add:
`config.action_mailer.default_url_options = { host: "localhost", port: 3000 }`

- [ ] **Step 6: Boot check + commit**

Run: `mise exec ruby@3.4.9 -- bin/rails runner 'puts Devise::VERSION'`
Expected: prints a 5.x version.

```bash
git add -A
git commit -m "Phase 1: add devise ~>5.0 + strong_migrations; pin devise config (stretches/paranoid/length)"
```

### Task 1.2: User migration — rename digest, add Devise columns, unique email index

**Files:** Create: two migrations under `db/migrate/`. Test: `spec/models/user_auth_migration_spec.rb`
(create, then delete after — a guard, kept as a model spec).

- [ ] **Step 1: Pre-migration audit (blocking, manual)**

Run: `mise exec ruby@3.4.9 -- bin/rails runner 'puts User.group("lower(email)").having("count(*) > 1").count.inspect'`
Expected: `{}` (empty). If not empty, STOP and report the duplicate emails — they must be resolved before
the unique index.

- [ ] **Step 2: Generate the column migration**

Run: `mise exec ruby@3.4.9 -- bin/rails generate migration DeviseUserColumns`
Edit it to:

```ruby
class DeviseUserColumns < ActiveRecord::Migration[8.1]
  def change
    rename_column :users, :password_digest, :encrypted_password
    change_column_default :users, :encrypted_password, from: nil, to: ""
    change_column_null    :users, :encrypted_password, false, ""

    add_column :users, :reset_password_token, :string
    add_column :users, :reset_password_sent_at, :datetime
    add_column :users, :remember_created_at, :datetime
    add_index  :users, :reset_password_token, unique: true

    # normalize existing emails to lowercase so the unique index + Devise agree
    up_only { execute "UPDATE users SET email = lower(email)" }
    change_column_default :users, :email, from: nil, to: ""
  end
end
```

- [ ] **Step 3: Generate the concurrent unique-index migration (separate — needs no DDL transaction)**

Run: `mise exec ruby@3.4.9 -- bin/rails generate migration AddUniqueIndexToUsersEmail`
Edit it to:

```ruby
class AddUniqueIndexToUsersEmail < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!
  def change
    add_index :users, :email, unique: true, algorithm: :concurrently
  end
end
```

- [ ] **Step 4: Migrate dev + prepare test DB**

```bash
mise exec ruby@3.4.9 -- bin/rails db:migrate
mise exec ruby@3.4.9 -- bin/rails db:test:prepare
```
Expected: strong_migrations does NOT flag these (rename is metadata-only; index is concurrent).

- [ ] **Step 5: Index-validity guard test** — `spec/models/user_auth_migration_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'users schema (post-Devise migration)', type: :model do
  it 'has encrypted_password and a valid unique email index' do
    cols = User.column_names
    expect(cols).to include('encrypted_password', 'reset_password_token', 'remember_created_at')
    expect(cols).not_to include('password_digest')

    idx = ActiveRecord::Base.connection.execute(<<~SQL).to_a
      SELECT indisvalid FROM pg_index i
      JOIN pg_class c ON c.oid = i.indexrelid
      WHERE c.relname = 'index_users_on_email'
    SQL
    expect(idx.first['indisvalid']).to be(true)
  end
end
```

- [ ] **Step 6: Run it — expect PASS**

Run: `RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec spec/models/user_auth_migration_spec.rb -f doc`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Phase 1: Devise user migration (rename digest, add columns, concurrent unique email index)"
```

### Task 1.3: User model — Devise modules, drop has_secure_password

**Files:** Modify: `app/models/user.rb`. Test: `spec/models/user_spec.rb` (create).

- [ ] **Step 1: Write the failing test** — `spec/models/user_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe User, type: :model do
  it 'authenticates a pre-existing bcrypt password via Devise (no re-hash)' do
    user = User.create!(full_name: 'A', username: 'a_user', email: 'A@X.com', password: 'hoojah8')
    expect(user.email).to eq('a@x.com')                       # downcased
    expect(user.valid_password?('hoojah8')).to be(true)       # Devise validates
    expect(user).to respond_to(:reset_password_token)
  end

  it 'still requires a unique username' do
    User.create!(full_name: 'A', username: 'dup', email: 'a@x.com', password: 'hoojah8')
    dup = User.new(full_name: 'B', username: 'dup', email: 'b@x.com', password: 'hoojah8')
    expect(dup).not_to be_valid
  end

  it 'assigns a random photo after create' do
    user = User.create!(full_name: 'A', username: 'ph', email: 'ph@x.com', password: 'hoojah8')
    expect(user.photo).to be_present
  end
end
```

- [ ] **Step 2: Run it — expect FAIL**

Run: `RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec spec/models/user_spec.rb -f doc`
Expected: FAIL (`has_secure_password` still present; no `valid_password?`).

- [ ] **Step 3: Rewrite the model** — `app/models/user.rb`, replace the `has_secure_password` +
  email/password validations with Devise:

```ruby
class User < ApplicationRecord
  has_many :hujahs, dependent: :destroy
  has_many :votes, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :flags, dependent: :destroy

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  before_validation { self.email = email.to_s.downcase.strip }

  validates :full_name, presence: true
  validates :username, presence: true, uniqueness: true, length: { minimum: 1 }

  after_create :assign_random_photo

  def self.random_photo
    [
      "https://res.cloudinary.com/hoojah/image/upload/v1586909321/user_photo_2.gif",
      "https://res.cloudinary.com/hoojah/image/upload/v1586909320/user_photo_4.gif",
      "https://res.cloudinary.com/hoojah/image/upload/v1586909321/user_photo_6.gif",
      "https://res.cloudinary.com/hoojah/image/upload/v1586909320/user_photo_7.gif"
    ].sample
  end

  def unread_notifications_count
    notifications.where(read: false).count
  end

  private

  def assign_random_photo
    update_column(:photo, User.random_photo) if photo.blank?
  end
end
```

- [ ] **Step 4: Update the factory** — in `spec/factories` (find the users factory) ensure it sets
  `password { 'hoojah8' }` (≥8 chars now) and drops any `password_digest`. If factory users used
  `password 'hoojah'`, change every reference; the `login_as` helper default is updated in Task 1.7.

- [ ] **Step 5: Run test — expect PASS**

Run: `RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec spec/models/user_spec.rb -f doc`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Phase 1: User model on Devise (drop has_secure_password, downcase email, after_create photo)"
```

### Task 1.4: Routes + signup extras; delete hand-rolled auth controllers

**Files:** Modify: `config/routes.rb`, `app/controllers/application_controller.rb`. Delete:
`app/controllers/sessions_controller.rb`, `app/controllers/votes_controller.rb`. Create:
`app/controllers/users/registrations_controller.rb`.

- [ ] **Step 1: Rewrite the auth routes** — in `config/routes.rb` remove `post '/login'`,
  `delete '/logout'`, `get '/logged_in'`, `resources :users, only: :create`, and `resources :votes`.
  Add at the top:

```ruby
devise_for :users,
  controllers: { registrations: 'users/registrations' },
  path: '',
  path_names: { sign_in: 'login', sign_out: 'logout', sign_up: 'signup' }
```

- [ ] **Step 2: Registrations controller with extra params** —
  `app/controllers/users/registrations_controller.rb`:

```ruby
class Users::RegistrationsController < Devise::RegistrationsController
  before_action :configure_permitted_parameters

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:username, :full_name])
    devise_parameter_sanitizer.permit(:account_update, keys: [:username, :full_name])
  end
end
```

- [ ] **Step 3: Delete the hand-rolled controllers**

```bash
git rm app/controllers/sessions_controller.rb app/controllers/votes_controller.rb
```

- [ ] **Step 4: Strip hand-rolled auth from ApplicationController** — replace
  `app/controllers/application_controller.rb` with:

```ruby
class ApplicationController < ActionController::Base
  # CSRF is ON (Devise + Turbo). Api::V1::BaseController overrides the strategy for JSON clients.
end
```

- [ ] **Step 5: Verify routes**

Run: `mise exec ruby@3.4.9 -- bin/rails runner 'puts Rails.application.routes.url_helpers.new_user_session_path'`
Expected: prints `/login`.

- [ ] **Step 6: Run full suite** — expect the API specs green; `sessions_spec.rb` now FAILS (endpoints
  gone) — that's expected, rewritten in Task 1.7.

Run: `RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec`
Expected: only `sessions_spec.rb` (and any spec posting `/login`) failing.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Phase 1: devise_for routes (/login /logout /signup); delete SessionsController + legacy VotesController"
```

### Task 1.5: Devise Tailwind views (login/signup/reset)

**Files:** Create: `app/views/devise/**` (generated, then Tailwind-styled + signup extras).

- [ ] **Step 1: Generate Devise views**

Run: `mise exec ruby@3.4.9 -- bin/rails generate devise:views`

- [ ] **Step 2: Add the extra fields to signup** — in `app/views/devise/registrations/new.html.erb` add
  `full_name` and `username` fields above email:

```erb
<div class="mb-3">
  <%= f.label :full_name, class: "block text-sm" %>
  <%= f.text_field :full_name, autofocus: true, class: "w-full border rounded px-3 py-2" %>
</div>
<div class="mb-3">
  <%= f.label :username, class: "block text-sm" %>
  <%= f.text_field :username, class: "w-full border rounded px-3 py-2" %>
</div>
```

- [ ] **Step 3: Apply faithful Tailwind classes** to `sessions/new`, `registrations/new`,
  `passwords/new`, `passwords/edit` — a centered card (`max-w-md mx-auto mt-16 p-6`), primary button
  (`bg-primary text-white rounded px-4 py-2`). Match the current Start/Login look. (Tailwind theme tokens
  land in Task 4.0; use placeholder utility classes now, refine in Phase 4.)

- [ ] **Step 4: Manual smoke** — start the app, visit `/login`, `/signup`, `/users/password/new`; confirm
  they render (no missing-partial errors).

Run: `mise exec ruby@3.4.9 -- bin/rails runner 'app.get "/login"; puts app.response.status'`
Expected: `200`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Phase 1: Devise Tailwind views + signup full_name/username fields"
```

### Task 1.6: Api::V1::BaseController (null_session CSRF) + Warden test helpers

**Files:** Create: `app/controllers/api/v1/base_controller.rb`, `spec/support/devise.rb`. Modify: every
`app/controllers/api/v1/*_controller.rb` to inherit from it; `spec/rails_helper.rb`.

- [ ] **Step 1: Base controller** — `app/controllers/api/v1/base_controller.rb`:

```ruby
module Api
  module V1
    class BaseController < ApplicationController
      protect_from_forgery with: :null_session
      respond_to :json
    end
  end
end
```

- [ ] **Step 2: Reparent the API controllers** — change each
  `class Api::V1::XController < ApplicationController` to `< Api::V1::BaseController` in
  `votes`, `hujahs`, `users`, `notifications`, `flags` controllers. Replace any leftover calls to the
  deleted `logged_in?`/`current_user` helpers with Devise's `user_signed_in?`/`current_user`.

- [ ] **Step 3: Devise test helpers** — `spec/support/devise.rb`:

```ruby
RSpec.configure do |config|
  config.include Warden::Test::Helpers
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include Devise::Test::IntegrationHelpers, type: :system
  config.after(:each) { Warden.test_reset! }
end
```
Ensure `spec/rails_helper.rb` has `Dir[Rails.root.join('spec/support/**/*.rb')].sort.each { |f| require f }`
uncommented.

- [ ] **Step 4: Boot + partial suite**

Run: `RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec spec/requests/api/v1/hujahs_spec.rb -f doc`
Expected: the index/show examples pass (destroy still asserts old behavior — fixed in Phase 2).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Phase 1: Api::V1::BaseController (null_session CSRF); Warden/Devise test helpers"
```

### Task 1.7: Rewrite sessions characterization spec → Devise

**Files:** Modify: `spec/support/auth_helpers.rb`, `spec/requests/sessions_spec.rb` (rewrite).

- [ ] **Step 1: Replace `login_as` helper** — `spec/support/auth_helpers.rb`:

```ruby
module AuthHelpers
  # Devise/Warden login for request specs. Factory users have password 'hoojah8'.
  def login_as(user, password: 'hoojah8')
    login_params = { user: { email: user.email, password: password } }
    post user_session_path, params: login_params
    expect(response).to have_http_status(:see_other).or have_http_status(:found)
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
end
```

- [ ] **Step 2: Rewrite `spec/requests/sessions_spec.rb`** to assert Devise HTML behavior + the leak is
  gone:

```ruby
require 'rails_helper'

RSpec.describe 'Sessions (Devise)', type: :request do
  let(:user) { create(:user, password: 'hoojah8') }

  it 'logs in with valid credentials and redirects' do
    post user_session_path, params: { user: { email: user.email, password: 'hoojah8' } }
    expect(response).to have_http_status(:see_other).or have_http_status(:found)
  end

  it 'never exposes encrypted_password in any auth response' do
    post user_session_path, params: { user: { email: user.email, password: 'hoojah8' } }
    follow_redirect!
    expect(response.body).not_to include('encrypted_password')
    expect(response.body).not_to include('$2a$')
  end

  it 'rejects bad credentials without revealing account existence' do
    post user_session_path, params: { user: { email: user.email, password: 'wrong' } }
    expect(response.body).not_to include('encrypted_password')
  end
end
```

- [ ] **Step 3: Run — expect PASS**

Run: `RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec spec/requests/sessions_spec.rb -f doc`
Expected: PASS.

- [ ] **Step 4: Full suite** — everything green except the still-to-fix `votes_spec.rb` +
  `hujahs_spec.rb` destroy block (Phase 2).

Run: `RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec`

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Phase 1: rewrite sessions spec for Devise; login_as helper uses Warden; assert no digest leak"
```

---

# Phase 2 — Endpoint hardening (IDOR + CSRF + throttling)

### Task 2.1: Votes IDOR — authenticate + derive voter from session

**Files:** Modify: `app/controllers/api/v1/votes_controller.rb`. Rewrite:
`spec/requests/api/v1/votes_spec.rb`.

- [ ] **Step 1: Rewrite the characterization spec to assert SECURE behavior** —
  `spec/requests/api/v1/votes_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'Api::V1::Votes', type: :request do
  let(:owner) { create(:user) }
  let(:voter) { create(:user) }
  let(:attacker) { create(:user) }
  let(:hujah) { create(:hujah, user: owner) }

  it 'requires authentication' do
    post '/api/v1/votes/create', params: { vote: 1, hujah_id: hujah.id }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'records the vote under the SESSION user, ignoring a supplied user_id' do
    sign_in voter
    post '/api/v1/votes/create',
         params: { vote: 1, hujah_id: hujah.id, user_id: attacker.id }, as: :json
    expect(response).to have_http_status(:ok).or have_http_status(:created)
    expect(Vote.where(user: voter, hujah: hujah)).to exist
    expect(Vote.where(user: attacker)).to be_empty
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec spec/requests/api/v1/votes_spec.rb -f doc`
Expected: FAIL (no auth; uses `params[:user_id]`).

- [ ] **Step 3: Harden the controller** — `app/controllers/api/v1/votes_controller.rb`: add
  `before_action :authenticate_user!`, remove `:user_id` from `vote_params`, and make `user`/`vote`
  derive from `current_user`. Concretely replace the private helpers:

```ruby
before_action :authenticate_user!

# ...

private

def vote_params
  params.permit(:vote, :hujah_id)
end

def vote
  @vote ||= Vote.find_by(user_id: current_user.id, hujah_id: params[:hujah_id])
end

def user
  current_user
end

def hujah
  @hujah ||= Hujah.find(params[:hujah_id])
end
```
(The `create`/`update_vote`/`update_hujah_counters` bodies stay — they already use the `user`/`hujah`
helpers. In Task 3.1 this logic moves into `Hujah#cast_vote`; for now just fix the actor.)

- [ ] **Step 4: Run — expect PASS**

Run: `RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec spec/requests/api/v1/votes_spec.rb -f doc`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Phase 2: fix votes IDOR — authenticate + derive voter from current_user (was params[:user_id])"
```

### Task 2.2: Hujah-destroy IDOR — authenticate + owner-only

**Files:** Modify: `app/controllers/api/v1/hujahs_controller.rb`. Rewrite: the destroy block of
`spec/requests/api/v1/hujahs_spec.rb`.

- [ ] **Step 1: Rewrite the destroy examples to assert SECURE behavior** — in
  `spec/requests/api/v1/hujahs_spec.rb`, replace the destroy `describe`/`context` block with:

```ruby
  describe 'DELETE /api/v1/hoojah/destroy/:slug' do
    let(:owner) { create(:user) }
    let(:hujah) { create(:hujah, user: owner) }

    it 'rejects an unauthenticated delete' do
      delete "/api/v1/hoojah/destroy/#{hujah.slug}", as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(Hujah.exists?(hujah.id)).to be(true)
    end

    it 'rejects a non-owner delete' do
      sign_in create(:user)
      delete "/api/v1/hoojah/destroy/#{hujah.slug}", as: :json
      expect(response).to have_http_status(:forbidden)
      expect(Hujah.exists?(hujah.id)).to be(true)
    end

    it 'allows the owner to delete' do
      sign_in owner
      delete "/api/v1/hoojah/destroy/#{hujah.slug}", as: :json
      expect(response).to have_http_status(:ok)
      expect(Hujah.exists?(hujah.id)).to be(false)
    end
  end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec spec/requests/api/v1/hujahs_spec.rb -f doc`
Expected: FAIL on the destroy examples.

- [ ] **Step 3: Harden the controller** — `app/controllers/api/v1/hujahs_controller.rb`:

```ruby
before_action :authenticate_user!, only: :destroy
before_action :require_owner!, only: :destroy

# ...

def destroy
  hujah.destroy
  render json: { message: 'Hoojah deleted!' }
end

private

def require_owner!
  head :forbidden unless hujah&.user_id == current_user.id
end
```
(Keep the existing `hujah` finder. `index`/`show`/`create` are unchanged; `create` already uses
`current_user`.)

- [ ] **Step 4: Run — expect PASS**

Run: `RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec spec/requests/api/v1/hujahs_spec.rb -f doc`
Expected: PASS.

- [ ] **Step 5: Full suite green again**

Run: `RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec`
Expected: 0 failures (all characterization specs now assert secure behavior).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Phase 2: fix hujah-destroy IDOR — authenticate + owner-only"
```

### Task 2.3: Users `:id` mass-assignment fix

**Files:** Modify: `app/controllers/api/v1/users_controller.rb`. Test: add to
`spec/requests/api/v1/users_spec.rb`.

- [ ] **Step 1: Failing regression test** — append to `spec/requests/api/v1/users_spec.rb`:

```ruby
  it 'ignores an injected :id on update (no mass-assignment)' do
    user = create(:user)
    sign_in user
    other_id = create(:user).id
    post "/api/v1/#{user.username}/update",
         params: { user: { id: other_id, full_name: 'New Name' } }, as: :json
    expect(user.reload.id).not_to eq(other_id)
  end
```
(If the update route/action doesn't yet accept auth, wrap per the controller's current shape — the
assertion that matters is `id` is not reassignable.)

- [ ] **Step 2: Run — expect FAIL** (or error revealing `:id` is permitted).

Run: `RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec spec/requests/api/v1/users_spec.rb -f doc`

- [ ] **Step 3: Fix `user_params`** — in `app/controllers/api/v1/users_controller.rb`, ensure the update
  permit list excludes `:id` and the meaningless `:user` key:

```ruby
def user_params
  params.require(:user).permit(:full_name, :username, :email, :photo, :location, :headline, :link)
end
```

- [ ] **Step 4: Run — expect PASS**; **Step 5: Commit**

```bash
git add -A
git commit -m "Phase 2: drop :id from users update permit list (mass-assignment fix) + regression spec"
```

### Task 2.4: rack-attack throttles + invisible_captcha

**Files:** Modify: `Gemfile`. Create: `config/initializers/rack_attack.rb`. Modify signup view + the
registrations controller. Test: `spec/requests/rate_limit_spec.rb`.

- [ ] **Step 1: Add gems** — `gem 'rack-attack', '~> 6.8'`, `gem 'invisible_captcha', '~> 0.8'`; then
  `source .mise-build-env.sh && mise exec ruby@3.4.9 -- bundle install`.

- [ ] **Step 2: Initializer** — `config/initializers/rack_attack.rb`:

```ruby
class Rack::Attack
  cache.store = ActiveSupport::Cache::SolidCacheStore.new

  throttle('login/ip', limit: 10, period: 1.minute) do |req|
    req.ip if req.path == '/login' && req.post?
  end
  throttle('login/email', limit: 5, period: 1.minute) do |req|
    if req.path == '/login' && req.post?
      req.params.dig('user', 'email').to_s.downcase.presence
    end
  end
  throttle('signup/ip', limit: 5, period: 1.minute) do |req|
    req.ip if req.path == '/signup' && req.post?
  end
  throttle('password/ip', limit: 5, period: 1.minute) do |req|
    req.ip if req.path == '/password' && req.post?
  end
  throttle('votes/user', limit: 30, period: 1.minute) do |req|
    req.env['warden']&.user&.id if req.path == '/api/v1/votes/create' && req.post?
  end
end
```
Enable in `config/application.rb`: `config.middleware.use Rack::Attack`.

- [ ] **Step 3: Honeypot** — add `invisible_captcha` to `Users::RegistrationsController`:
  `invisible_captcha only: [:create], honeypot: :subtitle` and add the honeypot to the signup form:
  `<%= invisible_captcha :subtitle %>`.

- [ ] **Step 4: Throttle test** — `spec/requests/rate_limit_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'Rate limiting', type: :request do
  before { Rack::Attack.enabled = true; Rack::Attack.reset! }
  after  { Rack::Attack.enabled = false }

  it 'throttles repeated failed logins from one IP' do
    11.times { post '/login', params: { user: { email: 'x@x.com', password: 'nope' } } }
    expect(response).to have_http_status(:too_many_requests)
  end
end
```

- [ ] **Step 5: Run — expect PASS**; **Step 6: Commit**

```bash
git add -A
git commit -m "Phase 2: rack-attack throttles (login/signup/password/votes) + invisible_captcha honeypot"
```

### Task 2.5: Content Security Policy + Drift nonce

**Files:** Modify: `config/initializers/content_security_policy.rb`, `app/views/layouts/application.html.erb`.

- [ ] **Step 1: Confirm Drift hosts** — check Drift's current install snippet for its script host,
  websocket, and frame origins (typically `js.driftt.com`/`event.api.drift.com`/`*.drift.com`). Record
  the exact hosts before writing directives.

- [ ] **Step 2: CSP initializer** — `config/initializers/content_security_policy.rb`:

```ruby
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src  :self, "https://widget.cloudinary.com", "https://js.driftt.com", "https://*.drift.com"
    policy.style_src   :self, :unsafe_inline # Tailwind ships static CSS; inline only for Turbo progress bar
    policy.img_src     :self, :data, "https://res.cloudinary.com", "https://*.drift.com"
    policy.connect_src :self, "https://api.cloudinary.com", "https://*.drift.com", "wss://*.drift.com"
    policy.frame_src   "https://widget.cloudinary.com", "https://*.drift.com"
  end

  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[script-src]
end
```

- [ ] **Step 3: Re-add Drift with a nonce** — in the layout `<body>`, replace the Drift comment with the
  install snippet wrapped as `<script nonce="<%= content_security_policy_nonce %>"> … </script>` (Drift
  appId `fx42y6ieyaff` from the old React `App.jsx`).

- [ ] **Step 4: Verify CSP header present + no unsafe-inline on script-src**

Run: `mise exec ruby@3.4.9 -- bin/rails runner 'app.get "/"; puts app.response.headers["Content-Security-Policy"]'`
Expected: contains `script-src 'self' 'nonce-...'` and the Cloudinary/Drift hosts; **no** `'unsafe-inline'`
in `script-src`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Phase 2: explicit CSP (Cloudinary + Drift hosts) with nonce for Drift inline script"
```

- [ ] **Step 6: Run brakeman + bundler-audit — expect clean**

Run: `mise exec ruby@3.4.9 -- bundle exec brakeman -q && mise exec ruby@3.4.9 -- bundle exec bundler-audit check --update`
Expected: brakeman 0 warnings; bundler-audit clean (shakapacker CVE removed in Task 5.4).

---

# Phase 3 — Model: cast_vote, slugs, body helper, icons

### Task 3.1: `Hujah#cast_vote` rich-model method

**Files:** Modify: `app/models/hujah.rb`, `app/controllers/api/v1/votes_controller.rb`. Test:
`spec/models/hujah_cast_vote_spec.rb`.

- [ ] **Step 1: Failing test** — `spec/models/hujah_cast_vote_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'Hujah#cast_vote', type: :model do
  let(:owner) { create(:user) }
  let(:voter) { create(:user) }
  let(:hujah) { create(:hujah, user: owner, agree_count: 0, neutral_count: 0, disagree_count: 0) }

  it 'records a first vote, bumps the counter, notifies the owner' do
    expect { hujah.cast_vote(by: voter, choice: 1) }
      .to change { hujah.reload.agree_count }.by(1)
      .and change { Notification.where(user: owner, category: 'new_vote').count }.by(1)
    expect(Vote.find_by(user: voter, hujah: hujah).vote.last).to eq(1)
  end

  it 'switches a vote: increments new stance, decrements old, no double count' do
    hujah.cast_vote(by: voter, choice: 1)
    expect { hujah.cast_vote(by: voter, choice: 3) }
      .to change { hujah.reload.disagree_count }.by(1)
      .and change { hujah.reload.agree_count }.by(-1)
    expect(Vote.find_by(user: voter, hujah: hujah).vote).to eq([1, 3])
  end

  it 're-casting the same stance is a no-op on counters' do
    hujah.cast_vote(by: voter, choice: 2)
    expect { hujah.cast_vote(by: voter, choice: 2) }.not_to change { hujah.reload.neutral_count }
  end
end
```

- [ ] **Step 2: Run — expect FAIL** (`cast_vote` undefined).

Run: `RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec spec/models/hujah_cast_vote_spec.rb -f doc`

- [ ] **Step 3: Implement on the model** — add to `app/models/hujah.rb`:

```ruby
COUNTER_FOR = { 1 => :agree_count, 2 => :neutral_count, 3 => :disagree_count }.freeze

def cast_vote(by:, choice:)
  choice = choice.to_i
  return unless COUNTER_FOR.key?(choice)

  transaction do
    existing = votes.find_by(user_id: by.id)
    if existing
      previous = existing.vote.last
      return if previous == choice
      existing.update!(vote: existing.vote + [choice])
      decrement!(COUNTER_FOR[previous]) if COUNTER_FOR.key?(previous)
      increment!(COUNTER_FOR[choice])
    else
      votes.create!(user: by, vote: [choice])
      increment!(COUNTER_FOR[choice])
      Notification.create!(user_id: user_id, category: :new_vote, hujah_id: id, subject_user_id: by.id)
    end
  end
end
```
(`increment!`/`decrement!` are AR methods that persist a single column atomically.)

- [ ] **Step 4: Point the controller at it** — in `app/controllers/api/v1/votes_controller.rb` replace
  the `create` body with:

```ruby
def create
  hujah.cast_vote(by: current_user, choice: vote_params[:vote])
  render json: { message: 'ok' }
end
```
Remove the now-dead `user_has_voted?`, `update_vote`, `update_hujah_counters`, `user`, `vote` privates
(keep `hujah` + `vote_params`).

- [ ] **Step 5: Run cast_vote spec + votes request spec — expect PASS**

Run: `RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec spec/models/hujah_cast_vote_spec.rb spec/requests/api/v1/votes_spec.rb -f doc`

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Phase 3: Hujah#cast_vote rich-model method; thin the votes controller"
```

### Task 3.2: friendly_id slugs (with history) + backfill

**Files:** Modify: `Gemfile`, `app/models/hujah.rb`, `app/controllers/api/v1/hujahs_controller.rb`.
Create: two migrations (`friendly_id` install + backfill). Test: `spec/models/hujah_slug_spec.rb`.

- [ ] **Step 1: Add gem + install**

```bash
# Gemfile: gem 'friendly_id', '~> 5.7'  (and remove gem 'slug')
source .mise-build-env.sh && mise exec ruby@3.4.9 -- bundle install
mise exec ruby@3.4.9 -- bin/rails generate friendly_id   # creates friendly_id_slugs table migration
mise exec ruby@3.4.9 -- bin/rails db:migrate && mise exec ruby@3.4.9 -- bin/rails db:test:prepare
```

- [ ] **Step 2: Failing test** — `spec/models/hujah_slug_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'Hujah slugs (friendly_id)', type: :model do
  let(:user) { create(:user) }

  it 'generates unique, length-bounded slugs from the body' do
    a = Hujah.create!(user: user, body: 'Nasi lemak is the best breakfast in Malaysia hands down')
    b = Hujah.create!(user: user, body: 'Nasi lemak is the best breakfast in Malaysia hands down')
    expect(a.slug).not_to eq(b.slug)          # collision-safe
    expect(a.slug.length).to be <= 80
    expect(Hujah.friendly.find(a.slug)).to eq(a)
  end

  it 'keeps old slugs resolvable after a body edit (history)' do
    h = Hujah.create!(user: user, body: 'Original take on teh tarik')
    old = h.slug
    h.update!(body: 'Revised take on teh tarik entirely')
    expect(Hujah.friendly.find(old)).to eq(h)
  end
end
```

- [ ] **Step 3: Run — expect FAIL**.

- [ ] **Step 4: Configure the model** — in `app/models/hujah.rb` remove `slug :set_slug` and the
  `set_slug` method; add:

```ruby
extend FriendlyId
friendly_id :slug_source, use: [:slugged, :history]

def slug_source
  ActionController::Base.helpers.strip_tags(body.to_s).split.first(10).join(' ')
end

def should_generate_new_friendly_id?
  will_save_change_to_body? || slug.blank?
end
```

- [ ] **Step 5: Backfill migration** — generate `BackfillHujahSlugs`:

```ruby
class BackfillHujahSlugs < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!
  def up
    Hujah.reset_column_information
    Hujah.find_each { |h| h.send(:set_slug, nil); h.save!(validate: false) if h.slug.blank? }
  end
  def down; end
end
```
(If any existing slug is non-unique, friendly_id appends a UUID suffix on save.)

- [ ] **Step 6: Point controller lookups at friendly_id** — in
  `app/controllers/api/v1/hujahs_controller.rb` change the `hujah` finder:
  `@hujah ||= Hujah.friendly.find(params[:slug])`.

- [ ] **Step 7: Migrate, run slug spec + full suite — expect PASS**

```bash
mise exec ruby@3.4.9 -- bin/rails db:migrate && mise exec ruby@3.4.9 -- bin/rails db:test:prepare
RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec
```

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Phase 3: replace dead slug gem with friendly_id (slugged+history); backfill existing slugs"
```

### Task 3.3: `format_body` view helper

**Files:** Add gem `rails_autolink`; create `app/helpers/hujahs_helper.rb`. Test:
`spec/helpers/hujahs_helper_spec.rb`.

- [ ] **Step 1: Add gem** — `gem 'rails_autolink'`; `bundle install`.

- [ ] **Step 2: Failing test** — `spec/helpers/hujahs_helper_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe HujahsHelper, type: :helper do
  it 'linkifies URLs and escapes script tags' do
    out = helper.format_body("See https://hoojah.my now <script>alert(1)</script>")
    expect(out).to include('href="https://hoojah.my"')
    expect(out).to include('rel="noopener"')
    expect(out).not_to include('<script>')
  end

  it 'preserves newlines as paragraphs' do
    expect(helper.format_body("a\n\nb")).to include('</p>')
  end
end
```

- [ ] **Step 3: Run — expect FAIL**.

- [ ] **Step 4: Implement** — `app/helpers/hujahs_helper.rb`:

```ruby
module HujahsHelper
  def format_body(text)
    auto_link(simple_format(text), html: { target: "_blank", rel: "noopener" })
  end
end
```

- [ ] **Step 5: Run — expect PASS**; **Step 6: Commit**

```bash
git add -A
git commit -m "Phase 3: format_body helper (simple_format + auto_link); replaces dangerouslySetInnerHTML"
```

### Task 3.4: lucide-rails icon helper

**Files:** Add gem `lucide-rails`; create `app/helpers/icons_helper.rb` (semantic aliases). Test:
`spec/helpers/icons_helper_spec.rb`.

- [ ] **Step 1: Add gem + verify** — `gem 'lucide-rails'`; `bundle install`; confirm the helper:
  `mise exec ruby@3.4.9 -- bin/rails runner 'include LucideRails::RailsHelper rescue nil; puts "ok"'`.
  If the gem is incompatible with Propshaft/Rails 8.1, STOP and report (fallback: inline the ~15 needed
  SVGs as partials).

- [ ] **Step 2: Failing test** — `spec/helpers/icons_helper_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe IconsHelper, type: :helper do
  it 'renders the mapped Lucide svg for a stance' do
    expect(helper.stance_icon('agree')).to include('<svg')
  end
end
```

- [ ] **Step 3: Implement** — `app/helpers/icons_helper.rb`:

```ruby
module IconsHelper
  STANCE_ICON = { 'agree' => 'thumbs-up', 'neutral' => 'minus', 'disagree' => 'thumbs-down' }.freeze

  def stance_icon(stance, **opts)
    lucide_icon(STANCE_ICON.fetch(stance.to_s), **opts)
  end
end
```
(Direct `lucide_icon("bell")` etc. is used inline in views for the 1:1 icons per the spec mapping table.)

- [ ] **Step 4: Run — expect PASS**; **Step 5: Commit**

```bash
git add -A
git commit -m "Phase 3: lucide-rails + stance_icon helper (agree/neutral/disagree → thumbs-up/minus/thumbs-down)"
```

---

# Phase 4 — Screens (HTML feed + show + voting)

### Task 4.0: Tailwind theme tokens (agree/neutral/disagree palette)

**Files:** Modify: `app/assets/stylesheets/application.tailwind.css` (or `config/tailwind.config.js`).

- [ ] **Step 1: Port the color system** — from the old `app/javascript/stylesheets/variables.scss`
  extract the primary + agree/neutral/disagree hex values and add them as Tailwind theme colors
  (`primary`, `agree`, `neutral`, `disagree`) so views can use `bg-agree`, `text-disagree`, etc. Rebuild:

Run: `mise exec ruby@3.4.9 -- bin/rails tailwindcss:build`
Expected: builds `app/assets/builds/tailwind.css` with no errors.

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "Phase 4: Tailwind theme tokens for primary + agree/neutral/disagree palette"
```

### Task 4.1: HujahsController#index — feed + pagy load-more

**Files:** Create: `app/controllers/hujahs_controller.rb`, `app/views/hujahs/index.html.erb`,
`app/views/hujahs/_hujah_card.html.erb`, `app/views/hujahs/_hujah_header.html.erb`,
`app/views/hujahs/_vote_bars.html.erb`, `app/views/hujahs/index.turbo_stream.erb`,
`app/views/shared/_navbar.html.erb`, `app/views/shared/_pinned.html.erb`,
`config/initializers/pagy.rb`. Modify: `Gemfile` (pagy), `config/routes.rb`,
`app/controllers/application_controller.rb` (include Pagy::Backend). Test:
`spec/requests/hujahs_index_spec.rb`, `spec/system/feed_spec.rb`.

- [ ] **Step 1: Add pagy + wire it** — `gem 'pagy', '~> 43.6'`; `bundle install`. Create
  `config/initializers/pagy.rb` with `require 'pagy/extras/countless'` and
  `Pagy::DEFAULT[:limit] = 15`. In `ApplicationController` add `include Pagy::Backend`; in
  `ApplicationHelper` add `include Pagy::Frontend`.

- [ ] **Step 2: Failing request test** — `spec/requests/hujahs_index_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'Hujahs index', type: :request do
  it 'lists top-level hujahs and paginates via turbo_stream' do
    user = create(:user)
    create_list(:hujah, 20, user: user, parent_id: nil)
    get '/'
    expect(response).to have_http_status(:ok)
    expect(response.body.scan('data-testid="hujah-card"').size).to eq(15)

    get '/', params: { page: 2 }, headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
    expect(response.media_type).to eq('text/vnd.turbo-stream.html')
    expect(response.body).to include('turbo-stream action="append"')
  end
end
```

- [ ] **Step 3: Run — expect FAIL**.

- [ ] **Step 4: Route + controller** — in `config/routes.rb` set `root 'hujahs#index'` (replacing
  `hujah#index`) and `get '/hoojah/:slug', to: 'hujahs#show', as: :hujah`. Then delete the now-orphaned
  placeholder: `git rm app/controllers/hujah_controller.rb -r app/views/hujah`. Create
  `app/controllers/hujahs_controller.rb`:

```ruby
class HujahsController < ApplicationController
  def index
    @pagy, @hujahs = pagy_countless(
      Hujah.where(parent_id: nil).includes(:user).order(updated_at: :desc)
    )
    respond_to do |format|
      format.html
      format.turbo_stream # index.turbo_stream.erb (load-more append)
    end
  end
end
```

- [ ] **Step 5: Views** — create the partials. `index.html.erb`:

```erb
<%= render "shared/navbar" %>
<main class="max-w-xl mx-auto px-4 py-6">
  <%= render "shared/pinned" unless user_signed_in? %>
  <div id="hujah-feed">
    <%= render partial: "hujah_card", collection: @hujahs, as: :hujah %>
  </div>
  <div id="load-more"><%= render "load_more" if @pagy.next %>
  </div>
</main>
```
`_hujah_card.html.erb` (faithful port of the React card — avatar/handle header, body via `format_body`,
three stance buttons, `_vote_bars`, counts). Give the root element `data-testid="hujah-card"` and wrap
the vote widget in `<div id="<%= dom_id(hujah, :vote_bars) %>">…</div>`. `index.turbo_stream.erb`:

```erb
<%= turbo_stream.append "hujah-feed" do %>
  <%= render partial: "hujah_card", collection: @hujahs, as: :hujah %>
<% end %>
<%= turbo_stream.replace "load-more" do %>
  <div id="load-more"><%= render "load_more" if @pagy.next %></div>
<% end %>
```
Create `_load_more.html.erb`:
`<%= link_to "Load more", root_path(page: @pagy.next), data: { turbo_stream: true } %>`.

- [ ] **Step 6: Run request test — expect PASS**.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Phase 4: HujahsController#index — server-rendered feed + pagy_countless turbo-stream load-more"
```

### Task 4.2: HujahsController#show — full card, vote bars, threaded children

**Files:** Modify: `app/controllers/hujahs_controller.rb`. Create: `app/views/hujahs/show.html.erb`,
`app/views/hujahs/_response_filter.html.erb`, `app/views/hujahs/_child_card.html.erb`. Test:
`spec/requests/hujahs_show_spec.rb`.

- [ ] **Step 1: Failing test** — `spec/requests/hujahs_show_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'Hujah show', type: :request do
  it 'renders the hujah, its vote bars, and threaded children' do
    user = create(:user)
    parent = create(:hujah, user: user)
    create(:hujah, user: user, parent: parent, body: 'a child response')
    get "/hoojah/#{parent.slug}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(dom_id(parent, :vote_bars))
    expect(response.body).to include('a child response')
    expect(response.body).to include('data-controller="response-filter"')
  end
end
```

- [ ] **Step 2: Run — expect FAIL**.

- [ ] **Step 3: Controller action**:

```ruby
def show
  @hujah = Hujah.friendly.find(params[:slug])
  @children = @hujah.children.includes(:user).order(updated_at: :desc)
end
```

- [ ] **Step 4: Views** — `show.html.erb` renders `_hujah_header`, `format_body`, `_vote_bars`
  (same `dom_id` scheme), the counts row, then `_response_filter` wrapping the children
  (`_child_card` per child, each with `data-response-filter-target="item"` and
  `data-response-filter-vote="<stance>"`). Faithful to `Hujah.jsx`.

- [ ] **Step 5: Run — expect PASS**; **Step 6: Commit**

```bash
git add -A
git commit -m "Phase 4: HujahsController#show — full card, vote bars, threaded children, response filter markup"
```

### Task 4.3: HTML voting — Turbo Stream replace of `_vote_bars`

**Files:** Create: `app/controllers/votes_controller.rb` (HTML),
`app/views/votes/create.turbo_stream.erb`. Modify: `config/routes.rb`. Test:
`spec/requests/vote_stream_spec.rb`.

- [ ] **Step 1: Failing test** — `spec/requests/vote_stream_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'HTML voting', type: :request do
  let(:user) { create(:user) }
  let(:hujah) { create(:hujah, user: create(:user)) }

  it 'requires login' do
    post "/hoojah/#{hujah.slug}/votes", params: { vote: 1 }
    expect(response).to redirect_to(new_user_session_path)
  end

  it 'casts a vote and returns a turbo_stream replacing the vote bars' do
    sign_in user
    post "/hoojah/#{hujah.slug}/votes", params: { vote: 1 },
         headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
    expect(response.media_type).to eq('text/vnd.turbo-stream.html')
    expect(response.body).to include("turbo-stream action=\"replace\" target=\"#{dom_id(hujah, :vote_bars)}\"")
    expect(hujah.reload.agree_count).to eq(1)
  end
end
```

- [ ] **Step 2: Run — expect FAIL**.

- [ ] **Step 3: Route** — in `config/routes.rb`:
  `post '/hoojah/:slug/votes', to: 'votes#create', as: :hujah_votes`.

- [ ] **Step 4: Controller** — `app/controllers/votes_controller.rb`:

```ruby
class VotesController < ApplicationController
  before_action :authenticate_user!

  def create
    @hujah = Hujah.friendly.find(params[:slug])
    @hujah.cast_vote(by: current_user, choice: params[:vote])
    respond_to do |format|
      format.turbo_stream # create.turbo_stream.erb
      format.html { redirect_to hujah_path(@hujah.slug) }
    end
  end
end
```

- [ ] **Step 5: Stream view** — `app/views/votes/create.turbo_stream.erb`:

```erb
<%= turbo_stream.replace dom_id(@hujah, :vote_bars) do %>
  <%= render "hujahs/vote_bars", hujah: @hujah, current_user_vote: @hujah.current_user_vote(logged_in: true, current_user_id: current_user.id) %>
<% end %>
```
Ensure `_vote_bars.html.erb` wraps itself in `<div id="<%= dom_id(hujah, :vote_bars) %>">` and each
stance button is a `button_to hujah_votes_path(hujah.slug), params: { vote: n }` with
`data: { turbo_stream: true }`.

- [ ] **Step 6: Run — expect PASS**; **Step 7: Commit**

```bash
git add -A
git commit -m "Phase 4: HTML votes controller — cast_vote + turbo_stream replace of _vote_bars"
```

### Task 4.4: `response_filter_controller` (Stimulus) + latency check on vote feedback

**Files:** Create: `app/javascript/controllers/response_filter_controller.js`. Modify: importmap pins for
`local-time`; `_response_filter.html.erb`. Test: `spec/system/response_filter_spec.rb`.

- [ ] **Step 1: Pin local-time** — `mise exec ruby@3.4.9 -- bin/importmap pin local-time` (or manual pin
  if the gem asset isn't ESM — see spec risk). In `app/javascript/application.js` add
  `import LocalTime from "local-time"; LocalTime.start()`.

- [ ] **Step 2: Stimulus controller** — `app/javascript/controllers/response_filter_controller.js`
  (Values/Classes API per spec conventions):

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "item"]
  static classes = ["hidden"]
  static values = { active: { type: String, default: "all" } }

  filter(event) { this.activeValue = event.params.filter }

  activeValueChanged(value) {
    this.itemTargets.forEach((el) => {
      const show = value === "all" || el.dataset.responseFilterVote === value
      el.toggleAttribute("hidden", !show)
    })
    this.tabTargets.forEach((tab) => {
      tab.setAttribute("aria-pressed", String(tab.dataset.responseFilterFilterParam === value))
    })
  }
}
```

- [ ] **Step 3: Wire the markup** — `_response_filter.html.erb`: a `role="group"` with four
  `<button data-action="response-filter#filter" data-response-filter-filter-param="all|agree|neutral|disagree"
  data-response-filter-target="tab" aria-pressed="...">`; children as
  `data-response-filter-target="item" data-response-filter-vote="<stance>"`. Controller root:
  `data-controller="response-filter" data-response-filter-hidden-class="hidden"`.

- [ ] **Step 4: System test (cuprite — set up in Phase 5, so this step's spec is written now and run in
  Task 5.2)** — write `spec/system/response_filter_spec.rb` asserting: clicking "Agree" hides
  non-agree items (`hidden` attribute present) and sets `aria-pressed="true"` on the Agree tab.

- [ ] **Step 5: Vote-feedback latency decision** — run the app, click a vote; if the `button_to` +
  Turbo-Stream round-trip already feels instant (it will on same-origin), **do not** add `vote_controller`
  — rely on CSS `:active`/`button:disabled` (Turbo auto-disables the submitter). Record the decision in a
  code comment in `_vote_bars.html.erb`. Only if visibly laggy, add a presentational `vote_controller`
  per the spec's Stimulus-conventions contract.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Phase 4: response_filter Stimulus controller (a11y-correct) + local-time; vote feedback via CSS/Turbo"
```

### Task 4.5: Navbar + pinned block (faithful port)

**Files:** Create/finish: `app/views/shared/_navbar.html.erb`, `app/views/shared/_pinned.html.erb`.

- [ ] **Step 1** — port `navbar.js`/`navbar_registration.js`: logged-out shows Login/Signup links;
  logged-in shows the user avatar + logout (`button_to destroy_user_session_path, method: :delete`) and
  unread notifications count (`current_user.unread_notifications_count`). Port `pinned.js` intro block.

- [ ] **Step 2: Request assertion** — extend `spec/requests/hujahs_index_spec.rb`: logged-out response
  includes "Login"; signed-in response includes the logout control.

- [ ] **Step 3: Run those examples — expect PASS**; **Step 4: Commit**

```bash
git add -A
git commit -m "Phase 4: navbar (logged-in/out) + pinned intro block"
```

---

# Phase 5 — System tests, linter, cleanup

### Task 5.1: Capybara + cuprite driver

**Files:** Modify: `Gemfile`; create `spec/support/capybara.rb`. Modify: `spec/rails_helper.rb`.

- [ ] **Step 1: Add gems** — `group :test` add `gem 'capybara'`, `gem 'cuprite'`; `bundle install`.

- [ ] **Step 2: Driver config** — `spec/support/capybara.rb`:

```ruby
require 'capybara/cuprite'

Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(app, window_size: [1200, 900], process_timeout: 20,
    browser_options: { 'no-sandbox': nil })
end
Capybara.javascript_driver = :cuprite
Capybara.default_max_wait_time = 5

RSpec.configure do |config|
  config.before(:each, type: :system) { driven_by :rack_test }
  config.before(:each, type: :system, js: true) { driven_by :cuprite }
end
```

- [ ] **Step 3: Smoke system test** — `spec/system/smoke_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'Smoke', type: :system, js: true do
  it 'loads the feed' do
    create(:hujah, user: create(:user))
    visit '/'
    expect(page).to have_css('[data-testid="hujah-card"]')
  end
end
```

- [ ] **Step 4: Run — expect PASS** (needs Chrome/Chromium present)

Run: `RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec spec/system/smoke_spec.rb -f doc`
Expected: PASS. If Chrome missing, report — do not skip silently.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Phase 5: capybara + cuprite system-test driver + feed smoke test"
```

### Task 5.2: Flagship system specs (vote, filter a11y, local-time, double-submit)

**Files:** Create/run: `spec/system/vote_spec.rb`, `spec/system/response_filter_spec.rb`,
`spec/system/local_time_spec.rb`, and the double-submit request assertion.

- [ ] **Step 1: Vote happy-path** — `spec/system/vote_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'Voting', type: :system, js: true do
  it 'updates the vote bars in place without a full reload' do
    voter = create(:user)
    hujah = create(:hujah, user: create(:user))
    login_as_system(voter)
    visit "/hoojah/#{hujah.slug}"
    within "##{ActionView::RecordIdentifier.dom_id(hujah, :vote_bars)}" do
      click_button 'Agree'
    end
    expect(page).to have_content('100%')
    expect(hujah.reload.agree_count).to eq(1)
  end
end
```
(Add a `login_as_system` helper using Warden `login_as` for system specs in `spec/support/devise.rb`.)

- [ ] **Step 2: Filter a11y** — run `spec/system/response_filter_spec.rb` (written in Task 4.4): assert
  `hidden` attribute + `aria-pressed`.

- [ ] **Step 3: local-time after stream** — `spec/system/local_time_spec.rb`: create a hujah, load more /
  vote, assert a `<time>` element gets a localized title/text (not raw ISO).

- [ ] **Step 4: Double-submit** — add to `spec/requests/hujahs_index_spec.rb`: append page 2 twice, assert
  card ids are unique (no duplicate `dom_id`s).

- [ ] **Step 5: Run all system specs — expect PASS**

Run: `RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec spec/system -f doc`

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Phase 5: system specs — vote-in-place, filter a11y, local-time, double-submit guard"
```

### Task 5.3: StandardRB

**Files:** Modify: `Gemfile`; create `.standard.yml`.

- [ ] **Step 1: Add gem** — `group :development, :test` add `gem 'standard'`; `bundle install`.

- [ ] **Step 2: Config** — `.standard.yml`:

```yaml
ruby_version: 3.4.9
ignore:
  - 'db/schema.rb'
  - 'db/migrate/**/*'
  - 'bin/**/*'
```

- [ ] **Step 3: Autoformat + fix** — `mise exec ruby@3.4.9 -- bundle exec standardrb --fix`. Re-run the
  full suite to confirm formatting didn't break anything.

Run: `mise exec ruby@3.4.9 -- bundle exec standardrb && RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec`
Expected: standardrb clean; suite green.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Phase 5: adopt StandardRB (matches workspace convention) + autoformat"
```

### Task 5.4: Final cleanup + security gates + docs

**Files:** Modify: `.bundler-audit.yml`, `README.md`, `docs/superpowers/HANDOVER.md`.

- [ ] **Step 1: Remove the shakapacker CVE ignore** — delete the `GHSA-96qw-h329-v5rg` block from
  `.bundler-audit.yml` (shakapacker is gone).

- [ ] **Step 2: Confirm no stragglers** — grep for dead references:

Run: `grep -rniE "shakapacker|webpacker|react|javascript_pack_tag|has_secure_password|params\[:user_id\]" app config Gemfile | grep -v node_modules`
Expected: no hits (Cloudinary widget script is fine; that's not React).

- [ ] **Step 3: Security gates**

```bash
mise exec ruby@3.4.9 -- bundle exec brakeman -q
mise exec ruby@3.4.9 -- bundle exec bundler-audit check --update
```
Expected: brakeman 0 warnings; bundler-audit clean (no ignores needed).

- [ ] **Step 4: Full suite, final green**

Run: `mise exec ruby@3.4.9 -- bin/rails db:test:prepare && RAILS_ENV=test RUBYOPT='-W0' mise exec ruby@3.4.9 -- bundle exec rspec`
Expected: 0 failures.

- [ ] **Step 5: Update docs** — README stack section (Hotwire/Propshaft/Devise, `bin/dev`), and add a
  "Project 2 Slice 1 done" note to `docs/superpowers/HANDOVER.md` with Slice 2 scope (compose/profile/
  notifications/flags) + the still-open items (rack-cors M1, require_master_key L4, notifications IDOR).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Phase 5: remove shakapacker CVE ignore; security gates clean; update README + HANDOVER"
```

---

## Definition of done (Slice 1)

- App boots dev + test on importmap/Propshaft/Tailwind; no React/Webpacker/Node.
- Devise auth (`/login` `/signup` `/logout` + reset); existing users log in unchanged; no `password_digest`
  leak; CSRF on.
- Feed + single-hujah render server-side, faithful look; voting updates in place via Turbo Streams.
- Votes IDOR + hujah-destroy IDOR + `:id` mass-assignment closed, guarded by rewritten specs.
- rack-attack throttles, invisible_captcha, explicit CSP with Drift nonce.
- Full RSpec suite green (incl. new request + cuprite system specs); brakeman 0; bundler-audit clean;
  StandardRB clean.

## Deferred to Slice 2+ (own specs)

Compose/new-hujah form (+ Cloudinary upload + parent-reply), user profile, notifications index (+ its
IDOR fix), flag modal, social-share menu; Pundit; prosopite N+1; vote-model array→scalar collapse;
Cloudinary URL host validation; `require_master_key`; `rack-cors` origin tightening before Project 3.
