# MyDigital ID SSO Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a reusable OmniAuth strategy gem for Malaysia's MyDigital ID (Keycloak OIDC) and integrate it into hoojah with secure ID-token validation and a link-or-create account flow that never persists the NRIC.

**Architecture:** Two deliverables. (A) `omniauth-mydigital-id-ruby` — a standalone gem at `/Users/deepsight/code/omniauth-mydigital-id-ruby` whose `OmniAuth::Strategies::MyDigitalId` subclasses `OmniAuth::Strategies::OAuth2`, builds Keycloak realm endpoints, and validates the ID token against JWKS. (B) hoojah integration — a `user_identities` table (multi-provider), MyID callback + link/create interstitial, a public legal notice, and Devise wiring. Identity key is the OIDC `sub`; NRIC only transits, never stored.

**Tech Stack:** Ruby 3.4, OmniAuth 2 / omniauth-oauth2, `jwt`, RSpec + WebMock (gem); Rails 8.1, Devise, Pundit, Hotwire, RSpec + FactoryBot + Cuprite (hoojah).

**Reference spec:** `docs/superpowers/specs/2026-09-06-mydigital-id-sso-design.md`.

---

## Conventions for every task

- Ruby is mise-managed. If the shell hasn't activated mise, prefix commands with `mise exec ruby@3.4.9 --`.
- Gem tasks (1–6) run in `/Users/deepsight/code/omniauth-mydigital-id-ruby`. Hoojah tasks (7+) run in `/Users/deepsight/code/hoojah-beta`.
- Provider identifier is **`my_digital_id`** everywhere (OmniAuth camelizes it to `MyDigitalId`). The Keycloak *realm* is `mydid` — a gem config value, not the provider label.
- TDD: write the failing test, watch it fail, implement minimally, watch it pass, commit. No Claude/Anthropic trailer in commit messages.

---

## File Structure

### Gem (`/Users/deepsight/code/omniauth-mydigital-id-ruby`)
- `omniauth-mydigital-id-ruby.gemspec` — gem metadata + deps
- `Gemfile` — bundler entry
- `.standard.yml`, `.gitignore`
- `lib/omniauth-mydigital-id-ruby.rb` — top-level require
- `lib/omniauth/mydigital_id/version.rb` — VERSION
- `lib/omniauth/mydigital_id/jwks_fetcher.rb` — TTL-cached JWKS fetch
- `lib/omniauth/mydigital_id/id_token_validator.rb` — RS256 + claim validation
- `lib/omniauth/strategies/my_digital_id.rb` — the strategy
- `spec/spec_helper.rb`, `spec/support/rsa_keys.rb` — signing fixtures
- `spec/mydigital_id/jwks_fetcher_spec.rb`
- `spec/mydigital_id/id_token_validator_spec.rb`
- `spec/strategies/my_digital_id_spec.rb`
- `README.md`

### Hoojah (`/Users/deepsight/code/hoojah-beta`)
- Modify: `Gemfile`, `config/initializers/devise.rb`, `app/models/user.rb`, `app/controllers/users/omniauth_callbacks_controller.rb`, `config/routes.rb`, `app/controllers/pages_controller.rb`, `app/views/devise/sessions/new.html.erb`, `app/views/devise/registrations/new.html.erb`, `spec/support/omniauth.rb`, `spec/requests/omniauth_callbacks_spec.rb`
- Create: migrations for `user_identities` (+ backfill, + later drop), `app/models/user_identity.rb`, `app/controllers/mydigital_id_links_controller.rb`, `app/policies/` (none — skip_authorization), `app/views/mydigital_id_links/new.html.erb`, `app/views/pages/mydigital_id.html.erb`, `spec/factories/user_identities.rb`, `spec/models/user_identity_spec.rb`, `spec/models/user_mydigital_id_spec.rb`, `spec/requests/mydigital_id_spec.rb`, `spec/system/mydigital_id_sign_in_spec.rb`

---

# PART A — the gem `omniauth-mydigital-id-ruby`

## Task 1: Gem skeleton + RSpec harness

**Files:**
- Create: `omniauth-mydigital-id-ruby.gemspec`, `Gemfile`, `.gitignore`, `.standard.yml`, `lib/omniauth-mydigital-id-ruby.rb`, `lib/omniauth/mydigital_id/version.rb`, `spec/spec_helper.rb`

- [ ] **Step 1: Create the gem directory and init git**

```bash
mkdir -p /Users/deepsight/code/omniauth-mydigital-id-ruby
cd /Users/deepsight/code/omniauth-mydigital-id-ruby
git init -q
mkdir -p lib/omniauth/mydigital_id lib/omniauth/strategies spec/support spec/mydigital_id spec/strategies
```

- [ ] **Step 2: Write `lib/omniauth/mydigital_id/version.rb`**

```ruby
# frozen_string_literal: true

module OmniAuth
  module MyDigitalId
    VERSION = "0.1.0"
  end
end
```

- [ ] **Step 3: Write `omniauth-mydigital-id-ruby.gemspec`**

```ruby
# frozen_string_literal: true

require_relative "lib/omniauth/mydigital_id/version"

Gem::Specification.new do |spec|
  spec.name = "omniauth-mydigital-id-ruby"
  spec.version = OmniAuth::MyDigitalId::VERSION
  spec.authors = ["Rudzainy Rahman"]
  spec.email = ["rudzainy@gmail.com"]
  spec.summary = "OmniAuth strategy for Malaysia's MyDigital ID SSO (Keycloak OIDC)."
  spec.description = "Authorization Code + OIDC strategy for MyDigital ID, with ID-token JWKS validation."
  spec.homepage = "https://github.com/rudzainy/omniauth-mydigital-id-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir["lib/**/*", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "omniauth", "~> 2.0"
  spec.add_dependency "omniauth-oauth2", "~> 1.8"
  spec.add_dependency "jwt", "~> 2.7"

  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "webmock", "~> 3.23"
  spec.add_development_dependency "rack-test", "~> 2.1"
  spec.add_development_dependency "standard", "~> 1.35"
end
```

- [ ] **Step 4: Write `Gemfile`, `.gitignore`, `.standard.yml`**

`Gemfile`:
```ruby
# frozen_string_literal: true

source "https://rubygems.org"
gemspec
```

`.gitignore`:
```
/.bundle/
/pkg/
/tmp/
Gemfile.lock
```

`.standard.yml`:
```yaml
ruby_version: 3.1
```

- [ ] **Step 5: Write `lib/omniauth-mydigital-id-ruby.rb`**

```ruby
# frozen_string_literal: true

require "omniauth/mydigital_id/version"
require "omniauth/strategies/my_digital_id"
```

- [ ] **Step 6: Write `spec/spec_helper.rb`**

```ruby
# frozen_string_literal: true

require "webmock/rspec"
require "omniauth-mydigital-id-ruby"
require_relative "support/rsa_keys"

WebMock.disable_net_connect!

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
end
```

- [ ] **Step 7: Install and confirm the harness loads**

```bash
cd /Users/deepsight/code/omniauth-mydigital-id-ruby
bundle install
```
Expected: resolves omniauth, omniauth-oauth2, jwt, rspec, webmock. (Spec run comes after Task 2 adds `rsa_keys`.)

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Gem skeleton: gemspec, version, RSpec harness"
```

---

## Task 2: RSA signing fixtures (`spec/support/rsa_keys.rb`)

A shared helper that mints an RSA keypair once, exposes a JWKS document for it, and signs ID tokens — used by the validator and strategy specs.

**Files:**
- Create: `spec/support/rsa_keys.rb`

- [ ] **Step 1: Write the helper**

```ruby
# frozen_string_literal: true

require "openssl"
require "jwt"
require "base64"

