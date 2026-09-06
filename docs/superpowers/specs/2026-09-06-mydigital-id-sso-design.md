# MyDigital ID SSO Integration — Design

**Date:** 2026-09-06
**Status:** Approved design → implementation planning
**Scope:** A reusable OmniAuth strategy gem for Malaysia's MyDigital ID SSO, plus its
integration into hoojah-beta (Devise + OmniAuth).

---

## 1. Background

[MyDigital ID SSO](https://developer.digital-id.my/) is Malaysia's national digital-identity
login layer. Technically it is a **Keycloak** cluster (realm `mydid`) fronting a MyDOW OIDC
connector that performs the MyDigital ID QR/3-way-handshake authentication. To a relying party
it is a **standard OpenID Connect provider** using the OAuth 2.0 Authorization Code flow.

Reference material (read during brainstorming):

- Org repos: <https://github.com/MyIDSSO> (sample apps in Go, Swift, Java, Flutter, Next.js,
  Laravel, CodeIgniter).
- Authoritative spec: `SSO-Integration-Guideline` repo, branch `branch-v5.0`,
  `Guideline-v5.0.md` (v5.0, dated 27/11/2025).

### What the provider gives us

- **Endpoints** (derived from the SSO DNS host + realm):
  - Authorization: `{base_url}/realms/{realm}/protocol/openid-connect/auth`
  - Token:         `{base_url}/realms/{realm}/protocol/openid-connect/token`
  - Userinfo:      `{base_url}/realms/{realm}/protocol/openid-connect/userinfo`
  - Logout:        `{base_url}/realms/{realm}/protocol/openid-connect/logout`
  - JWKS:          `{base_url}/realms/{realm}/protocol/openid-connect/certs`

  (The v5.0 endpoint table shows a legacy `/auth/realms/...` prefix in one place, but every
  code sample uses `/realms/...`. The gem uses `/realms/...` and exposes the prefix as a
  configurable option so a future Keycloak-legacy host can be accommodated.)
- **Client:** confidential — `client_id` + `client_secret`.
- **Flow:** Authorization Code, `response_type=code`, `scope=openid profile email`, with
  `state`, `nonce`, and `prompt=login`.
- **Userinfo claims:** `nric` (Malaysian IC number) and `nama` (full name). **No email.**
  The stable OIDC subject identifier is `sub`.

### Two things the official samples get wrong (and we will not)

1. They read `userinfo` and trust it **without validating the ID token signature**. We validate
   the ID token against JWKS (`iss`/`aud`/`exp`/`nonce`) before trusting any claim.
2. The Laravel sample stores a **hash of the raw NRIC** as the account key and even matches by
   iterating every user and `Hash::check`-ing — both a PII and an O(n) problem. We key on the
   opaque, stable `sub` and never persist NRIC.

---

## 2. Decisions (from brainstorming)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Gem scope | **Reusable** standalone OmniAuth strategy gem, usable across all the workspace's Devise apps. |
| 2 | Gem name / location | `omniauth-mydigital-id-ruby`, its own git repo at `/Users/deepsight/code/omniauth-mydigital-id-ruby`, referenced from hoojah via a `path:` Gemfile entry during development. |
| 3 | Internal design | **Approach A** — purpose-built `OmniAuth::Strategies::OAuth2` subclass with JWKS ID-token validation. Not `omniauth_openid_connect` (fragile discovery dependency), not hand-rolled Faraday. |
| 4 | NRIC storage | **Never persist NRIC.** Use the Keycloak `sub` as `uid`, `provider = "mydid"`. NRIC only transits during the auth exchange. |
| 5 | Account linking on first MyID login | **Explicit link by default**, with an escape hatch to create a new account (see §4.3). Never auto-link by email — MyID supplies none. |
| 6 | Multi-provider | Introduce a **`user_identities`** table so one account can hold Google + MyID (+ future providers). Migrate existing `users.provider/uid` into it. |
| 7 | Credentials | **Spec-only** build: WebMock + signed-JWT fixtures, ENV placeholders. Live sandbox smoke-test deferred until credentials are issued. |

---

## 3. Component 1 — the gem `omniauth-mydigital-id-ruby`

### 3.1 Purpose & boundary

A single OmniAuth strategy. Input: OmniAuth's Rack middleware invocation + configured
credentials. Output: a standard OmniAuth **auth hash** on the callback env. It knows nothing
about hoojah, Devise, users, or databases — it speaks only OAuth2/OIDC. This is what makes it
reusable.

### 3.2 Public interface

```ruby
# In an initializer (Devise or bare OmniAuth):
config.omniauth :mydigital_id,
  ENV["MYID_CLIENT_ID"],
  ENV["MYID_CLIENT_SECRET"],
  base_url: ENV["MYID_BASE_URL"],   # SSO DNS host, e.g. https://sso.example.gov.my
  realm:    ENV.fetch("MYID_REALM", "mydid")
```

