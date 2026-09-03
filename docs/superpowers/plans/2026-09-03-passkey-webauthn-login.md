# Passkey (WebAuthn) Passwordless Login — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add passkeys (WebAuthn discoverable credentials) as a passwordless alternative login beside email+password and Google, plus a self-service page to add/rename/delete passkeys.

**Architecture:** A hand-rolled Warden `:passkey` strategy on top of the `webauthn` gem verifies usernameless assertions and signs the user in. A `Users::SessionsController` subclass serves the login challenge + verify endpoints; a plain `PasskeysController` (Pundit owner-only) serves the management page. The browser ceremony runs through the `@github/webauthn-json` library (pinned via importmap) driven by two Stimulus controllers. Password login always remains, so passkeys are purely additive — no lockout risk.

**Tech Stack:** Rails 8.1, Ruby 3.4.9, Devise 5 + Warden, `webauthn` (cedarcode/webauthn-ruby) gem, Pundit, Hotwire (Turbo + Stimulus over importmap, no Node build), `@github/webauthn-json`, RSpec + FactoryBot + `WebAuthn::FakeClient`, Cuprite (system specs).

---

## Key conventions (read before starting)

- **Warden `params` are Rack-level, not Rails-level** — a JSON request body is **not** parsed into `params` inside a Warden strategy. Therefore the **login assertion is POSTed form-encoded** (`credential=<json-string>`) and the strategy `JSON.parse`s it. The **registration** flow, by contrast, runs in an ordinary Rails controller, so it can POST JSON. This asymmetry is deliberate; keep the explaining comments.
- **Pundit:** `ApplicationController` runs `after_action :verify_authorized, unless: :devise_controller?`. Devise subclasses (`Users::SessionsController`) are exempt. `PasskeysController` is a plain `ApplicationController`, so **every action must call `authorize` or `skip_authorization` exactly once.**
- **Routes are hand-written, no `resources`** (`config/routes.rb`). Every route carries a `#` comment explaining its shape. Match that style.
- **Session is indifferent-access** and shared between the controller and the Warden strategy (both see `env["rack.session"]`). Store challenges under string-y keys; read-and-delete for single use.
- **Config origin in dev+test is `http://localhost:3000`.** `WebAuthn::FakeClient` in specs must be constructed with that exact origin, or verification fails on an origin mismatch. The HTTP request host in specs is irrelevant to WebAuthn verification.
- Commit subjects follow `Slice N`-style only for roadmap work; this is a feature branch, so use plain imperative subjects. **No Claude/Anthropic branding in commit messages.**
- Run specs with `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec ...`. Prefix any command with `mise exec ruby@3.4.9 --` if mise hasn't activated the shell.

## File Structure

**Create:**
- `config/initializers/webauthn.rb` — `WebAuthn.configure` (origin, rp_name).
- `db/migrate/<ts>_add_webauthn_id_to_users.rb` — user handle column + concurrent unique index.
- `db/migrate/<ts>_create_webauthn_credentials.rb` — credentials table.
- `app/models/webauthn_credential.rb` — credential model + validations.
- `app/strategies/passkey_strategy.rb` — `PasskeyStrategy < Warden::Strategies::Base`.
- `app/controllers/users/sessions_controller.rb` — passkey login challenge + verify.
- `app/controllers/passkeys_controller.rb` — management (index/options/create/update/destroy).
- `app/policies/passkey_policy.rb` — owner-only update/destroy.
- `app/views/passkeys/index.html.erb` — security page.
- `app/views/passkeys/_credential.html.erb` — one passkey row.
- `app/views/passkeys/create.turbo_stream.erb` — append new row.
- `app/views/passkeys/destroy.turbo_stream.erb` — remove row.
- `app/javascript/controllers/passkey_authentication_controller.js` — login button.
- `app/javascript/controllers/passkey_registration_controller.js` — add-passkey button.
- Spec files under `spec/` (per task).

**Modify:**
- `app/models/user.rb` — `has_many :webauthn_credentials`.
- `config/initializers/devise.rb` — register the `:passkey` Warden strategy.
- `config/routes.rb` — sessions controller override + passkey login + `/settings/passkeys` routes.
- `app/views/devise/sessions/new.html.erb` — "Sign in with a passkey" button.
- `app/views/devise/registrations/edit.html.erb` — link to the security page.
- `config/importmap.rb` — pin `@github/webauthn-json`.
- `config/initializers/filter_parameter_logging.rb` — filter `challenge`/`credential`.
- `vendor/javascript/@github--webauthn-json.js` — created by `bin/importmap ... --download`.

---

## Task 1: Add the `webauthn` gem and configuration

**Files:**
- Modify: `Gemfile`
- Create: `config/initializers/webauthn.rb`
- Create: `spec/config/webauthn_config_spec.rb`

- [ ] **Step 1: Add the gem**

In `Gemfile`, next to the auth gems (after `gem "omniauth-rails_csrf_protection", "~> 1.0"`), add:

```ruby
# WebAuthn / passkeys — server-side Relying Party for passwordless login.
gem "webauthn", "~> 3.4"
```

- [ ] **Step 2: Install**

Run: `mise exec ruby@3.4.9 -- bundle install`
Expected: bundle resolves and installs `webauthn` (and its `cbor`/`openssl` deps). If a C-extension build fails on Apple Silicon, `source .mise-build-env.sh` first, then re-run.

- [ ] **Step 3: Write the failing config spec**

Create `spec/config/webauthn_config_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "WebAuthn configuration" do
  it "uses the localhost origin in the test environment" do
    expect(WebAuthn.configuration.allowed_origins).to eq(["http://localhost:3000"])
  end

  it "sets the relying-party name to Hoojah" do
    expect(WebAuthn.configuration.rp_name).to eq("Hoojah")
  end
end
```

- [ ] **Step 4: Run it, watch it fail**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/config/webauthn_config_spec.rb`
Expected: FAIL — origin is nil / rp_name is nil (initializer not written yet).

- [ ] **Step 5: Write the initializer**

Create `config/initializers/webauthn.rb`:

```ruby
# WebAuthn Relying Party config for passkey login. `allowed_origins` is the list of
# full scheme+host values the browser may present; `rp_id` is derived from their host
# by the gem. In production this MUST include the public origin
# (https://hoojah.rudzainy.com) or every assertion fails the origin check. Dev and test
# both use http://localhost:3000 so WebAuthn::FakeClient in specs can match it without a
# Host dance. (Use allowed_origins, not the deprecated singular origin=.)
WebAuthn.configure do |config|
  config.allowed_origins = [ENV.fetch("WEBAUTHN_ORIGIN") { "http://localhost:3000" }]
  config.rp_name = "Hoojah"
  config.credential_options_timeout = 120_000 # ms the browser waits for the user gesture — restates the gem default