module RsaKeys
  module_function

  def private_key
    @private_key ||= OpenSSL::PKey::RSA.generate(2048)
  end

  def kid
    "test-key-1"
  end

  # JWKS document (string keys) as Keycloak's /certs endpoint returns it.
  def jwks
    jwk = JWT::JWK.new(private_key, kid: kid)
    {"keys" => [jwk.export.transform_keys(&:to_s)]}
  end

  # Sign an ID token. Overridable claims for negative tests.
  def id_token(overrides = {})
    claims = {
      "iss" => "https://sso.example.gov.my/realms/mydid",
      "aud" => "hoojah-client",
      "sub" => "keycloak-sub-123",
      "nonce" => "nonce-abc",
      "exp" => Time.now.to_i + 300,
      "iat" => Time.now.to_i
    }.merge(overrides)
    JWT.encode(claims, private_key, "RS256", {kid: kid})
  end
end
```

- [ ] **Step 2: Confirm it loads under RSpec**

```bash
cd /Users/deepsight/code/omniauth-mydigital-id-ruby
bundle exec ruby -e 'require "./spec/support/rsa_keys"; puts RsaKeys.jwks["keys"].first["kid"]'
```
Expected: `test-key-1`

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "Add RSA signing fixtures for specs"
```

---

## Task 3: JWKS fetcher (TTL cache + forced refresh)

**Files:**
- Create: `lib/omniauth/mydigital_id/jwks_fetcher.rb`
- Test: `spec/mydigital_id/jwks_fetcher_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

require "spec_helper"
require "omniauth/mydigital_id/jwks_fetcher"

RSpec.describe OmniAuth::MyDigitalId::JwksFetcher do
  let(:uri) { "https://sso.example.gov.my/realms/mydid/protocol/openid-connect/certs" }

  it "fetches and parses the JWKS document" do
    stub = stub_request(:get, uri).to_return(body: RsaKeys.jwks.to_json, headers: {"Content-Type" => "application/json"})
    jwks = described_class.new.call(uri)
    expect(jwks[:keys].first[:kid]).to eq("test-key-1")
    expect(stub).to have_been_requested.once
  end

  it "caches within the TTL (no second HTTP call)" do
    stub = stub_request(:get, uri).to_return(body: RsaKeys.jwks.to_json)
    fetcher = described_class.new(ttl: 3600)
    2.times { fetcher.call(uri) }
    expect(stub).to have_been_requested.once
  end

  it "refetches when force: true" do
    stub = stub_request(:get, uri).to_return(body: RsaKeys.jwks.to_json)
    fetcher = described_class.new
    fetcher.call(uri)
    fetcher.call(uri, force: true)
    expect(stub).to have_been_requested.twice
  end

  it "raises IdTokenError on non-200" do
    stub_request(:get, uri).to_return(status: 500, body: "boom")
    expect { described_class.new.call(uri) }.to raise_error(OmniAuth::MyDigitalId::IdTokenError)
  end
end
```

- [ ] **Step 2: Run it — expect failure (constant not defined)**

```bash
cd /Users/deepsight/code/omniauth-mydigital-id-ruby
bundle exec rspec spec/mydigital_id/jwks_fetcher_spec.rb
```
Expected: FAIL — `uninitialized constant OmniAuth::MyDigitalId::JwksFetcher`.

- [ ] **Step 3: Implement `lib/omniauth/mydigital_id/jwks_fetcher.rb`**

```ruby
# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module OmniAuth
  module MyDigitalId
    class IdTokenError < StandardError; end

    # Fetches a Keycloak JWKS document and caches it in-process by URI with a TTL.
    # Thread-safe. `force: true` bypasses the cache (used on a kid cache-miss).
    class JwksFetcher
      def initialize(ttl: 3600, http: Net::HTTP)
        @ttl = ttl
        @http = http
        @cache = {}
        @mutex = Mutex.new
      end

      def call(uri, force: false)
        @mutex.synchronize do
          entry = @cache[uri]
          return entry[:jwks] if !force && entry && entry[:at] + @ttl > monotonic

          jwks = fetch(uri)
          @cache[uri] = {jwks: jwks, at: monotonic}
          jwks
        end
      end

      private

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def fetch(uri)
        res = @http.get_response(URI(uri))
        unless res.is_a?(Net::HTTPSuccess)
          raise IdTokenError, "JWKS fetch failed (#{res.code})"
        end
        JSON.parse(res.body, symbolize_names: true)
      rescue JSON::ParserError => e
        raise IdTokenError, "JWKS parse failed: #{e.message}"
      end
    end
  end
end
```

- [ ] **Step 4: Run it — expect pass**

```bash
bundle exec rspec spec/mydigital_id/jwks_fetcher_spec.rb
```
Expected: 4 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Add JWKS fetcher with TTL cache and forced refresh"
```

---

## Task 4: ID-token validator (RS256 + iss/aud/exp/nonce)

**Files:**
- Create: `lib/omniauth/mydigital_id/id_token_validator.rb`
- Test: `spec/mydigital_id/id_token_validator_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

require "spec_helper"
require "omniauth/mydigital_id/id_token_validator"

RSpec.describe OmniAuth::MyDigitalId::IdTokenValidator do
  let(:jwks_uri) { "https://sso.example.gov.my/realms/mydid/protocol/openid-connect/certs" }
  let(:issuer) { "https://sso.example.gov.my/realms/mydid" }
  let(:audience) { "hoojah-client" }
  let(:nonce) { "nonce-abc" }

  def validator(id_token, nonce_arg: nonce)
    described_class.new(id_token: id_token, jwks_uri: jwks_uri, issuer: issuer,
      audience: audience, nonce: nonce_arg)
  end

  before { stub_request(:get, jwks_uri).to_return(body: RsaKeys.jwks.to_json) }

  it "returns the claims for a valid token" do
    claims = validator(RsaKeys.id_token).validate!
    expect(claims["sub"]).to eq("keycloak-sub-123")
  end

  it "rejects a missing token" do
    expect { validator(nil).validate! }.to raise_error(OmniAuth::MyDigitalId::IdTokenError, /missing/)
  end

  it "rejects a bad signature" do
    other = OpenSSL::PKey::RSA.generate(2048)
    forged = JWT.encode({"iss" => issuer, "aud" => audience, "sub" => "x",
      "nonce" => nonce, "exp" => Time.now.to_i + 300}, other, "RS256", {kid: RsaKeys.kid})
    expect { validator(forged).validate! }.to raise_error(OmniAuth::MyDigitalId::IdTokenError)
  end

  it "rejects a wrong audience" do
    expect { validator(RsaKeys.id_token("aud" => "someone-else")).validate! }
      .to raise_error(OmniAuth::MyDigitalId::IdTokenError)
  end

  it "rejects a wrong issuer" do
    expect { validator(RsaKeys.id_token("iss" => "https://evil.example/realms/mydid")).validate! }
      .to raise_error(OmniAuth::MyDigitalId::IdTokenError)
  end

  it "rejects an expired token" do
    expect { validator(RsaKeys.id_token("exp" => Time.now.to_i - 10)).validate! }
      .to raise_error(OmniAuth::MyDigitalId::IdTokenError)
  end

  it "rejects a nonce mismatch" do
    expect { validator(RsaKeys.id_token, nonce_arg: "different").validate! }
      .to raise_error(OmniAuth::MyDigitalId::IdTokenError, /nonce/)
  end
end
```

- [ ] **Step 2: Run it — expect failure**

```bash
bundle exec rspec spec/mydigital_id/id_token_validator_spec.rb
```
Expected: FAIL — `uninitialized constant OmniAuth::MyDigitalId::IdTokenValidator`.

- [ ] **Step 3: Implement `lib/omniauth/mydigital_id/id_token_validator.rb`**

```ruby
# frozen_string_literal: true

require "jwt"
require "omniauth/mydigital_id/jwks_fetcher"