**Options:**

| Option | Default | Meaning |
|--------|---------|---------|
| `base_url` | (required) | SSO DNS host, scheme + host, no trailing slash. |
| `realm` | `"mydid"` | Keycloak realm. |
| `scope` | `"openid profile email"` | OAuth scope. |
| `pkce` | `true` | Send PKCE `code_challenge` (S256). Harmless for confidential clients, defends the code. |
| `path_prefix` | `""` | Set to `"/auth"` for legacy Keycloak hosts. |
| `client_options.ssl` etc. | — | Passed through to the underlying OAuth2 client. |

### 3.3 Internal structure

`OmniAuth::Strategies::MyDigitalId < OmniAuth::Strategies::OAuth2`

- `client_options` computed from `base_url`/`realm`/`path_prefix` → `site`, `authorize_url`,
  `token_url`.
- `authorize_params` adds `nonce` (random, stored in session) and passes `prompt` through.
- `uid { raw_info["sub"] }`.
- `info { { name: raw_info["nama"] } }` — deliberately **no email** key.
- `extra { { raw_info: raw_info, id_token_claims: validated_id_token_claims } }`;
  `raw_info` includes `nric` for the relying party to consume in-request (hoojah won't store it).
- `raw_info` = userinfo endpoint response, memoized.
- **ID-token validation** (`IdTokenValidator`, a plain object): decode the `id_token` from the
  token response, fetch JWKS (cached in-process with TTL + key-id lookup), verify RS256
  signature, and assert `iss == {base_url}/realms/{realm}`, `aud == client_id`, `exp` not past,
  and `nonce` matches the session value. Raises `OmniAuth::MyDigitalId::IdTokenError` (→ OmniAuth
  failure) on any mismatch.

### 3.4 Dependencies

`omniauth` (~> 2), `omniauth-oauth2` (~> 1.8), `jwt` (~> 2). Dev: `rspec`, `webmock`,
`rack-test`, `standard`.

### 3.5 Tests (gem)

- Strategy request phase: correct authorize URL, params, PKCE challenge present, nonce stored.
- Callback phase (WebMock-stubbed token + userinfo + JWKS): auth hash shape — uid=`sub`,
  name=`nama`, `extra.raw_info["nric"]` present, no `info.email`.
- `IdTokenValidator`: happy path with a locally signed RS256 fixture; and each failure —
  bad signature, wrong `aud`, wrong `iss`, expired, nonce mismatch, unknown `kid`.
- JWKS caching: second call within TTL does not refetch; `kid` rotation refetches.

---

## 4. Component 2 — hoojah integration

### 4.1 Data model: `user_identities`

Migration set (respecting `strong_migrations`):

1. Create `user_identities` (`id`, `user_id` FK, `provider:string`, `uid:string`, timestamps).
   Unique index on `[provider, uid]`; index on `[user_id, provider]`.
2. Backfill: for each user with `provider`/`uid` present, insert a matching identity row
   (batched).
3. **Later, separate migration** (after code no longer reads the columns): drop
   `users.provider`, `users.uid` and their unique index.

```ruby
class UserIdentity < ApplicationRecord
  belongs_to :user
  validates :provider, presence: true
  validates :uid, presence: true, uniqueness: {scope: :provider}
end

# User
has_many :identities, class_name: "UserIdentity", dependent: :destroy
```

### 4.2 Model methods

- Rework `User.from_omniauth` (Google) to look up / create through `identities` instead of the
  `provider`/`uid` columns. Its verified-email auto-link behaviour is preserved **for Google
  only**.
- Add `User.from_mydigital_id(auth)` → returns the user owning identity `["mydid", auth.uid]`,
  or `nil`. It **never** creates and **never** matches on email. `nil` means "unknown subject →
  go to the link/create interstitial".
- `User.create_with_mydigital_id(username:, sub:)` — used by the create escape hatch: validates
  username, sets a secure random password (`Devise.friendly_token`), creates the user and its
  `mydid` identity in one transaction. Relies on the unique `[provider, uid]` index to enforce
  **one hoojah account per MyID** under a race (`rescue RecordNotUnique`).

### 4.3 Controllers & flow

**`Users::OmniauthCallbacksController#mydid`:**

1. `auth = request.env["omniauth.auth"]`.
2. `user = User.from_mydigital_id(auth)`.
3. If `user` present → `sign_in_and_redirect`.
4. If `nil` → stash `auth.uid` (the `sub`) and `auth.info.name` in a **short-lived signed value**
   (e.g. `session[:pending_mydid]` with a timestamp; expired after N minutes) and
   `redirect_to new_mydigital_id_link_path`.

**`MydigitalIdLinksController`** (new; owner/anon interstitial, `skip_authorization` — it is a
pre-auth linking surface, like Devise controllers):

- `new` — renders the interstitial: "We found your MyDigital ID. Link it to your Hoojah account,
  or create a new one." Requires a live `pending_mydid`; otherwise redirect to login with alert.
- `create` (**link existing**) — params: email + password (reuse Devise's `valid_password?`), or
  a passkey assertion. On success, create the `mydid` identity on that user, clear
  `pending_mydid`, sign in. On the unique-index collision ("this MyID is already linked to
  another account") → friendly error.
- `create_account` (**escape hatch**) — params: `username` only. Server-side re-validates
  uniqueness/format (client-side validation is UX, not trust). Calls
  `User.create_with_mydigital_id`. Signs in, lands on dashboard. Hoojah has no multi-step
  onboarding, so the account is immediately complete.

All `pending_mydid` reads assert freshness and presence; a missing/stale value fails closed to
the login page.

### 4.4 Views / UI

- **Login & signup pages:** add a "Log in with MyDigital ID" button (mirrors the existing Google
  button; `button_to` via `omniauth-rails_csrf_protection`), plus a small link: "What is
  MyDigital ID login?" → `/mydigital-id`.
- **Interstitial** (`mydigital_id_links/new`): two clear paths — link (email+password / passkey)
  and "I don't have a Hoojah account yet" (username field with async uniqueness check).
- Follow the design system (`ds_button_classes`, `ui/_card`, token colours, no hex). Interpolated
  utilities safelisted if any are introduced.

### 4.5 Public legal notice

`PagesController#mydigital_id`, route `get "/mydigital-id", to: "pages#mydigital_id"`, sibling of
`/about`, `/terms`. Static, no auth. Content states:

- MyDigital ID login is **per registered individual in Malaysia** and is bound by Malaysian laws
  and policies.
- **Only one Hoojah account is allowed per MyDigital ID.**
- Account recovery for a Hoojah account created via MyDigital ID requires **contacting a Hoojah
  moderator** (there is no password to reset for an SSO-created account).

### 4.6 Configuration

- `config/initializers/devise.rb`: `config.omniauth :mydigital_id, ENV["MYID_CLIENT_ID"],
  ENV["MYID_CLIENT_SECRET"], base_url: ENV["MYID_BASE_URL"], realm: ENV.fetch("MYID_REALM",
  "mydid")`.
- `User`: add `:mydigital_id` to `omniauth_providers`.
- `Gemfile`: `gem "omniauth-mydigital-id-ruby", path: "../omniauth-mydigital-id-ruby"`.
- `.env` / credentials docs: `MYID_BASE_URL`, `MYID_REALM`, `MYID_CLIENT_ID`, `MYID_CLIENT_SECRET`.
  Absent creds → the provider is simply not offered (button hidden), never a boot crash.

### 4.7 Tests (hoojah)

- **Model:** `from_mydigital_id` (known/unknown sub), `create_with_mydigital_id` (happy + race),
  reworked `from_omniauth` still green, one-account-per-MyID enforced.
- **Request:** `#mydid` callback for known sub (signs in) and unknown sub (redirects to
  interstitial with a fresh `pending_mydid`); `MydigitalIdLinksController` link-existing (good +
  wrong password + already-linked), create-account (good + taken username + stale pending).
- **System (js):** button on login page → OmniAuth test mode → interstitial → both branches to
  dashboard. `pages#mydigital_id` renders.
- OmniAuth `mock_auth` + `test` mode helpers in `spec/support`.

---

## 5. Process

- **Fable orchestration**: Fable 5 as architect/advisor planning and delegating; Opus 4.8 does
  token-heavy execution. Effort-level routing as the cost lever.
- **Subagent-driven development** executing the written plan's independent tasks.
- **TDD** throughout (red → green → refactor), per the repo's prevailing method
  (implementer → independent review → batched fixes → re-verify).
- **Reviews** before finishing: `rails-simplifier` (37signals/One-Person-Framework pass) and
  `rails-security-auditor` (OIDC/OAuth + Rails security). Security focus areas: state/nonce/PKCE,
  ID-token signature + claim validation, `pending_mydid` freshness & fail-closed, CSRF on the
  OmniAuth request phase, no NRIC persistence/logging, unique-index race handling.

## 6. Out of scope / deferred

- Live sandbox smoke-test (no credentials yet).
- RP-initiated logout / single-logout against the MyID logout endpoint (hoojah keeps its own
  Devise session lifecycle for now).
- Publishing the gem to RubyGems or a git source (stays a `path:` gem until it stabilises).
- Collapsing `votes.vote` or any unrelated refactor.
- Native-client (`Api::V1`) MyID support.

## 7. Success criteria

1. `omniauth-mydigital-id-ruby` builds, its RSpec suite is green, `standardrb` clean.
2. Hoojah `bin/ci` green (gates + specs) with the integration and new specs.
3. A known MyID `sub` signs in; an unknown `sub` is routed to link-or-create; one hoojah account
   per MyID is enforced; NRIC never touches the database or logs.
4. Both reviewer agents' findings triaged and addressed (or explicitly deferred with rationale).