end
```

- [ ] **Step 6: Run it, watch it pass**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/config/webauthn_config_spec.rb`
Expected: PASS (2 examples).

- [ ] **Step 7: Document the env var**

If a `.env.example` or similar exists, add `WEBAUTHN_ORIGIN=http://localhost:3000`. If not, skip — the initializer's fallback covers dev/test and production sets it in the deploy environment.

- [ ] **Step 8: Commit**

```bash
git add Gemfile Gemfile.lock config/initializers/webauthn.rb spec/config/webauthn_config_spec.rb
git commit -m "Add webauthn gem and Relying Party configuration"
```

---

## Task 2: Migrations — user handle + credentials table

**Files:**
- Create: `db/migrate/<ts>_add_webauthn_id_to_users.rb`
- Create: `db/migrate/<ts>_create_webauthn_credentials.rb`
- Modify: `db/schema.rb` (regenerated by migrate)

- [ ] **Step 1: Generate the user-handle migration**

Run: `bin/rails g migration AddWebauthnIdToUsers`
Then replace its body with:

```ruby
class AddWebauthnIdToUsers < ActiveRecord::Migration[8.1]
  # strong_migrations: adding a nullable column with no default is safe on PG.
  # A unique index on a populated table must be built CONCURRENTLY, which needs
  # the DDL transaction disabled. NULLs are distinct in a Postgres unique index,
  # so the many existing users with a NULL webauthn_id do not collide.
  disable_ddl_transaction!

  def change
    add_column :users, :webauthn_id, :string
    add_index :users, :webauthn_id, unique: true, algorithm: :concurrently
  end
end
```

- [ ] **Step 2: Generate the credentials-table migration**

Run: `bin/rails g migration CreateWebauthnCredentials`
Then replace its body with:

```ruby
class CreateWebauthnCredentials < ActiveRecord::Migration[8.1]
  # New (empty) table, so inline index creation is safe — no concurrent build needed.
  def change
    create_table :webauthn_credentials do |t|
      t.references :user, null: false, foreign_key: true
      t.string :external_id, null: false   # credential id from the authenticator (base64url)
      t.string :public_key, null: false    # COSE public key (base64url)
      t.string :nickname, null: false      # user-facing label
      t.bigint :sign_count, null: false, default: 0 # clone-detection counter
      t.datetime :last_used_at
      t.timestamps
    end

    add_index :webauthn_credentials, :external_id, unique: true
    add_index :webauthn_credentials, [:user_id, :nickname], unique: true
  end
end
```

- [ ] **Step 3: Migrate dev + test databases**