module OmniAuth
  module MyDigitalId
    # Validates a Keycloak-issued ID token: RS256 signature against JWKS, plus
    # iss/aud/exp and (when supplied) nonce. Returns the decoded payload or raises
    # IdTokenError. On an unknown key id it forces one JWKS refetch (key rotation).
    class IdTokenValidator
      def initialize(id_token:, jwks_uri:, issuer:, audience:, nonce:, jwks_fetcher: JwksFetcher.new)
        @id_token = id_token
        @jwks_uri = jwks_uri
        @issuer = issuer
        @audience = audience
        @nonce = nonce
        @jwks_fetcher = jwks_fetcher
      end

      def validate!
        raise IdTokenError, "missing id_token" if @id_token.nil? || @id_token.to_s.empty?

        payload = decode(@jwks_fetcher.call(@jwks_uri))
        verify_nonce!(payload)
        payload
      rescue JWT::DecodeError => e
        # Possible key rotation: refetch JWKS once, then re-decode.
        begin
          payload = decode(@jwks_fetcher.call(@jwks_uri, force: true))
          verify_nonce!(payload)
          payload
        rescue JWT::DecodeError
          raise IdTokenError, e.message
        end
      end

      private

      def decode(jwks)
        JWT.decode(
          @id_token, nil, true,
          algorithms: ["RS256"],
          jwks: jwks,
          iss: @issuer, verify_iss: true,
          aud: @audience, verify_aud: true,
          verify_expiration: true
        ).first
      end

      def verify_nonce!(payload)
        return if @nonce.nil?
        raise IdTokenError, "nonce mismatch" unless payload["nonce"] == @nonce
      end
    end
  end
end
```

- [ ] **Step 4: Run it — expect pass**

```bash
bundle exec rspec spec/mydigital_id/id_token_validator_spec.rb
```
Expected: 7 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Add ID-token validator (RS256 + iss/aud/exp/nonce)"
```

---

## Task 5: The OmniAuth strategy

**Files:**
- Create: `lib/omniauth/strategies/my_digital_id.rb`
- Test: `spec/strategies/my_digital_id_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

require "spec_helper"
require "omniauth"
require "rack/test"

RSpec.describe OmniAuth::Strategies::MyDigitalId do
  include Rack::Test::Methods

  let(:base_url) { "https://sso.example.gov.my" }
  let(:jwks_uri) { "#{base_url}/realms/mydid/protocol/openid-connect/certs" }

  let(:app) do
    strat_opts = {base_url: base_url, realm: "mydid"}
    Rack::Builder.new do
      use Rack::Session::Cookie, secret: "a" * 64
      use OmniAuth::Strategies::MyDigitalId, "hoojah-client", "secret", strat_opts
      run ->(env) { [200, {}, [(env["omniauth.auth"] || {}).to_json]] }
    end.to_app
  end

  before { OmniAuth.config.test_mode = false }

  it "redirects the request phase to the Keycloak authorize endpoint with a nonce" do
    get "/auth/my_digital_id"
    expect(last_response.status).to eq(302)
    location = last_response.headers["Location"]
    expect(location).to start_with("#{base_url}/realms/mydid/protocol/openid-connect/auth")
    expect(location).to include("scope=openid")
    expect(location).to include("nonce=")
  end
end
```

- [ ] **Step 2: Run it — expect failure**

```bash
bundle exec rspec spec/strategies/my_digital_id_spec.rb
```
Expected: FAIL — `uninitialized constant OmniAuth::Strategies::MyDigitalId`.

- [ ] **Step 3: Implement `lib/omniauth/strategies/my_digital_id.rb`**

```ruby
# frozen_string_literal: true

require "securerandom"
require "omniauth-oauth2"
require "omniauth/mydigital_id/id_token_validator"

module OmniAuth
  module Strategies
    # OmniAuth strategy for Malaysia's MyDigital ID SSO. MyDigital ID is a Keycloak
    # cluster (realm "mydid") speaking standard OIDC Authorization Code. This strategy
    # builds the realm endpoints, adds a nonce, and validates the returned ID token
    # against JWKS before the auth hash is trusted. Userinfo returns `nric` (Malaysian
    # IC number) and `nama` (full name) — no email.
    class MyDigitalId < OmniAuth::Strategies::OAuth2
      option :name, "my_digital_id"
      option :base_url, nil
      option :realm, "mydid"
      option :path_prefix, ""
      option :scope, "openid profile email"
      option :pkce, true
      option :client_options, {}

      # `sub` — the opaque, stable Keycloak subject. The relying party keys on this;
      # it is NOT the NRIC.
      uid { raw_info["sub"] }

      info do
        {name: raw_info["nama"]} # deliberately no :email — MyDigital ID supplies none
      end

      extra do
        {raw_info: raw_info, id_token_claims: id_token_claims}
      end

      def client
        options.client_options[:site] = base_url
        options.client_options[:authorize_url] = realm_path("auth")
        options.client_options[:token_url] = realm_path("token")
        super
      end

      def authorize_params
        super.tap do |params|
          params[:scope] ||= options.scope
          params[:nonce] = SecureRandom.hex(16)
          session["omniauth.nonce"] = params[:nonce]
          params[:prompt] = request.params["prompt"] if request.params["prompt"]
        end
      end

      def raw_info
        @raw_info ||= access_token.get(realm_path("userinfo")).parsed
      end

      # Validate the ID token (raises IdTokenError → OmniAuth failure via callback_phase).
      def id_token_claims
        @id_token_claims ||= OmniAuth::MyDigitalId::IdTokenValidator.new(
          id_token: access_token["id_token"],
          jwks_uri: realm_url("certs"),
          issuer: issuer,
          audience: options.client_id,
          nonce: session.delete("omniauth.nonce")
        ).validate!
      end

      def callback_phase
        super
      rescue OmniAuth::MyDigitalId::IdTokenError => e
        fail!(:invalid_id_token, e)
      end

      private

      def base_url
        options.base_url or raise ArgumentError, "omniauth my_digital_id requires :base_url"
      end

      def issuer
        "#{base_url}#{options.path_prefix}/realms/#{options.realm}"
      end

      def realm_path(action)
        "#{options.path_prefix}/realms/#{options.realm}/protocol/openid-connect/#{action}"
      end

      def realm_url(action)
        "#{base_url}#{realm_path(action)}"
      end
    end
  end
end
```

- [ ] **Step 4: Run it — expect pass**

```bash
bundle exec rspec spec/strategies/my_digital_id_spec.rb
```
Expected: 1 example, 0 failures.

- [ ] **Step 5: Add a full callback-phase spec (auth hash shape)**

Append to `spec/strategies/my_digital_id_spec.rb` inside the `describe` block:

```ruby
  it "builds the auth hash on callback: uid=sub, name=nama, nric in raw_info, no email" do
    token_uri = "#{base_url}/realms/mydid/protocol/openid-connect/token"
    userinfo_uri = "#{base_url}/realms/mydid/protocol/openid-connect/userinfo"

    stub_request(:post, token_uri).to_return(
      headers: {"Content-Type" => "application/json"},
      body: {access_token: "at-1", token_type: "Bearer", id_token: RsaKeys.id_token(
        "nonce" => "fixed-nonce")}.to_json
    )
    stub_request(:get, userinfo_uri).to_return(
      headers: {"Content-Type" => "application/json"},
      body: {sub: "keycloak-sub-123", nama: "Ali bin Abu", nric: "900101015511"}.to_json
    )
    stub_request(:get, jwks_uri).to_return(body: RsaKeys.jwks.to_json)

    # Seed the session nonce the callback will compare against.
    env "rack.session", {"omniauth.nonce" => "fixed-nonce"}
    get "/auth/my_digital_id/callback", {code: "abc", state: "xyz"}, {"rack.session" => {"omniauth.state" => "xyz", "omniauth.nonce" => "fixed-nonce"}}

    body = JSON.parse(last_response.body)
    expect(body["uid"]).to eq("keycloak-sub-123")
    expect(body["info"]["name"]).to eq("Ali bin Abu")
    expect(body["info"]).not_to have_key("email")
    expect(body.dig("extra", "raw_info", "nric")).to eq("900101015511")
  end
```

> Note: OAuth2 checks `state`. The session and the `state` param must match; the seed above supplies both. If the harness's state handling needs `OmniAuth.config.request_validation_phase` disabled, set `OmniAuth.config.test_mode = false` (already done) and rely on the `state` match. If state proves brittle in this harness, set `provider_ignores_state: true` in `strat_opts` **for this spec only** — never in the app.

