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
| `realm_path_prefix` | `nil` | Keycloak realm-path prefix. Set to `/auth` for the legacy Keycloak path layout; `nil` means none. (Distinct from OmniAuth's reserved `path_prefix` routing option.) |

## Auth hash

- `uid` → OIDC `sub` (opaque, stable; **not** the NRIC).
- `info.name` → `nama`. No `info.email` (MyDigital ID supplies none).
- `extra.raw_info` → full userinfo incl. `nric` (consume in-request; do not persist).
- `extra.id_token_claims` → validated ID-token payload.

Requires `omniauth-rails_csrf_protection` and a POST request phase (OmniAuth 2 / CVE-2015-9284).