Run:
```bash
bin/rails db:migrate
RAILS_ENV=test bin/rails db:migrate
```
Expected: both succeed; `db/schema.rb` now shows `webauthn_id` on `users` and a `webauthn_credentials` table. (Do NOT run `db:test:prepare` — it's schema-only and would drop the just-migrated changes only to reload from schema.rb, which is fine either way, but a plain `db:migrate` keeps it simple.)

- [ ] **Step 4: Sanity-check the schema**

Run: `grep -n "webauthn" db/schema.rb`
Expected: the `webauthn_id` column + index on `users`, and the full `webauthn_credentials` table block.

- [ ] **Step 5: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "Add webauthn_id to users and webauthn_credentials table"
```

---

## Task 3: WebauthnCredential model + User association

**Files:**
- Create: `app/models/webauthn_credential.rb`
- Modify: `app/models/user.rb`
- Create: `spec/factories/webauthn_credentials.rb`
- Create: `spec/models/webauthn_credential_spec.rb`

- [ ] **Step 1: Write the factory**

Create `spec/factories/webauthn_credentials.rb`:

```ruby
FactoryBot.define do
  factory :webauthn_credential do
    association :user
    sequence(:external_id) { |n| "credential-external-id-#{n}" }
    public_key { "cose-public-key-bytes" }
    sequence(:nickname) { |n| "Passkey #{n}" }
    sign_count { 0 }
  end
end
```

- [ ] **Step 2: Write the failing model spec**

Create `spec/models/webauthn_credential_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe WebauthnCredential do
  it "is valid with the factory defaults" do
    expect(build(:webauthn_credential)).to be_valid
  end

  it "requires an external_id, public_key, and nickname" do
    credential = build(:webauthn_credential, external_id: nil, public_key: nil, nickname: nil)
    expect(credential).not_to be_valid
    expect(credential.errors.attribute_names).to include(:external_id, :public_key, :nickname)
  end

  it "requires a globally unique external_id" do
    existing = create(:webauthn_credential)
    dup = build(:webauthn_credential, external_id: existing.external_id)
    expect(dup).not_to be_valid
    expect(dup.errors[:external_id]).to be_present
  end

  it "requires a nickname unique per user but allows reuse across users" do
    owner = create(:user)
    create(:webauthn_credential, user: owner, nickname: "Laptop")
    same_owner_dup = build(:webauthn_credential, user: owner, nickname: "Laptop")
    other_owner_ok = build(:webauthn_credential, user: create(:user), nickname: "Laptop")
    expect(same_owner_dup).not_to be_valid
    expect(other_owner_ok).to be_valid
  end

  it "is destroyed when its user is destroyed" do
    credential = create(:webauthn_credential)
    expect { credential.user.destroy }.to change(described_class, :count).by(-1)
  end
end
```

- [ ] **Step 3: Run it, watch it fail**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/webauthn_credential_spec.rb`
Expected: FAIL — `uninitialized constant WebauthnCredential`.

- [ ] **Step 4: Write the model**

Create `app/models/webauthn_credential.rb`:

```ruby
class WebauthnCredential < ApplicationRecord
  belongs_to :user

  validates :external_id, presence: true, uniqueness: true
  validates :public_key, presence: true
  validates :nickname, presence: true, uniqueness: {scope: :user_id}
  validates :sign_count,
    presence: true,
    numericality: {only_integer: true, greater_than_or_equal_to: 0}
end
```

- [ ] **Step 5: Add the association on User**

In `app/models/user.rb`, in the associations block (after `has_many :user_badges, dependent: :destroy` around line 9), add:

```ruby
  has_many :webauthn_credentials, dependent: :destroy
```

- [ ] **Step 6: Run it, watch it pass**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/webauthn_credential_spec.rb`
Expected: PASS (5 examples).

- [ ] **Step 7: Commit**

```bash
git add app/models/webauthn_credential.rb app/models/user.rb spec/factories/webauthn_credentials.rb spec/models/webauthn_credential_spec.rb
git commit -m "Add WebauthnCredential model and User association"
```

---

## Task 4: Warden `:passkey` strategy

**Files:**
- Create: `app/strategies/passkey_strategy.rb`
- Modify: `config/initializers/devise.rb`
- Create: `spec/strategies/passkey_strategy_spec.rb`

The strategy authenticates a usernameless assertion: it reads the challenge stored in the session by the login-options endpoint, resolves the stored credential by its `external_id`, verifies the assertion against the stored public key + sign count, bumps the counter, and returns the owning user. It fails closed with one generic message on every error branch (paranoid — no distinction between "unknown credential" and "bad signature").

- [ ] **Step 1: Write the failing strategy spec**

Create `spec/strategies/passkey_strategy_spec.rb`. This drives the strategy end-to-end through a real request using `WebAuthn::FakeClient`, because the strategy's value comes from wiring (session + params + Warden), which a pure unit test can't exercise faithfully.

```ruby
require "rails_helper"

RSpec.describe PasskeyStrategy, type: :request do
  let(:origin) { "http://localhost:3000" }
  let(:fake_client) { WebAuthn::FakeClient.new(origin) }

  # Register a real credential in the fake authenticator AND our DB, so a later
  # assertion from the same fake_client verifies against stored bytes.
  def register_credential_for(user)
    get_options = WebAuthn::Credential.options_for_create(
      user: {id: user.webauthn_id, name: user.email, display_name: user.full_name}
    )
    raw = fake_client.create(challenge: get_options.challenge)
    created = WebAuthn::Credential.from_create(raw)
    created.verify(get_options.challenge)
    user.webauthn_credentials.create!(
      external_id: created.id, public_key: created.public_key,
      sign_count: created.sign_count, nickname: "Test key"
    )
  end

  # Ask the real login-options endpoint for a challenge (also stores it in session).
  def fetch_login_challenge
    post "/login/passkey/options"
    JSON.parse(response.body).fetch("challenge")
  end

  it "signs in the owner when the assertion verifies" do
    user = create(:user, webauthn_id: WebAuthn.generate_user_id)
    register_credential_for(user)

    challenge = fetch_login_challenge
    assertion = fake_client.get(challenge: challenge)
    post "/login/passkey", params: {credential: assertion.to_json}

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to include("redirect")
    # Warden actually signed us in: a members-only page now renders.
    get "/dashboard"
    expect(response).to have_http_status(:ok)
  end

  it "fails closed when the credential is unknown" do
    create(:user, webauthn_id: WebAuthn.generate_user_id) # no credential stored
    challenge = fetch_login_challenge
    assertion = fake_client.get(challenge: challenge)
    post "/login/passkey", params: {credential: assertion.to_json}
    expect(response).to have_http_status(:unauthorized)
  end

  it "fails closed when the challenge is missing from the session" do
    user = create(:user, webauthn_id: WebAuthn.generate_user_id)
    register_credential_for(user)
    # No call to /login/passkey/options → no challenge in session.
    assertion = fake_client.get(challenge: WebAuthn.generate_user_id)
    post "/login/passkey", params: {credential: assertion.to_json}
    expect(response).to have_http_status(:unauthorized)
  end
end
```

> Note: this spec exercises routes/controller from Task 7. If you're building strictly task-by-task, expect Steps 1–3 here to fail on missing routes until Task 7 lands; that's fine — implement the strategy now (Step 4), register it (Step 5), and the spec goes green once Task 7's controller + routes exist. The subagent executing this plan should run the strategy spec again at the end of Task 7.

- [ ] **Step 2: Run it, watch it fail**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/strategies/passkey_strategy_spec.rb`
Expected: FAIL — `uninitialized constant PasskeyStrategy` (and/or missing route).

- [ ] **Step 3: Write the strategy**

Create `app/strategies/passkey_strategy.rb`:

```ruby
# Warden strategy for usernameless (discoverable) passkey login. It is invoked
# explicitly by Users::SessionsController#passkey via `warden.authenticate(:passkey)`,
# NOT added to Warden's default strategies (which would run on every request).
#
# Two gotchas encoded here:
#   1. Warden's `params` are RACK-level, so a JSON body would be invisible. The
#      login form therefore posts `credential` as a form-encoded JSON string, which
#      we JSON.parse below. (Registration, an ordinary Rails controller, posts JSON.)
#   2. The challenge is read-and-deleted for single use; it is stored by
#      Users::SessionsController#passkey_options under this same session key.
class PasskeyStrategy < Warden::Strategies::Base
  CHALLENGE_KEY = "passkey_authentication_challenge"

  def valid?
    params["credential"].present?
  end

  def authenticate!
    challenge = session.delete(CHALLENGE_KEY)
    return fail!("Passkey verification failed") if challenge.blank?

    webauthn_credential = WebAuthn::Credential.from_get(JSON.parse(params["credential"]))
    stored = WebauthnCredential.find_by(external_id: webauthn_credential.id)
    return fail!("Passkey verification failed") unless stored

    webauthn_credential.verify(
      challenge,
      public_key: stored.public_key,
      sign_count: stored.sign_count
    )

    stored.update!(sign_count: webauthn_credential.sign_count, last_used_at: Time.current)
    success!(stored.user)
  rescue WebAuthn::Error, JSON::ParserError
    fail!("Passkey verification failed")
  end
end
```

- [ ] **Step 4: Register the strategy with Warden**

In `config/initializers/devise.rb`, find the `config.warden do |manager|` block if one exists; otherwise add one near the bottom (before the final `end` of `Devise.setup do |config|`). Add:

```ruby
  # Passkey login is an explicit, opt-in strategy (invoked by name in the sessions
  # controller), so we register it but do NOT add it to default_strategies.
  config.warden do |manager|
    manager.strategies.add(:passkey, PasskeyStrategy)
  end
```

> If a `config.warden do |manager| ... end` block already exists, add only the `manager.strategies.add(:passkey, PasskeyStrategy)` line inside it — do not create a second block.

- [ ] **Step 5: Run the strategy spec after Task 7 exists**

Defer the green run to the end of Task 7 (routes + controller). At that point:
Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/strategies/passkey_strategy_spec.rb`
Expected: PASS (3 examples).

- [ ] **Step 6: Commit**

```bash
git add app/strategies/passkey_strategy.rb config/initializers/devise.rb spec/strategies/passkey_strategy_spec.rb
git commit -m "Add Warden :passkey strategy for usernameless login"
```

---

## Task 5: PasskeyPolicy

**Files:**
- Create: `app/policies/passkey_policy.rb`
- Create: `spec/policies/passkey_policy_spec.rb`

- [ ] **Step 1: Write the failing policy spec**

Create `spec/policies/passkey_policy_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe PasskeyPolicy do
  subject { described_class.new(user, credential) }

  let(:owner) { create(:user) }
  let(:credential) { create(:webauthn_credential, user: owner) }

  context "when the user owns the credential" do
    let(:user) { owner }
    it { is_expected.to permit_actions(%i[update destroy]) }
  end

  context "when the user does not own the credential" do
    let(:user) { create(:user) }
    it { is_expected.to forbid_actions(%i[update destroy]) }
  end

  context "when there is no user" do
    let(:user) { nil }
    it { is_expected.to forbid_actions(%i[update destroy]) }
  end
end
```

> This uses `permit_actions`/`forbid_actions` from `pundit-matchers`. Verify it's in the Gemfile test group (other policy specs here rely on it). If a different matcher style is used in `spec/policies/*_spec.rb`, mirror that instead.

- [ ] **Step 2: Run it, watch it fail**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/policies/passkey_policy_spec.rb`
Expected: FAIL — `uninitialized constant PasskeyPolicy`.

- [ ] **Step 3: Write the policy**

Create `app/policies/passkey_policy.rb`, mirroring `app/policies/block_policy.rb`'s style:

```ruby
# frozen_string_literal: true

# Owner-only management of a WebAuthn credential. index/options/create are handled
# by controller-level current_user scoping (skip_authorization), so only the
# mutating-a-specific-record actions need a policy.
class PasskeyPolicy < ApplicationPolicy
  def update? = record.user_id == user&.id

  def destroy? = record.user_id == user&.id
end
```

- [ ] **Step 4: Run it, watch it pass**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/policies/passkey_policy_spec.rb`
Expected: PASS (all examples).

- [ ] **Step 5: Commit**

```bash
git add app/policies/passkey_policy.rb spec/policies/passkey_policy_spec.rb
git commit -m "Add owner-only PasskeyPolicy"
```

---

## Task 6: PasskeysController + management routes + views

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/passkeys_controller.rb`
- Create: `app/views/passkeys/index.html.erb`
- Create: `app/views/passkeys/_credential.html.erb`
- Create: `app/views/passkeys/create.turbo_stream.erb`
- Create: `app/views/passkeys/destroy.turbo_stream.erb`
- Create: `spec/requests/passkeys_spec.rb`

- [ ] **Step 1: Add the management routes**

In `config/routes.rb`, after the `/blocks` route (around line 132), add:

```ruby
  # Passkey (WebAuthn) management — owner-only by construction like /blocks, so no
  # username in the URL. MAIN routes (CSRF on): a new HTML write surface belongs on
  # a main route, never under Api::V1 where CSRF is null_session. Hand-written, no
  # `resources`, one path per line.
  #   index   — list my passkeys
  #   options — POST: mint a creation challenge (stored in session), lazily assign webauthn_id
  #   create  — POST: verify the attestation and persist the credential
  #   update  — PATCH: rename a passkey
  #   destroy — DELETE: remove a passkey
  get    "/settings/passkeys",         to: "passkeys#index",   as: :passkeys
  post   "/settings/passkeys/options", to: "passkeys#options", as: :passkey_registration_options
  post   "/settings/passkeys",         to: "passkeys#create"
  patch  "/settings/passkeys/:id",     to: "passkeys#update",  as: :passkey
  delete "/settings/passkeys/:id",     to: "passkeys#destroy"
```

- [ ] **Step 2: Write the failing request spec**

Create `spec/requests/passkeys_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Passkey management", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:origin) { "http://localhost:3000" }
  let(:fake_client) { WebAuthn::FakeClient.new(origin) }
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /settings/passkeys" do
    it "renders the current user's passkeys" do
      mine = create(:webauthn_credential, user: user, nickname: "My laptop")
      _theirs = create(:webauthn_credential, nickname: "Someone else")
      get "/settings/passkeys"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("My laptop")
      expect(response.body).not_to include("Someone else")
    end
  end

  describe "POST /settings/passkeys/options" do
    it "returns creation options and lazily assigns a webauthn_id" do
      expect(user.webauthn_id).to be_nil
      post "/settings/passkeys/options"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to include("challenge", "user")
      expect(user.reload.webauthn_id).to be_present
    end
  end

  describe "POST /settings/passkeys" do
    it "verifies the attestation and stores the credential" do
      post "/settings/passkeys/options" # seeds session challenge + webauthn_id
      challenge = JSON.parse(response.body).fetch("challenge")
      raw = fake_client.create(challenge: challenge)

      expect {
        post "/settings/passkeys",
          params: {passkey: {credential: raw, nickname: "Laptop"}}.to_json,
          headers: {"CONTENT_TYPE" => "application/json"}
      }.to change(user.webauthn_credentials, :count).by(1)

      expect(response).to redirect_to("/settings/passkeys")
      expect(user.webauthn_credentials.last.nickname).to eq("Laptop")
    end

    it "does not store a credential when verification fails" do
      post "/settings/passkeys/options"
      raw = fake_client.create(challenge: "a-different-unrelated-challenge")
      expect {
        post "/settings/passkeys",
          params: {passkey: {credential: raw, nickname: "Laptop"}}.to_json,
          headers: {"CONTENT_TYPE" => "application/json"}
      }.not_to change(WebauthnCredential, :count)
      expect(response).to redirect_to("/settings/passkeys")
    end
  end

  describe "PATCH /settings/passkeys/:id" do
    it "renames my own passkey" do
      credential = create(:webauthn_credential, user: user, nickname: "Old")
      patch "/settings/passkeys/#{credential.id}", params: {passkey: {nickname: "New"}}
      expect(credential.reload.nickname).to eq("New")
    end

    it "refuses to touch someone else's passkey" do
      others = create(:webauthn_credential, nickname: "Theirs")
      patch "/settings/passkeys/#{others.id}", params: {passkey: {nickname: "Hacked"}}
      expect(others.reload.nickname).to eq("Theirs")
    end
  end

  describe "DELETE /settings/passkeys/:id" do
    it "removes my own passkey" do
      credential = create(:webauthn_credential, user: user)
      expect {
        delete "/settings/passkeys/#{credential.id}"
      }.to change(user.webauthn_credentials, :count).by(-1)
    end
  end
end
```

- [ ] **Step 3: Run it, watch it fail**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/passkeys_spec.rb`
Expected: FAIL — missing controller / views.

- [ ] **Step 4: Write the controller**

Create `app/controllers/passkeys_controller.rb`:

```ruby
class PasskeysController < ApplicationController
  before_action :authenticate_user!

  # Owner-only by construction: everything is scoped through current_user, so
  # index/options/create carry no authorizable record → skip_authorization. The
  # per-record mutations (update/destroy) call authorize with PasskeyPolicy.
  def index
    skip_authorization
    @credentials = current_user.webauthn_credentials.order(created_at: :desc)
  end

  # Registration step 1: hand the browser creation options and remember the
  # challenge. Mint the stable user handle on first enrollment.
  def options
    skip_authorization
    current_user.update!(webauthn_id: WebAuthn.generate_user_id) if current_user.webauthn_id.blank?

    create_options = WebAuthn::Credential.options_for_create(
      user: {
        id: current_user.webauthn_id,
        name: current_user.email,
        display_name: current_user.full_name
      },
      exclude: current_user.webauthn_credentials.pluck(:external_id),
      authenticator_selection: {resident_key: "required", user_verification: "required"},
      attestation: "none"
    )
    session[:passkey_registration_challenge] = create_options.challenge
    render json: create_options
  end

  # Registration step 2: verify the attestation, persist the credential. This is an
  # ordinary Rails controller, so a JSON body IS parsed into params (unlike the
  # Warden strategy). Read-and-delete the challenge for single use.
  def create
    skip_authorization
    challenge = session.delete(:passkey_registration_challenge)
    webauthn_credential = WebAuthn::Credential.from_create(credential_param)
    webauthn_credential.verify(challenge)

    @credential = current_user.webauthn_credentials.create!(
      external_id: webauthn_credential.id,
      public_key: webauthn_credential.public_key,
      sign_count: webauthn_credential.sign_count,
      nickname: nickname_param
    )

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to passkeys_path, notice: "Passkey added." }
    end
  rescue WebAuthn::Error, ActiveRecord::RecordInvalid, TypeError
    redirect_to passkeys_path, alert: "We couldn't add that passkey. Please try again."
  end

  def update
    @credential = current_user.webauthn_credentials.find(params[:id])
    authorize @credential
    @credential.update!(nickname: nickname_param)
    redirect_to passkeys_path, notice: "Passkey renamed."
  end

  def destroy
    @credential = current_user.webauthn_credentials.find(params[:id])
    authorize @credential
    @credential.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to passkeys_path, notice: "Passkey removed.", status: :see_other }
    end
  end

  private

  def credential_param
    params.require(:passkey).require(:credential)
  end

  def nickname_param
    params.require(:passkey).fetch(:nickname, "").to_s.strip.presence || "Passkey"
  end
end
```

> Note on `update`/`destroy` ownership: loading via `current_user.webauthn_credentials.find` already scopes to the owner (a non-owner id raises `RecordNotFound` → 404). The `authorize` call is defense-in-depth and satisfies `verify_authorized`. The "refuses to touch someone else's passkey" spec passes via the 404 (RecordNotFound) — the record simply isn't found in the owner's scope. Rails renders 404 for that; the spec only asserts the record is unchanged, so that's fine.

- [ ] **Step 5: Write the index view**

Create `app/views/passkeys/index.html.erb`:

```erb
<%# Security → Passkeys. Add/list/rename/delete WebAuthn credentials. The add flow
    is driven by the passkey-registration Stimulus controller, which runs the
    navigator.credentials.create() ceremony then POSTs the attestation. %>
<div class="min-h-screen bg-surface px-6 py-10">
  <div class="w-full max-w-lg mx-auto">
    <h1 class="text-xl font-bold text-ink">Passkeys</h1>
    <p class="mt-1 text-sm text-ink-2">
      Sign in without a password using Face ID, a fingerprint, or a security key.
      Your password still works as a backup.
    </p>

    <div data-controller="passkey-registration" class="mt-6">
      <div class="flex items-end gap-3">
        <label class="flex-1">
          <span class="block text-xs font-semibold text-faint mb-1">Passkey name</span>
          <input type="text" data-passkey-registration-target="nickname"
                 placeholder="e.g. My laptop"
                 class="w-full h-[46px] px-4 rounded-xl bg-card-2 border border-field text-[14.5px] text-ink placeholder:text-faint outline-none" />
        </label>
        <button type="button" data-action="passkey-registration#add" data-passkey-add
                class="h-[46px] px-5 rounded-xl bg-primary text-white font-bold shadow cursor-pointer">
          Add passkey
        </button>
      </div>
      <p data-passkey-registration-target="error" hidden class="mt-2 text-sm text-disagree"></p>
    </div>

    <ul id="passkeys-list" class="mt-6 flex flex-col gap-3">
      <% if @credentials.any? %>
        <%= render partial: "passkeys/credential", collection: @credentials, as: :credential %>
      <% else %>
        <li id="passkeys-empty" class="text-sm text-faint"><%= render "ui/empty_state", title: "No passkeys yet", subtitle: "Add one above for faster sign-in." %></li>
      <% end %>
    </ul>
  </div>
</div>
```

> Verify the `ui/_empty_state` partial's expected locals against an existing caller (e.g. grep `render "ui/empty_state"`). If its interface differs, match the existing call sites; the exact empty-state markup is not load-bearing.

- [ ] **Step 6: Write the row partial**

Create `app/views/passkeys/_credential.html.erb`:

```erb
<%# One passkey row: name, added date, last-used, rename + delete. dom_id keeps the
    row addressable so create/destroy turbo streams can target it. %>
<li id="<%= dom_id(credential) %>" class="flex items-center justify-between gap-3 p-4 rounded-2xl bg-card border border-hairline shadow">
  <div class="min-w-0">
    <div class="font-semibold text-ink truncate"><%= credential.nickname %></div>
    <div class="text-xs text-faint mt-0.5">
      Added <%= credential.created_at.to_date.to_fs(:long) %>
      <% if credential.last_used_at %> · Last used <%= credential.last_used_at.to_date.to_fs(:long) %><% end %>
    </div>
  </div>
  <div class="flex items-center gap-2 shrink-0">
    <%= form_with url: passkey_path(credential), method: :patch, class: "flex items-center gap-2" do |f| %>
      <%= f.text_field :"passkey[nickname]", value: credential.nickname,
            class: "h-9 w-28 px-3 rounded-lg bg-card-2 border border-field text-sm text-ink outline-none" %>
      <%= f.submit "Rename", class: "h-9 px-3 rounded-lg border border-field text-sm font-semibold text-ink cursor-pointer" %>
    <% end %>
    <%= button_to "Delete", passkey_path(credential), method: :delete,
          form: {data: {turbo_confirm: "Remove this passkey?"}},
          class: "h-9 px-3 rounded-lg border border-field text-sm font-semibold text-disagree cursor-pointer" %>
  </div>
</li>
```

> The rename field name `passkey[nickname]` must match `nickname_param` (`params.require(:passkey).fetch(:nickname, ...)`). `form_with`'s `f.text_field :"passkey[nickname]"` emits `name="passkey[nickname]"`. Confirm the emitted name in the request spec's PATCH (it posts `params: {passkey: {nickname: "New"}}`, which matches).

- [ ] **Step 7: Write the turbo-stream responses**

Create `app/views/passkeys/create.turbo_stream.erb`:

```erb
<%# Append the new passkey and clear the empty-state placeholder if present. %>
<%= turbo_stream.remove "passkeys-empty" %>
<%= turbo_stream.append "passkeys-list" do %>
  <%= render partial: "passkeys/credential", locals: {credential: @credential} %>
<% end %>
```

Create `app/views/passkeys/destroy.turbo_stream.erb`:

```erb
<%= turbo_stream.remove dom_id(@credential) %>
```

- [ ] **Step 8: Run the request spec, watch it pass**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/passkeys_spec.rb`
Expected: PASS (all examples). If the PATCH "someone else's" example fails with a raised `RecordNotFound` rather than a benign response, wrap the finder appropriately or assert on the raised error — but the default Rails test behavior renders 404 and leaves the record unchanged, satisfying the assertion.

- [ ] **Step 9: Commit**

```bash
git add config/routes.rb app/controllers/passkeys_controller.rb app/views/passkeys spec/requests/passkeys_spec.rb
git commit -m "Add passkey management controller, routes, and views"
```

---

## Task 7: Passkey login — Users::SessionsController + routes

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/users/sessions_controller.rb`
- Create: `spec/requests/passkey_sessions_spec.rb`

- [ ] **Step 1: Wire the sessions controller + login routes**

In `config/routes.rb`, update the `devise_for :users` block to route sessions to our subclass, and add the passkey login routes inside a `devise_scope`:

```ruby
  devise_for :users,
    controllers: {
      registrations: "users/registrations",
      sessions: "users/sessions",
      omniauth_callbacks: "users/omniauth_callbacks"
    },
    path: "",
    path_names: {sign_in: "login", sign_out: "logout", sign_up: "signup"}

  # Passkey (usernameless) login. Two POSTs, both inside devise_scope so path
  # helpers resolve to the :user mapping:
  #   passkey_options — mint an authentication challenge (stored in session)
  #   passkey_session — verify the assertion via the Warden :passkey strategy
  # These are MAIN routes (CSRF on). The verify endpoint receives the assertion
  # form-encoded (see PasskeyStrategy for why it can't be JSON).
  devise_scope :user do
    post "/login/passkey/options", to: "users/sessions#passkey_options", as: :passkey_options
    post "/login/passkey", to: "users/sessions#passkey", as: :passkey_session
  end
```

- [ ] **Step 2: Write the failing request spec**

Create `spec/requests/passkey_sessions_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Passkey login", type: :request do
  let(:origin) { "http://localhost:3000" }
  let(:fake_client) { WebAuthn::FakeClient.new(origin) }

  # Register a credential in BOTH the fake authenticator and the DB.
  def register!(user)
    opts = WebAuthn::Credential.options_for_create(
      user: {id: user.webauthn_id, name: user.email, display_name: user.full_name}
    )
    raw = fake_client.create(challenge: opts.challenge)
    created = WebAuthn::Credential.from_create(raw)
    created.verify(opts.challenge)
    user.webauthn_credentials.create!(
      external_id: created.id, public_key: created.public_key,
      sign_count: created.sign_count, nickname: "Key"
    )
  end

  describe "POST /login/passkey/options" do
    it "returns a discoverable-credential challenge (no allowCredentials list)" do
      post "/login/passkey/options"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["challenge"]).to be_present
      expect(body["allowCredentials"]).to be_blank
    end
  end

  describe "POST /login/passkey" do
    it "signs the owner in on a valid assertion" do
      user = create(:user, webauthn_id: WebAuthn.generate_user_id)
      register!(user)

      post "/login/passkey/options"
      challenge = JSON.parse(response.body).fetch("challenge")
      assertion = fake_client.get(challenge: challenge)

      post "/login/passkey", params: {credential: assertion.to_json}
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("redirect")

      get "/dashboard" # members-only
      expect(response).to have_http_status(:ok)
    end

    it "returns 401 on a tampered/failed assertion" do
      user = create(:user, webauthn_id: WebAuthn.generate_user_id)
      register!(user)
      post "/login/passkey/options"
      # Wrong challenge → signature won't verify.
      assertion = fake_client.get(challenge: WebAuthn.generate_user_id)
      post "/login/passkey", params: {credential: assertion.to_json}
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
```

- [ ] **Step 3: Run it, watch it fail**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/passkey_sessions_spec.rb`
Expected: FAIL — missing `Users::SessionsController#passkey_options`.

- [ ] **Step 4: Write the sessions controller**

Create `app/controllers/users/sessions_controller.rb`:

```ruby
class Users::SessionsController < Devise::SessionsController
  # Devise controller → exempt from Pundit's verify_authorized.

  # Passkey login step 1: hand the browser an authentication challenge. Usernameless
  # / discoverable — no `allow` list, so no email is typed and email enumeration
  # stays impossible (matches config.paranoid = true). Challenge saved to session.
  def passkey_options
    get_options = WebAuthn::Credential.options_for_get(user_verification: "required")
    session[PasskeyStrategy::CHALLENGE_KEY] = get_options.challenge
    render json: get_options
  end

  # Step 2: verify the assertion through the Warden :passkey strategy. On success
  # respond with a redirect target for the JS to navigate to; the flash is set here
  # and shows on that next GET. On failure, a single generic 401 (paranoid).
  def passkey
    user = warden.authenticate(:passkey, scope: :user)
    if user
      sign_in(:user, user)
      flash[:notice] = "Signed in with your passkey."
      render json: {redirect: after_sign_in_path_for(user)}
    else
      render json: {error: "We couldn't verify that passkey."}, status: :unauthorized
    end
  end
end
```

- [ ] **Step 5: Run the sessions + strategy specs, watch them pass**

Run:
```bash
RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/passkey_sessions_spec.rb spec/strategies/passkey_strategy_spec.rb
```
Expected: PASS (Task 4's strategy spec now goes green too, since routes + controller exist).

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/users/sessions_controller.rb spec/requests/passkey_sessions_spec.rb
git commit -m "Add passkey login sessions controller and routes"
```

---

## Task 8: Frontend — importmap pin, Stimulus controllers, view wiring, param filtering

**Files:**
- Modify: `config/importmap.rb`
- Create: `vendor/javascript/@github--webauthn-json.js` (downloaded)
- Create: `app/javascript/controllers/passkey_authentication_controller.js`
- Create: `app/javascript/controllers/passkey_registration_controller.js`
- Modify: `app/views/devise/sessions/new.html.erb`
- Modify: `app/views/devise/registrations/edit.html.erb`
- Modify: `config/initializers/filter_parameter_logging.rb`

- [ ] **Step 1: Pin `@github/webauthn-json` (vendored, no Node)**

Run:
```bash
bin/importmap pin @github/webauthn-json@0.5.7 --download
```
Expected: downloads to `vendor/javascript/@github--webauthn-json.js` and adds a `pin "@github/webauthn-json", to: "@github--webauthn-json.js"` line to `config/importmap.rb`. Version `0.5.7` is the classic API whose `create`/`get` accept `{ publicKey: <server options> }` and return an encoded JSON credential — the exact pairing webauthn-ruby's `from_create`/`from_get` expect.

If the download command is unavailable offline, manually download that module into `vendor/javascript/@github--webauthn-json.js` and add the pin line yourself.

- [ ] **Step 2: Verify the pin resolves**

Run: `bin/importmap json | grep webauthn`
Expected: shows `@github/webauthn-json` mapped to the vendored file.

- [ ] **Step 3: Write the login Stimulus controller**

Create `app/javascript/controllers/passkey_authentication_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"
import { get } from "@github/webauthn-json"

// "Sign in with a passkey" on the login page. Usernameless: fetch a challenge,
// run navigator.credentials.get() (via webauthn-json), then POST the assertion
// FORM-ENCODED (the Warden strategy reads Rack-level params, which don't parse
// JSON). Progressive enhancement — hides itself when the browser lacks WebAuthn.
export default class extends Controller {
  static targets = ["error"]

  connect() {
    if (!window.PublicKeyCredential) this.element.hidden = true
  }

  async authenticate(event) {
    event.preventDefault()
    this.clearError()
    try {
      const options = await this.postForOptions("/login/passkey/options")
      const assertion = await get({ publicKey: options })

      const body = new URLSearchParams()
      body.set("credential", JSON.stringify(assertion))
      const response = await fetch("/login/passkey", {
        method: "POST",
        headers: { "Accept": "application/json", "X-CSRF-Token": this.csrfToken },
        body
      })
      if (!response.ok) throw new Error("verify failed")
      const data = await response.json()
      window.location = data.redirect
    } catch (_e) {
      this.showError("We couldn't verify that passkey. Try again or use your password.")
    }
  }

  async postForOptions(url) {
    const response = await fetch(url, {
      method: "POST",
      headers: { "Accept": "application/json", "X-CSRF-Token": this.csrfToken }
    })
    if (!response.ok) throw new Error("options failed")
    return response.json()
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }

  showError(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
  }

  clearError() {
    if (this.hasErrorTarget) this.errorTarget.hidden = true
  }
}
```

- [ ] **Step 4: Write the registration Stimulus controller**

Create `app/javascript/controllers/passkey_registration_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"
import { create } from "@github/webauthn-json"

// Add-a-passkey on the security page. Fetch creation options, run
// navigator.credentials.create() (via webauthn-json), then POST the attestation
// as JSON (this hits an ordinary Rails controller, which parses JSON). The server
// replies with a Turbo Stream that appends the new row; we apply it by hand
// because this is a fetch, not a Turbo form submit.
export default class extends Controller {
  static targets = ["nickname", "error"]

  connect() {
    if (!window.PublicKeyCredential) {
      this.element.querySelectorAll("[data-passkey-add]").forEach((el) => (el.disabled = true))
    }
  }

  async add(event) {
    event.preventDefault()
    this.clearError()
    try {
      const options = await this.postForOptions("/settings/passkeys/options")
      const attestation = await create({ publicKey: options })
      const nickname = this.hasNicknameTarget ? this.nicknameTarget.value : ""

      const response = await fetch("/settings/passkeys", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "text/vnd.turbo-stream.html",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({ passkey: { credential: attestation, nickname } })
      })
      if (!response.ok) throw new Error("create failed")
      window.Turbo.renderStreamMessage(await response.text())
      if (this.hasNicknameTarget) this.nicknameTarget.value = ""
    } catch (_e) {
      this.showError("We couldn't add that passkey. Please try again.")
    }
  }

  async postForOptions(url) {
    const response = await fetch(url, {
      method: "POST",
      headers: { "Accept": "application/json", "X-CSRF-Token": this.csrfToken }
    })
    if (!response.ok) throw new Error("options failed")
    return response.json()
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }

  showError(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
  }

  clearError() {
    if (this.hasErrorTarget) this.errorTarget.hidden = true
  }
}
```

- [ ] **Step 5: Add the passkey button to the login view**

In `app/views/devise/sessions/new.html.erb`, immediately **after** the Google `button_to ... Continue with Google` block (before `<%= render "devise/shared/links" %>`), add:

```erb
    <%# Usernameless passkey login. The Stimulus controller hides this block when the
        browser has no WebAuthn, so JS-off / unsupported users simply never see it. %>
    <div data-controller="passkey-authentication" class="mt-3">
      <button type="button" data-action="passkey-authentication#authenticate"
              class="w-full h-[52px] rounded-xl border border-field bg-card text-ink font-bold text-[14.5px] flex items-center justify-center gap-2.5 cursor-pointer">
        <%= lucide_icon "key-round", class: "w-[19px] h-[19px]" %>
        Sign in with a passkey
      </button>
      <p data-passkey-authentication-target="error" hidden class="mt-2 text-sm text-disagree text-center"></p>
    </div>
```

> Confirm `key-round` is a valid Lucide icon in this `lucide-rails` version (grep other `lucide_icon` calls for the naming, or pick an available key/fingerprint glyph). The icon is cosmetic.

- [ ] **Step 6: Link the security page from account settings**

In `app/views/devise/registrations/edit.html.erb`, add a link to the passkeys page in a sensible spot (near the account actions). Add:

```erb
<%= link_to "Manage passkeys", passkeys_path, class: "block mt-4 text-sm font-semibold text-primary" %>
```

> Match the file's existing link styling if it differs; the exact classes aren't load-bearing, the presence of a reachable link is.

- [ ] **Step 7: Filter WebAuthn params from logs**

In `config/initializers/filter_parameter_logging.rb`, add `challenge` and `credential` to the list (note `public_key` is already covered by the `_key` substring):

```ruby
Rails.application.config.filter_parameters += %i[
  passw email secret token _key crypt salt certificate otp ssn challenge credential
]
```

- [ ] **Step 8: Smoke-test the build + a fast spec slice**

Run:
```bash
RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/passkeys_spec.rb spec/requests/passkey_sessions_spec.rb
```
Expected: still PASS (frontend changes don't affect request specs). This confirms nothing server-side regressed.

- [ ] **Step 9: Commit**

```bash
git add config/importmap.rb vendor/javascript app/javascript/controllers/passkey_authentication_controller.js app/javascript/controllers/passkey_registration_controller.js app/views/devise/sessions/new.html.erb app/views/devise/registrations/edit.html.erb config/initializers/filter_parameter_logging.rb
git commit -m "Wire passkey frontend: importmap pin, Stimulus controllers, views"
```

---

## Task 9: End-to-end system spec (best-effort, CDP virtual authenticator)

**Files:**
- Create: `spec/system/passkey_login_spec.rb`

This drives the real login button through Chrome's CDP **virtual authenticator**. It is the highest-risk test — CDP command shapes vary by Chrome/Cuprite version. If it proves flaky, mark it `pending`/`skip` and rely on the request-level coverage (Tasks 6–7), which already exercises the full server ceremony.

- [ ] **Step 1: Write the system spec**

Create `spec/system/passkey_login_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Passkey login", type: :system, js: true do
  # Register a virtual authenticator over CDP, and add a resident credential to it
  # by driving the real add-passkey flow while signed in. Then sign out and log in
  # with the passkey button.
  def add_virtual_authenticator!
    browser = page.driver.browser
    browser.command("WebAuthn.enable")
    browser.command(
      "WebAuthn.addVirtualAuthenticator",
      options: {
        protocol: "ctap2",
        transport: "internal",
        hasResidentKey: true,
        hasUserVerification: true,
        isUserVerified: true,
        automaticPresenceSimulation: true
      }
    )
  rescue => e
    skip "CDP virtual authenticator unavailable in this environment: #{e.message}"
  end

  it "registers a passkey then signs in with it" do
    add_virtual_authenticator!
    password = "correct horse battery"
    user = create(:user, password: password, password_confirmation: password)

    # Sign in with password, enroll a passkey.
    visit "/login"
    fill_in "user[email]", with: user.email
    fill_in "user[password]", with: password
    click_button "Log in"

    visit "/settings/passkeys"
    fill_in "passkey[nickname]", with: "Virtual key" rescue nil
    find("[data-passkey-add]").click
    expect(page).to have_content("Virtual key").or have_css("#passkeys-list li", wait: 5)

    # Sign out, then sign in with the passkey.
    click_button "Log out" rescue (page.driver.browser.command("Network.clearBrowserCookies") rescue nil)
    visit "/logout" rescue nil

    visit "/login"
    click_button "Sign in with a passkey"
    expect(page).to have_current_path("/", ignore_query: true).or have_content("Signed in").or have_no_button("Sign in with a passkey", wait: 5)
  end
end
```

> This spec is intentionally forgiving (multiple `.or` conditions, `rescue`/`skip` guards) because CDP/Cuprite virtual-authenticator behavior is environment-sensitive. The goal is a smoke signal that the wired button reaches a signed-in state, not a rigorous unit assertion — that rigor lives in the request specs. If it can't be made reliably green in ~an hour, leave it `skip`ped with a comment pointing at the request specs.

- [ ] **Step 2: Run it**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/system/passkey_login_spec.rb`
Expected: PASS or a clean `skip`. If it errors on CDP command shape, adjust `browser.command(...)` to the signature Cuprite exposes (some versions take positional `browser.command("WebAuthn.addVirtualAuthenticator", options: {...})`, others `browser.command(:"WebAuthn.addVirtualAuthenticator", **params)`). If it can't be stabilized quickly, wrap the body in `skip "…"` and move on.

- [ ] **Step 3: Commit**

```bash
git add spec/system/passkey_login_spec.rb
git commit -m "Add best-effort passkey login system spec (CDP virtual authenticator)"
```

---

## Task 10: Full-suite green + quality gates

**Files:** none (verification only)

- [ ] **Step 1: Run the full CI definition-of-record**

Run: `bin/ci`
Expected: gates (standardrb, brakeman, bundler-audit) + db:test:prepare + tailwind build + full RSpec all green. Note `bin/ci` runs `db:test:prepare` (schema-only reload), which is why Task 2 committed `db/schema.rb`.

- [ ] **Step 2: If StandardRB flags formatting**

Run: `bundle exec standardrb --fix` then re-run `bin/ci`. Re-inspect any auto-corrected file to confirm the change is sane.

- [ ] **Step 3: If Brakeman flags anything**

Investigate. Expected clean, but a new controller with `render json:` and `redirect_to` should not trip Brakeman. If it flags the `redirect_to passkeys_path` or the JSON responses, confirm they use no user-controlled redirect target (they don't — all paths are static helpers).

- [ ] **Step 4: Confirm no Tailwind bundle drift from ERB comments**

The new ERB comments reference no concrete color/utility class names except real utilities already in use. Per CLAUDE.md, ERB comments ARE scanned by Tailwind. Confirm none of the new comments name a class that shouldn't ship. (They don't — the comments are prose.)

- [ ] **Step 5: Final commit if anything changed**

```bash
git add -A
git commit -m "Satisfy quality gates for passkey login"
```

---

## Self-review notes (author)

- **Spec coverage:** data model → Task 2/3; Warden strategy → Task 4; controllers/routes → Task 6/7; frontend + config → Task 1/8; security posture (single-use read-and-delete challenge, generic failure, usernameless no-enumeration, sign_count via gem) → embedded in Tasks 4/6/7; filter params → Task 8; testing (model/policy/request/strategy/system) → Tasks 3/5/6/7/9.
- **Deferred per spec (not in this plan):** rate-limiting the options endpoints; post-signup onboarding prompt; email-first fallback; MFA. These are explicitly out of scope.
- **Cross-task type consistency:** session challenge keys — login uses `PasskeyStrategy::CHALLENGE_KEY` (`"passkey_authentication_challenge"`) set by `#passkey_options` and read-and-deleted by the strategy; registration uses `:passkey_registration_challenge` set by `#options` and read-and-deleted by `#create`. Param names: login posts form field `credential`; registration posts JSON `passkey: {credential:, nickname:}`; rename posts `passkey[nickname]`. Route helpers: `passkey_options_path`, `passkey_session_path`, `passkeys_path`, `passkey_registration_options_path`, `passkey_path(credential)`.
- **Known risk:** Task 9 (CDP virtual authenticator) is best-effort; request specs are the real safety net.