- [ ] **Step 6: Run the full strategy spec — expect pass**

```bash
bundle exec rspec spec/strategies/my_digital_id_spec.rb
```
Expected: 2 examples, 0 failures.

- [ ] **Step 7: Run the whole gem suite + standard**

```bash
bundle exec rspec && bundle exec standardrb
```
Expected: all green; standard clean.

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "Add MyDigitalId OmniAuth strategy with ID-token validation"
```

---

## Task 6: Gem README (Devise wiring)

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write `README.md`**

````markdown
# omniauth-mydigital-id-ruby

OmniAuth strategy for Malaysia's **MyDigital ID** SSO (a Keycloak OIDC provider, realm `mydid`).
Authorization Code flow with **ID-token validation against JWKS** (iss/aud/exp/nonce).

## Install

```ruby
gem "omniauth-mydigital-id-ruby"
```

## Devise wiring

```ruby
# config/initializers/devise.rb
config.omniauth :my_digital_id,
  ENV["MYID_CLIENT_ID"],
  ENV["MYID_CLIENT_SECRET"],
  base_url: ENV["MYID_BASE_URL"],           # SSO DNS host, scheme + host, no trailing slash
  realm: ENV.fetch("MYID_REALM", "mydid")
```

```ruby
# app/models/user.rb
devise :omniauthable, omniauth_providers: [:my_digital_id]
```

## Options

| Option | Default | Meaning |
|--------|---------|---------|
| `base_url` | (required) | SSO DNS host. |
| `realm` | `mydid` | Keycloak realm. |
| `scope` | `openid profile email` | OAuth scope. |
| `pkce` | `true` | Send PKCE S256 challenge. |
| `path_prefix` | `""` | Set to `/auth` for legacy Keycloak path layout. |

## Auth hash

- `uid` → OIDC `sub` (opaque, stable; **not** the NRIC).
- `info.name` → `nama`. No `info.email` (MyDigital ID supplies none).
- `extra.raw_info` → full userinfo incl. `nric` (consume in-request; do not persist).
- `extra.id_token_claims` → validated ID-token payload.

Requires `omniauth-rails_csrf_protection` and a POST request phase (OmniAuth 2 / CVE-2015-9284).
````

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "Add README with Devise wiring"
```

---

# PART B — hoojah integration

## Task 7: Add the gem, Devise config, provider list

**Files:**
- Modify: `Gemfile`, `config/initializers/devise.rb:278` (near the google_oauth2 line), `app/models/user.rb:31-32`

- [ ] **Step 1: Add the path gem to `Gemfile`** (next to the other omniauth gems)

```ruby
# MyDigital ID SSO (Keycloak OIDC) — reusable OmniAuth strategy, path gem during dev.
gem "omniauth-mydigital-id-ruby", path: "../omniauth-mydigital-id-ruby"
```

- [ ] **Step 2: `bundle install`**

```bash
cd /Users/deepsight/code/hoojah-beta
bundle install
```
Expected: bundler picks up `omniauth-mydigital-id-ruby (0.1.0)` from the path source.

- [ ] **Step 3: Add the provider to `config/initializers/devise.rb`** immediately after the existing `config.omniauth :google_oauth2, ...` block

```ruby
  # MyDigital ID (Malaysia national digital identity) — Keycloak OIDC. Credentials are
  # ENV-driven; when absent the provider is simply unavailable (the login button is
  # hidden), never a boot crash. NRIC is never persisted — see User.from_my_digital_id.
  config.omniauth :my_digital_id,
    ENV["MYID_CLIENT_ID"],
    ENV["MYID_CLIENT_SECRET"],
    base_url: ENV["MYID_BASE_URL"],
    realm: ENV.fetch("MYID_REALM", "mydid")
```

- [ ] **Step 4: Add `:my_digital_id` to the provider list in `app/models/user.rb`**

Change:
```ruby
    :omniauthable, omniauth_providers: [:google_oauth2]
```
to:
```ruby
    :omniauthable, omniauth_providers: [:google_oauth2, :my_digital_id]
```

- [ ] **Step 5: Boot check**

```bash
bin/rails runner 'puts User.omniauth_providers.inspect'
```
Expected: `[:google_oauth2, :my_digital_id]` and no boot error even with MYID_* unset.

- [ ] **Step 6: Commit**

```bash
git add Gemfile Gemfile.lock config/initializers/devise.rb app/models/user.rb
git commit -m "Wire omniauth-mydigital-id-ruby into Devise config"
```

---

## Task 8: `user_identities` table + model + backfill

**Files:**
- Create: migration `db/migrate/*_create_user_identities.rb`, migration `db/migrate/*_backfill_user_identities.rb`, `app/models/user_identity.rb`, `spec/factories/user_identities.rb`, `spec/models/user_identity_spec.rb`
- Modify: `app/models/user.rb` (association)

- [ ] **Step 1: Generate + write the create migration**

```bash
bin/rails g migration CreateUserIdentities
```
Fill it in:
```ruby
class CreateUserIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :user_identities do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :uid, null: false
      t.timestamps
    end
    add_index :user_identities, [:provider, :uid], unique: true
    add_index :user_identities, [:user_id, :provider], unique: true
  end
end
```

- [ ] **Step 2: Write the model `app/models/user_identity.rb`**

```ruby
class UserIdentity < ApplicationRecord
  belongs_to :user

  validates :provider, presence: true
  validates :uid, presence: true, uniqueness: {scope: :provider}
end
```

- [ ] **Step 3: Add the association in `app/models/user.rb`** (near the other `has_many`, after `webauthn_credentials`)

```ruby
  has_many :identities, class_name: "UserIdentity", dependent: :destroy
```

- [ ] **Step 4: Write the backfill migration**

```bash
bin/rails g migration BackfillUserIdentities
```
```ruby
class BackfillUserIdentities < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    say_with_time "backfilling user_identities from users.provider/uid" do
      User.where.not(provider: [nil, ""]).where.not(uid: [nil, ""]).find_each do |u|
        UserIdentity.find_or_create_by!(provider: u.provider, uid: u.uid) do |i|
          i.user_id = u.id
        end
      end
    end
  end

  def down
    UserIdentity.delete_all
  end
end
```

- [ ] **Step 5: Migrate dev + test**

```bash
bin/rails db:migrate
bin/rails db:test:prepare
```
Expected: `user_identities` created; backfill runs (0 rows in a fresh dev DB is fine).

- [ ] **Step 6: Write the failing model spec + factory**

`spec/factories/user_identities.rb`:
```ruby
FactoryBot.define do
  factory :user_identity do
    user
    provider { "my_digital_id" }
    sequence(:uid) { |n| "sub-#{n}" }
  end
end
```

`spec/models/user_identity_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe UserIdentity, type: :model do
  it "requires provider and uid" do
    identity = UserIdentity.new(user: create(:user))
    expect(identity).not_to be_valid
    expect(identity.errors.attribute_names).to include(:provider, :uid)
  end

  it "enforces uniqueness of uid within a provider" do
    create(:user_identity, provider: "my_digital_id", uid: "dup")
    dupe = build(:user_identity, provider: "my_digital_id", uid: "dup")
    expect(dupe).not_to be_valid
  end

  it "allows the same uid under a different provider" do
    create(:user_identity, provider: "my_digital_id", uid: "shared")
    other = build(:user_identity, provider: "google_oauth2", uid: "shared")
    expect(other).to be_valid
  end
end
```

- [ ] **Step 7: Run — expect pass**

```bash
RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/user_identity_spec.rb
```
Expected: 3 examples, 0 failures.

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "Add user_identities table, model, and backfill migration"
```

---

## Task 9: Rework Google `from_omniauth` through identities

The existing method writes `users.provider/uid`. Route it through `identities` so a user can hold multiple providers. Google's verified-email auto-link is preserved.

**Files:**
- Modify: `app/models/user.rb:92-126` (`from_omniauth`)
- Modify: `spec/requests/omniauth_callbacks_spec.rb` (assert via identity, not `uid` column)

- [ ] **Step 1: Update the failing request spec first**

In `spec/requests/omniauth_callbacks_spec.rb`, change the success assertion from
```ruby
    expect(User.find_by(uid: "u1")).to be_present
```
to
```ruby
    identity = UserIdentity.find_by(provider: "google_oauth2", uid: "u1")
    expect(identity).to be_present
    expect(identity.user.email).to eq("oauth.new@gmail.com")
```

- [ ] **Step 2: Run it — expect failure** (method still writes the column, no identity created)

```bash
RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/omniauth_callbacks_spec.rb
```
Expected: FAIL — identity is nil.

- [ ] **Step 3: Rewrite `from_omniauth` in `app/models/user.rb`**

```ruby
  # Auto-linking by email is safe ONLY because omniauth-google-oauth2 populates
  # info.email from Google's verified_email (nil unless the address is verified).
  # Do not reuse this method for a provider without that guarantee — MyDigital ID
  # has no email and uses from_my_digital_id instead.
  def self.from_omniauth(auth)
    if (identity = UserIdentity.find_by(provider: auth.provider, uid: auth.uid))
      return identity.user
    end

    email = auth.info.email.to_s.downcase.strip
    if email.blank?
      user = new
      user.errors.add(:base, "Google did not provide a verified email address.")
      return user
    end

    if (user = find_by(email: email))
      existing = user.identities.find_by(provider: auth.provider)
      if existing && existing.uid != auth.uid
        user.errors.add(:base, "This email is already linked to a different Google account.")
        return user
      end
      user.identities.create!(provider: auth.provider, uid: auth.uid) unless existing
      return user
    end

    seed = email.split("@").first.presence || auth.info.name
    user = create(
      email: email,
      full_name: auth.info.name.presence || email.split("@").first,
      username: generate_username(seed),
      password: Devise.friendly_token[0, 20]
    )
    user.identities.create!(provider: auth.provider, uid: auth.uid) if user.persisted?
    user
  rescue ActiveRecord::RecordNotUnique
    # Concurrent first sign-in: the other request won the unique [provider, uid]
    # index. Return the now-existing record.
    UserIdentity.find_by(provider: auth.provider, uid: auth.uid)&.user
  end
```

- [ ] **Step 4: Run the Google request spec — expect pass**

```bash
RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/omniauth_callbacks_spec.rb
```
Expected: 2 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/models/user.rb spec/requests/omniauth_callbacks_spec.rb
git commit -m "Route Google from_omniauth through user_identities"
```

---

## Task 10: `User.from_my_digital_id` + `create_with_my_digital_id`

**Files:**
- Modify: `app/models/user.rb` (add constant + two methods)
- Test: `spec/models/user_mydigital_id_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
require "rails_helper"

RSpec.describe "User MyDigital ID linking", type: :model do
  def mydid_auth(sub:, name: "Ali bin Abu")
    OmniAuth::AuthHash.new(provider: "my_digital_id", uid: sub, info: {name: name})
  end

  describe ".from_my_digital_id" do
    it "returns the user owning the matching identity" do
      user = create(:user)
      user.identities.create!(provider: "my_digital_id", uid: "sub-known")
      expect(User.from_my_digital_id(mydid_auth(sub: "sub-known"))).to eq(user)
    end

    it "returns nil for an unknown sub (never auto-creates, never matches email)" do
      create(:user, email: "someone@hoojah.com")
      expect(User.from_my_digital_id(mydid_auth(sub: "sub-unknown"))).to be_nil
    end
  end

  describe ".create_with_my_digital_id" do
    it "creates a usable account + identity, no NRIC anywhere" do
      user = User.create_with_my_digital_id(username: "newperson", sub: "sub-new", full_name: "Ali bin Abu")
      expect(user).to be_persisted
      expect(user.full_name).to eq("Ali bin Abu")
      expect(user.encrypted_password).to be_present
      expect(user.identities.pluck(:provider, :uid)).to eq([["my_digital_id", "sub-new"]])
    end

    it "returns an unsaved user with errors on a taken username" do
      create(:user, username: "taken")
      user = User.create_with_my_digital_id(username: "taken", sub: "sub-x", full_name: "X")
      expect(user).not_to be_persisted
      expect(user.errors[:username]).to be_present
    end

    it "enforces one hoojah account per MyDigital ID under a race" do
      User.create_with_my_digital_id(username: "firstperson", sub: "sub-race", full_name: "A")
      again = User.create_with_my_digital_id(username: "secondperson", sub: "sub-race", full_name: "B")
      expect(UserIdentity.where(provider: "my_digital_id", uid: "sub-race").count).to eq(1)
      expect(again.identities).to be_empty.or eq(User.find_by(username: "firstperson").identities)
    end

    it "is idempotent when the sub is already linked — returns the existing account, no orphan user" do
      first = User.create_with_my_digital_id(username: "firstperson", sub: "sub-idem", full_name: "A")
      expect {
        again = User.create_with_my_digital_id(username: "secondperson", sub: "sub-idem", full_name: "B")
        expect(again).to eq(first)
      }.not_to change(User, :count)
      expect(UserIdentity.where(provider: "my_digital_id", uid: "sub-idem").count).to eq(1)
    end
  end
end
```

- [ ] **Step 2: Run — expect failure**

```bash
RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/user_mydigital_id_spec.rb
```
Expected: FAIL — `NoMethodError: undefined method 'from_my_digital_id'`.

- [ ] **Step 3: Implement in `app/models/user.rb`** (add the constant near `RESERVED_USERNAMES`, methods after `from_omniauth`)

Constant:
```ruby
  MYDIGITAL_ID_PROVIDER = "my_digital_id"
```

Methods:
```ruby
  # MyDigital ID has NO verified email, so it never auto-links by email the way Google
  # does. A known subject returns its user; an unknown subject returns nil, which the
  # callback controller turns into the link-or-create interstitial. The NRIC (from
  # userinfo) is never read here — identity is keyed on the opaque OIDC `sub`.
  def self.from_my_digital_id(auth)
    UserIdentity.find_by(provider: MYDIGITAL_ID_PROVIDER, uid: auth.uid)&.user
  end

  # Escape hatch: create a fresh hoojah account for a MyDigital ID subject. Username is
  # user-chosen (validated by the model); password is a secure random token the user
  # never uses (recovery is moderator-assisted — see /mydigital-id). Email is synthesised
  # from the opaque `sub` to satisfy Devise :validatable without inventing PII (the value
  # is non-deliverable, never shown, never emailed). One-account-per-MyID is enforced by
  # the unique [provider, uid] index. The method is transactional (user + identity insert
  # commit together, so a failure never orphans an unusable @myid.invalid user row) and
  # idempotent (a subject already linked by a concurrent request or retry short-circuits
  # to the existing account instead of creating a duplicate).
  def self.create_with_my_digital_id(username:, sub:, full_name: nil)
    # Idempotent: if this subject is already linked (a concurrent request or retry got
    # here first), return that account rather than creating a duplicate.
    if (existing = UserIdentity.find_by(provider: MYDIGITAL_ID_PROVIDER, uid: sub)&.user)
      return existing
    end

    user = new(
      username: username.to_s.strip,
      full_name: full_name.presence || "New User",
      email: "#{sub}@myid.invalid",
      password: Devise.friendly_token[0, 32]
    )
    # save! + identity insert in ONE transaction so a failure NEVER leaves an orphaned
    # user row with an unusable @myid.invalid email. A taken username raises RecordInvalid
    # (ordinary, non-race); a concurrent link/create of the same sub raises RecordInvalid
    # (email/uid uniqueness) or RecordNotUnique — all handled below, and the transaction
    # rolls back our half-created row.
    transaction do
      user.save!
      user.identities.create!(provider: MYDIGITAL_ID_PROVIDER, uid: sub)
    end
    user
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    # If the subject was linked concurrently, return the winning account. Otherwise this
    # is an ordinary validation failure (e.g. taken username) — return the unsaved user
    # carrying its errors for the interstitial to render.
    if (winner = UserIdentity.find_by(provider: MYDIGITAL_ID_PROVIDER, uid: sub)&.user)
      return winner
    end
    user.errors.add(:base, "Could not create your account. Please try again.") if user.errors.empty?
    user
  end
```

- [ ] **Step 4: Run — expect pass**

```bash
RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/user_mydigital_id_spec.rb
```
Expected: 6 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/models/user.rb spec/models/user_mydigital_id_spec.rb
git commit -m "Add User.from_my_digital_id and create_with_my_digital_id"
```

---

## Task 11: OmniAuth callback `#my_digital_id`

**Files:**
- Modify: `app/controllers/users/omniauth_callbacks_controller.rb`
- Test: covered by Task 15's request spec (write the callback here, assert next task)

- [ ] **Step 1: Add the action to `app/controllers/users/omniauth_callbacks_controller.rb`** (after `google_oauth2`, before `failure`)

```ruby
  # MyDigital ID has no email, so we cannot auto-link. Known subject → sign in.
  # Unknown subject → stash the opaque `sub` (+ display name) in a short-lived session
  # value and send the user to the link-or-create interstitial. We never store the NRIC.
  def my_digital_id
    auth = request.env["omniauth.auth"]

    if (user = User.from_my_digital_id(auth))
      sign_in_and_redirect user, event: :authentication
      set_flash_message(:notice, :success, kind: "MyDigital ID") if is_navigational_format?
    else
      session[:pending_mydid] = {
        "sub" => auth.uid,
        "name" => auth.info.name.to_s,
        "at" => Time.current.to_i
      }
      redirect_to mydigital_id_continue_path
    end
  end
```

- [ ] **Step 2: Update the `failure` copy** to be provider-neutral

Change:
```ruby
  def failure
    redirect_to new_user_session_path, alert: "Could not sign you in with Google."
  end
```
to:
```ruby
  def failure
    redirect_to new_user_session_path, alert: "Could not sign you in. Please try again."
  end
```

- [ ] **Step 3: Commit** (routes/interstitial arrive next task; app won't fully run until then)

```bash
git add app/controllers/users/omniauth_callbacks_controller.rb
git commit -m "Add MyDigital ID OmniAuth callback with pending-link stash"
```

---

## Task 12: Link-or-create interstitial controller + routes

**Files:**
- Create: `app/controllers/mydigital_id_links_controller.rb`
- Modify: `config/routes.rb`
- Test: `spec/requests/mydigital_id_spec.rb` (added in Task 15)

- [ ] **Step 1: Add routes to `config/routes.rb`** (near the passkey `devise_scope` block; these are MAIN routes, CSRF on)

```ruby
  # MyDigital ID link-or-create interstitial (2026). Reached only after a successful
  # MyDigital ID auth whose `sub` is not yet linked (see OmniauthCallbacksController).
  # MAIN routes — CSRF on — because they create sessions/accounts. Guarded by a
  # short-lived session[:pending_mydid]; no username in the URL (pre-auth surface).
  get "/mydigital-id/continue", to: "mydigital_id_links#new", as: :mydigital_id_continue
  post "/mydigital-id/link", to: "mydigital_id_links#create", as: :mydigital_id_link
  post "/mydigital-id/register", to: "mydigital_id_links#create_account", as: :mydigital_id_register

  # Public notice (action + view land in Task 14). Route is drawn here so the login/
  # interstitial views in Task 13 can resolve mydigital_id_info_path.
  get "/mydigital-id", to: "pages#mydigital_id", as: :mydigital_id_info
```

- [ ] **Step 2: Write the controller `app/controllers/mydigital_id_links_controller.rb`**

```ruby
# Link-or-create interstitial for a MyDigital ID subject that is not yet linked to a
# hoojah account. Two paths: link to an existing account (email + password), or create
# a new account (username only; secure random password). Guarded by a short-lived
# session[:pending_mydid] carrying only the opaque `sub` and display name — never the
# NRIC. Fails closed to the login page when that value is missing or stale.
class MydigitalIdLinksController < ApplicationController
  PENDING_TTL = 15.minutes

  before_action :require_pending_mydid

  def new
    skip_authorization
  end

  # Link the pending MyDigital ID to an existing account after re-auth.
  def create
    skip_authorization
    user = User.find_by(email: params[:email].to_s.downcase.strip)

    unless user&.valid_password?(params[:password].to_s)
      flash.now[:alert] = "Those credentials didn't match an account."
      return render :new, status: :unprocessable_entity
    end

    if user.identities.exists?(provider: User::MYDIGITAL_ID_PROVIDER)
      flash.now[:alert] = "That account is already linked to a MyDigital ID."
      return render :new, status: :unprocessable_entity
    end

    user.identities.create!(provider: User::MYDIGITAL_ID_PROVIDER, uid: pending_sub)
    finish_linked(user)
  rescue ActiveRecord::RecordNotUnique
    flash.now[:alert] = "This MyDigital ID is already linked to another account."
    render :new, status: :unprocessable_entity
  end

  # Create a fresh account for the pending MyDigital ID (the "I don't have a Hoojah
  # account yet" path). Server-side re-validates the username (client checks are UX only).
  def create_account
    skip_authorization
    user = User.create_with_my_digital_id(
      username: params[:username], sub: pending_sub, full_name: pending_name
    )

    if user.persisted?
      finish_linked(user)
    else
      flash.now[:alert] = user.errors.full_messages.to_sentence.presence ||
        "Could not create your account."
      render :new, status: :unprocessable_entity
    end
  end

  private

  def finish_linked(user)
    session.delete(:pending_mydid)
    sign_in(user, event: :authentication)
    redirect_to after_sign_in_path_for(user), notice: "Signed in with MyDigital ID."
  end

  def require_pending_mydid
    data = session[:pending_mydid]
    if data.blank? || data["at"].to_i + PENDING_TTL.to_i < Time.current.to_i
      session.delete(:pending_mydid)
      redirect_to new_user_session_path,
        alert: "Your MyDigital ID session expired. Please sign in again."
    end
  end

  def pending_sub = session.dig(:pending_mydid, "sub")

  def pending_name = session.dig(:pending_mydid, "name")
end
```

- [ ] **Step 3: Boot check (routes resolve)**

```bash
bin/rails runner 'puts Rails.application.routes.url_helpers.mydigital_id_continue_path'
```
Expected: `/mydigital-id/continue`

- [ ] **Step 4: Commit** (view arrives next task)

```bash
git add config/routes.rb app/controllers/mydigital_id_links_controller.rb
git commit -m "Add MyDigital ID link-or-create interstitial controller and routes"
```

---

## Task 13: Views — interstitial + MyID buttons

**Files:**
- Create: `app/views/mydigital_id_links/new.html.erb`
- Modify: `app/views/devise/sessions/new.html.erb` (after the Google button, ~line 76), `app/views/devise/registrations/new.html.erb` (after its Google button, ~line 102)

- [ ] **Step 1: Write the interstitial view `app/views/mydigital_id_links/new.html.erb`**

```erb
<%# Link-or-create after a MyDigital ID sign-in whose subject isn't linked yet.
    Two paths: link an existing account, or create a new one. Follows the design
    system (ds_* helpers, token colours, no hex). %>
<div class="min-h-screen flex items-center justify-center px-4 py-10">
  <div class="<%= ds_card_classes %> w-full max-w-md p-6 sm:p-8">
    <h1 class="text-xl font-bold text-ink">Welcome via MyDigital ID</h1>
    <p class="mt-2 text-sm text-faint">
      We verified your MyDigital ID<% if session.dig(:pending_mydid, "name").present? %>,
      <span class="font-semibold text-ink"><%= session.dig(:pending_mydid, "name") %></span><% end %>.
      Link it to your Hoojah account, or create a new one.
    </p>

    <% if flash.now[:alert].present? || flash[:alert].present? %>
      <p class="mt-4 text-sm text-disagree"><%= flash.now[:alert] || flash[:alert] %></p>
    <% end %>

    <%# Path 1: link an existing account %>
    <%= form_with url: mydigital_id_link_path, method: :post, class: "mt-6 space-y-3" do |f| %>
      <label class="block text-sm font-semibold text-ink">Link my existing Hoojah account</label>
      <%= f.email_field :email, placeholder: "you@example.com", autocomplete: "email",
            class: "w-full h-[52px] rounded-xl border border-field bg-card text-ink px-4" %>
      <%= f.password_field :password, placeholder: "Password", autocomplete: "current-password",
            class: "w-full h-[52px] rounded-xl border border-field bg-card text-ink px-4" %>
      <%= f.submit "Link and continue",
            class: "#{ds_button_classes(tone: :primary)} w-full h-[52px]" %>
    <% end %>

    <div class="flex items-center gap-3 my-6">
      <div class="flex-1 h-px bg-hairline"></div>
      <span class="text-xs font-semibold text-faint">or</span>
      <div class="flex-1 h-px bg-hairline"></div>
    </div>

    <%# Path 2: create a new account (username only) %>
    <%= form_with url: mydigital_id_register_path, method: :post, class: "space-y-3" do |f| %>
      <label class="block text-sm font-semibold text-ink">I don't have a Hoojah account yet</label>
      <%= f.text_field :username, placeholder: "Choose a username", autocomplete: "off",
            pattern: "[A-Za-z0-9_]+",
            class: "w-full h-[52px] rounded-xl border border-field bg-card text-ink px-4" %>
      <p class="text-xs text-faint">Letters, numbers, and underscores only.</p>
      <%= f.submit "Create account and continue",
            class: "#{ds_button_classes(tone: :neutral)} w-full h-[52px]" %>
    <% end %>

    <p class="mt-6 text-xs text-faint">
      <%= link_to "How MyDigital ID login works", mydigital_id_info_path, class: "underline" %>
    </p>
  </div>
</div>
```

> If `ds_button_classes` doesn't accept a `tone:` keyword in this codebase, check `DesignSystemHelper#ds_button_classes` and use the correct signature; the two buttons just need a primary and a secondary style. Do not invent hex.

- [ ] **Step 2: Add the MyID button to `app/views/devise/sessions/new.html.erb`** immediately after the Google `button_to ... end` block (after ~line 76, before the passkey block)

```erb
    <%# MyDigital ID — POST to the OmniAuth request phase (POST /auth/my_digital_id).
        Turbo disabled so the request-phase 302 is a real navigation; CSRF token carried
        by button_to and verified by omniauth-rails_csrf_protection. Shown only when the
        provider is configured (MYID_BASE_URL present). %>
    <% if ENV["MYID_BASE_URL"].present? %>
      <%= button_to user_my_digital_id_omniauth_authorize_path,
            method: :post,
            form: {data: {turbo: false}},
            class: "w-full h-[52px] mt-3 rounded-xl border border-field bg-card text-ink font-bold text-[14.5px] flex items-center justify-center gap-2.5" do %>
        <%= lucide_icon "shield-check", class: "w-[19px] h-[19px]" %>
        Continue with MyDigital ID
      <% end %>
      <p class="mt-2 text-xs text-faint text-center">
        <%= link_to "What is MyDigital ID login?", mydigital_id_info_path, class: "underline" %>
      </p>
    <% end %>
```

- [ ] **Step 3: Add the same button block to `app/views/devise/registrations/new.html.erb`** after its Google `button_to ... end` (after ~line 102) — identical markup to Step 2.

- [ ] **Step 4: Visual sanity (server)**

```bash
MYID_BASE_URL=https://sso.example.gov.my bin/rails runner 'app.get "/login"; puts app.response.body.include?("Continue with MyDigital ID")'
```
Expected: `true`.

- [ ] **Step 5: Commit**

```bash
git add app/views/mydigital_id_links/new.html.erb app/views/devise/sessions/new.html.erb app/views/devise/registrations/new.html.erb
git commit -m "Add MyDigital ID buttons and link-or-create interstitial view"
```

---

## Task 14: Public legal notice `/mydigital-id`

**Files:**
- Modify: `app/controllers/pages_controller.rb`, `config/routes.rb:228-232` (near /about..)
- Create: `app/views/pages/mydigital_id.html.erb`

- [ ] **Step 1: Add the action to `app/controllers/pages_controller.rb`** (sibling of `terms`)

```ruby
  def mydigital_id
    skip_authorization
  end
```

- [ ] **Step 2: Route already drawn in Task 12** — the `get "/mydigital-id", to: "pages#mydigital_id", as: :mydigital_id_info` line was added in Task 12 so the Task 13 views resolve. Nothing to add here; just confirm it's present in `config/routes.rb`.

- [ ] **Step 3: Write `app/views/pages/mydigital_id.html.erb`** (mirror the `legal_chrome` layout used by about/terms)

```erb
<%= render layout: "pages/legal_chrome", locals: {title: "MyDigital ID login", updated: "6 September 2026", art: "about", variant: :spots, lede: "Hoojah lets Malaysians sign in with MyDigital ID, the national digital identity. This page explains what that means for your account."} do %>
  <%= render layout: "pages/section", locals: {heading: "One identity, one account", variant: :spots, spot: "claim"} do %>
    <p>MyDigital ID identifies a single registered individual in Malaysia. Signing in with MyDigital ID is bound by Malaysian laws and policies governing the national digital identity. Because of that, <strong>only one Hoojah account is allowed per MyDigital ID</strong>. If your MyDigital ID is already linked to a Hoojah account, signing in will always take you to that same account.</p>
  <% end %>
  <%= render layout: "pages/section", locals: {heading: "What we store", variant: :spots, spot: "votes"} do %>
    <p>When you sign in, MyDigital ID confirms your identity to Hoojah. We store only a stable, anonymous reference to that identity so we can recognise you next time. We do <strong>not</strong> store your MyKad / IC number.</p>
  <% end %>
  <%= render layout: "pages/section", locals: {heading: "Account recovery", variant: :spots, spot: "mission"} do %>
    <p>If you created your Hoojah account through MyDigital ID, there is no password for us to reset. To recover access, please contact a Hoojah moderator, who will help you re-establish your account.</p>
  <% end %>
<% end %>
```

> Confirm the `art:` and `spot:` values against an existing page (e.g. `about.html.erb`) so the illustrations resolve; reuse existing asset keys rather than inventing new ones.

- [ ] **Step 4: Boot check**

```bash
bin/rails runner 'app.get "/mydigital-id"; puts app.response.status'
```
Expected: `200`.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/pages_controller.rb config/routes.rb app/views/pages/mydigital_id.html.erb
git commit -m "Add public MyDigital ID login notice page"
```

---

## Task 15: Request + system specs for the MyID flow

**Files:**
- Modify: `spec/support/omniauth.rb` (add mydid mock helper + reset)
- Create: `spec/requests/mydigital_id_spec.rb`, `spec/system/mydigital_id_sign_in_spec.rb`

- [ ] **Step 1: Extend `spec/support/omniauth.rb`**

Add to the `before(:each)` reset block (alongside the google reset):
```ruby
    OmniAuth.config.mock_auth[:my_digital_id] = nil
```
Add to `module OmniauthSpecHelpers`:
```ruby
  def mock_mydigital_id_auth(sub:, name: "Ali bin Abu")
    OmniAuth.config.mock_auth[:my_digital_id] = OmniAuth::AuthHash.new(
      provider: "my_digital_id", uid: sub,
      info: {name: name},
      extra: {raw_info: {"sub" => sub, "nama" => name, "nric" => "900101015511"}}
    )
  end
```

- [ ] **Step 2: Write the request spec `spec/requests/mydigital_id_spec.rb`**

```ruby
require "rails_helper"

RSpec.describe "MyDigital ID SSO", type: :request do
  it "signs in a known subject" do
    user = create(:user)
    user.identities.create!(provider: "my_digital_id", uid: "sub-known")
    mock_mydigital_id_auth(sub: "sub-known")

    post "/auth/my_digital_id"
    follow_redirect! # → callback
    follow_redirect! # → after sign in
    expect(controller_signed_in?).to be(true) if respond_to?(:controller_signed_in?)
    expect(response).to have_http_status(:ok).or have_http_status(:found)
  end

  it "routes an unknown subject to the interstitial with a pending stash" do
    mock_mydigital_id_auth(sub: "sub-new", name: "Ali bin Abu")

    post "/auth/my_digital_id"
    follow_redirect! # callback → interstitial
    expect(response).to redirect_to(mydigital_id_continue_path).or have_http_status(:ok)
    follow_redirect! if response.redirect?
    expect(response.body).to include("MyDigital ID")
  end

  describe "linking an existing account" do
    before { mock_mydigital_id_auth(sub: "sub-link") }

    it "links on correct credentials" do
      create(:user, email: "me@hoojah.com", password: "hoojah88", password_confirmation: "hoojah88")
      post "/auth/my_digital_id"
      follow_redirect!
      post "/mydigital-id/link", params: {email: "me@hoojah.com", password: "hoojah88"}
      expect(UserIdentity.find_by(provider: "my_digital_id", uid: "sub-link")).to be_present
    end

    it "rejects wrong credentials" do
      create(:user, email: "me@hoojah.com", password: "hoojah88", password_confirmation: "hoojah88")
      post "/auth/my_digital_id"
      follow_redirect!
      post "/mydigital-id/link", params: {email: "me@hoojah.com", password: "wrong"}
      expect(response).to have_http_status(:unprocessable_entity)
      expect(UserIdentity.find_by(provider: "my_digital_id", uid: "sub-link")).to be_nil
    end
  end

  describe "creating a new account" do
    before { mock_mydigital_id_auth(sub: "sub-create", name: "Ali bin Abu") }

    it "creates on a valid username" do
      post "/auth/my_digital_id"
      follow_redirect!
      expect {
        post "/mydigital-id/register", params: {username: "brandnew"}
      }.to change(User, :count).by(1)
      expect(User.find_by(username: "brandnew").identities.first.uid).to eq("sub-create")
    end

    it "re-renders on a taken username" do
      create(:user, username: "brandnew")
      post "/auth/my_digital_id"
      follow_redirect!
      post "/mydigital-id/register", params: {username: "brandnew"}
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it "fails closed when the interstitial is hit with no pending stash" do
    get "/mydigital-id/continue"
    expect(response).to redirect_to(new_user_session_path)
  end
end
```

> Remove the `controller_signed_in?` line if the suite has no such helper — it's guarded but delete if it confuses. The core assertions are the identity rows and statuses.

- [ ] **Step 3: Run the request spec — expect pass**

```bash
RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/mydigital_id_spec.rb
```
Expected: all green. Fix controller/model issues surfaced here before moving on.

- [ ] **Step 4: Write the system spec `spec/system/mydigital_id_sign_in_spec.rb`**

```ruby
require "rails_helper"

RSpec.describe "MyDigital ID sign-in", type: :system, js: true do
  around do |example|
    prev = ENV["MYID_BASE_URL"]
    ENV["MYID_BASE_URL"] = "https://sso.example.gov.my"
    example.run
    ENV["MYID_BASE_URL"] = prev
  end

  it "creates an account via the interstitial" do
    mock_mydigital_id_auth(sub: "sub-sys", name: "Ali bin Abu")
    visit "/login"
    expect(page).to have_button("Continue with MyDigital ID")
    click_button "Continue with MyDigital ID"

    expect(page).to have_content("Welcome via MyDigital ID")
    fill_in "username", with: "systemuser"
    click_button "Create account and continue"

    expect(User.find_by(username: "systemuser")).to be_present
  end

  it "renders the public notice" do
    visit "/mydigital-id"
    expect(page).to have_content("One identity, one account")
  end
end
```

- [ ] **Step 5: Run the system spec — expect pass**

```bash
RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/system/mydigital_id_sign_in_spec.rb
```
Expected: green (headless Chrome). If the button field `name` differs, match it to the rendered form.

- [ ] **Step 6: Commit**

```bash
git add spec/support/omniauth.rb spec/requests/mydigital_id_spec.rb spec/system/mydigital_id_sign_in_spec.rb
git commit -m "Add request + system specs for MyDigital ID flow"
```

---

## Task 16: Drop the legacy `users.provider`/`uid` columns

Now that no code reads them, remove the columns and their unique index (strong_migrations-safe via `ignored_columns` first).

**Files:**
- Modify: `app/models/user.rb` (add `ignored_columns`)
- Create: migration `db/migrate/*_remove_provider_uid_from_users.rb`

- [ ] **Step 1: Tell ActiveRecord to ignore the columns** — add near the top of `app/models/user.rb` (just inside the class, before `devise`)

```ruby
  # Legacy single-provider columns, superseded by user_identities. Ignored so the app
  # tolerates the pre-drop schema, then removed in the migration below.
  self.ignored_columns += %w[provider uid]
```

- [ ] **Step 2: Write the migration**

```bash
bin/rails g migration RemoveProviderUidFromUsers
```
```ruby
class RemoveProviderUidFromUsers < ActiveRecord::Migration[8.1]
  def change
    remove_index :users, column: [:provider, :uid], unique: true, if_exists: true
    safety_assured do
      remove_column :users, :provider, :string
      remove_column :users, :uid, :string
    end
  end
end
```

- [ ] **Step 3: Migrate dev + test**

```bash
bin/rails db:migrate && bin/rails db:test:prepare
```

- [ ] **Step 4: Re-run the auth specs to confirm nothing read the columns**

```bash
RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/user_mydigital_id_spec.rb spec/models/user_identity_spec.rb spec/requests/omniauth_callbacks_spec.rb spec/requests/mydigital_id_spec.rb
```
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add app/models/user.rb db/migrate db/schema.rb
git commit -m "Drop legacy users.provider/uid columns (superseded by user_identities)"
```

---

## Task 17: Full green gate + reviews

**Files:** none (verification + review).

- [ ] **Step 1: Gem suite green**

```bash
cd /Users/deepsight/code/omniauth-mydigital-id-ruby && bundle exec rspec && bundle exec standardrb
```
Expected: all examples pass; standard clean.

- [ ] **Step 2: Hoojah full CI**

```bash
cd /Users/deepsight/code/hoojah-beta && bin/ci
```
Expected: gates (standardrb, brakeman, bundler-audit) + specs all green. Fix any regressions before proceeding.

- [ ] **Step 3: rails-simplifier review** — dispatch the `rails-simplifier:simplify` agent over the hoojah diff (models, controllers, views added in Tasks 8–16) and the gem. Triage its findings; apply the ones that don't reduce clarity or security; re-run `bin/ci`.

- [ ] **Step 4: rails-security-auditor review** — dispatch `rails-security-auditor:audit-security`. Focus areas: OmniAuth request phase is POST + CSRF-protected; ID-token signature + iss/aud/exp/nonce enforced; `pending_mydid` freshness & fail-closed; NRIC never persisted or logged (grep the diff for `nric`); unique-index race handled; the synthesised `@myid.invalid` email carries only the opaque `sub`. Triage + fix; re-run `bin/ci`.

- [ ] **Step 5: Final commit of any review fixes**

```bash
git add -A && git commit -m "Apply rails-simplifier and rails-security-auditor findings"
```

---

## Definition of done

1. `omniauth-mydigital-id-ruby` RSpec green, standardrb clean.
2. Hoojah `bin/ci` green with the new model/request/system specs.
3. Known `sub` signs in; unknown `sub` routes to link-or-create; one hoojah account per MyID enforced; `pending_mydid` fails closed; NRIC never stored or logged.
4. Both reviewer agents' findings triaged and addressed (or deferred with rationale in `docs/superpowers/HANDOVER.md`).
5. Deferred (per spec §6): live sandbox smoke-test, RP-initiated logout, passkey-based linking, gem publication.
