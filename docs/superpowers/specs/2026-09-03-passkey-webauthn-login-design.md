# Passkey (WebAuthn) passwordless login — design

**Date:** 2026-09-03
**Status:** Approved (brainstorm), pending implementation plan
**Author:** brainstormed with Claude

## Summary

Add **passkeys** (WebAuthn discoverable credentials) as a **passwordless alternative
login** to Hoojah, sitting beside the existing email+password form and the "Continue with
Google" button. A returning user taps one "Sign in with a passkey" button, the browser
offers the passkeys saved for this site, they confirm with Face ID / fingerprint / security
key, and they are signed in — **no email typed, no password**. Logged-in users add and
manage passkeys from a dedicated account **security page**.

Implemented as a **hand-rolled Warden `:passkey` strategy** on top of the `webauthn` gem,
mirroring the existing Google-OAuth "second credential path" — matching this codebase's
hand-written-routes, high-comment-density, paranoid-security ethos.

## Goals

- Passwordless sign-in via a discoverable (usernameless) passkey.
- Self-service enrollment/management: add, list (nickname + created + last-used), rename, delete.
- No new lockout risk: **password login always remains**, so a passkey is purely additive.
- Preserve the app's security posture: `paranoid = true` (no enumeration), CSRF on all HTML
  writes, Pundit owner-only scoping on management surfaces, fail-closed verification.

## Non-goals (YAGNI / deferred)

- **MFA / second-factor** passkeys (passkey stays a *primary alternative*, not a step-up).
- **Passwordless-only accounts** (registration still creates an email+password/Google account;
  no recovery-code system needed because password is always a fallback).
- **Email-first passkey login** as a fallback path (usernameless only; could be added later).
- **Post-signup "add a passkey" onboarding prompt** (management lives only on the security page).
- Cross-device / hybrid QR flows beyond whatever the browser/authenticator provides natively.
- Rate-limiting middleware (noted as a follow-up; see Security).

## Architecture

### Data model

**`users.webauthn_id`** — `string`, unique, **nullable**.
A stable, opaque per-user WebAuthn **user handle**: 64 random bytes, base64url
(`WebAuthn.generate_user_id`). Generated **lazily** the first time a user enrolls a passkey
(inside the creation-options request), then persisted for the life of the account. This is
the value a discoverable credential returns at login, letting us resolve the account
**without an email being typed**. Deliberately **not** the email or DB id — no PII in the
handle, and it must never change or existing passkeys break.

**New table `webauthn_credentials`:**

| column         | type     | notes                                                        |
|----------------|----------|--------------------------------------------------------------|
| `user_id`      | fk       | indexed; `dependent: :destroy` from User                     |
| `external_id`  | string   | the credential id (base64url); **unique index**              |
| `public_key`   | string   | COSE public key returned at registration                     |
| `nickname`     | string   | user-facing label; unique **per user**; required             |
| `sign_count`   | bigint   | default 0; clone-detection counter                           |
| `last_used_at` | datetime | nullable; bumped on each successful assertion                |
| timestamps     |          |                                                              |

Associations: `User has_many :webauthn_credentials, dependent: :destroy`;
`WebauthnCredential belongs_to :user`. Validations: presence of `external_id`, `public_key`,
`nickname`; uniqueness of `external_id` (global) and `nickname` (scoped to user).

### Warden `:passkey` strategy

A custom `Warden::Strategies` `:passkey` strategy, registered in a Devise/warden
initializer. At login it:

1. Reads the assertion JSON (POST body) and the **expected challenge** stored server-side in
   the session during the options request.
2. Builds `WebAuthn::Credential.from_get(assertion)`, resolves the local
   `WebauthnCredential` by `external_id`, and resolves the **user** by the assertion's
   returned user handle (`webauthn_id`).
3. Verifies signature, `origin`, `rp_id`, challenge, and `sign_count` via the `webauthn` gem.
4. On success: bump `sign_count` + `last_used_at`, then `success!(user)`.
5. On any mismatch / missing record / stale challenge: **fail closed** with a single generic
   message (paranoid — no distinction between "no such credential" and "bad signature").

The strategy is invoked by the sessions `passkey` action via `warden.authenticate!(:passkey,
...)` (or `authenticate` + explicit sign-in), scoped to the `:user` mapping.

### Controllers & routes (all hand-written; HTML = CSRF on)

**`Users::SessionsController < Devise::SessionsController`** (new override; Devise controllers
are exempt from Pundit's `verify_authorized`):

- `POST /login/passkey/options` → JSON **authentication** challenge. Usernameless: empty
  `allowCredentials`, `userVerification: "required"`. Stores the challenge in the session.
- `POST /login/passkey` → `passkey` action; runs Warden `:passkey`, signs the user in on
  success, re-renders the login page with the generic alert on failure.

**`Users::PasskeysController`** (new; **main route → CSRF on**; owner-only via `policy_scope`
+ `PasskeyPolicy`; mirrors the `/blocks` owner-by-construction pattern):

- `GET    /settings/passkeys`         → index (list the current user's passkeys).
- `POST   /settings/passkeys/options` → JSON **creation** challenge; lazily assigns
  `webauthn_id` if absent; stores challenge in session.
- `POST   /settings/passkeys`         → verify attestation → create `WebauthnCredential`;
  respond with a Turbo Stream appending the new row.
- `PATCH  /settings/passkeys/:id`     → rename (`nickname`).
- `DELETE /settings/passkeys/:id`     → delete.

`PasskeyPolicy` restricts every action to the record's owner; `policy_scope` on index. The
security page is linked from the Devise registration-edit page (`/edit`).

### Frontend (Stimulus + importmap — no Node, no build step)

- **Pin `@github/webauthn-json`** via importmap (from a CDN, pinned by version) to run the
  `navigator.credentials` ceremony and handle base64url ↔ ArrayBuffer encoding — no
  hand-rolled buffer juggling.
- **`passkey_authentication_controller.js`** (login page): on button click → `fetch` options
  → `webauthnJSON.get({ publicKey })` → POST the assertion to `/login/passkey`. Feature-detect
  `window.PublicKeyCredential`; **hide the button when unsupported** (progressive
  enhancement). Mirrors the Turbo-disabled behavior of the Google `button_to`.
- **`passkey_registration_controller.js`** (security page): add → `fetch` creation options →
  `webauthnJSON.create({ publicKey })` → POST attestation → Turbo Stream appends the passkey
  row. Rename/delete use ordinary Turbo forms/`button_to`.

### Configuration

`config/initializers/webauthn.rb`:

```ruby
WebAuthn.configure do |config|
  config.origin = ENV.fetch("WEBAUTHN_ORIGIN")      # prod: https://hoojah.rudzainy.com; dev: http://localhost:3000
  config.rp_name = "Hoojah"
  # rp_id derived from origin host (hoojah.rudzainy.com / localhost)
  config.credential_options_timeout = 120_000
  # algorithms default (ES256, RS256); userVerification "required" set per-request in options
end
```

Env vars (documented in the plan): `WEBAUTHN_ORIGIN` (required), optional `WEBAUTHN_RP_ID`
override. Add WebAuthn credential/assertion params to
`config/initializers/filter_parameter_logging.rb`.

## Security posture

This app treats privacy/security as a real constraint (secret-ballot votes, `paranoid = true`).
Passkey work must uphold it:

- **Single-use challenges**, stored server-side in the session and **cleared after verify** —
  never trust a client-supplied challenge.
- **Strict `origin` + `rp_id`** verification (delegated to the `webauthn` gem).
- **`sign_count` clone detection**: reject on counter regression, but **tolerate authenticators
  that always report 0** (common on platform/passkey authenticators) rather than locking users out.
- **Usernameless login inherently sidesteps email enumeration** — a natural fit with
  `paranoid = true`. Failure messages are generic and identical across failure modes.
- `userVerification: "required"` so a biometric/PIN gesture is always present.
- **No lockout**: deleting the last passkey is safe because password login always remains; the
  delete UI still shows a brief confirm.
- **Follow-up (deferred):** rate-limit the `/login/passkey/options` and
  `/settings/passkeys/options` endpoints (e.g. Rack::Attack) to blunt challenge-harvesting.

## Testing (RSpec + FactoryBot conventions)

Deterministic ceremonies use the **`webauthn` gem's fake authenticator / `WebAuthn::FakeClient`**
so no real hardware is needed.

- **Model spec** — `WebauthnCredential` validations + `User` association (`dependent: :destroy`).
- **Policy spec** — `PasskeyPolicy` (owner-only; non-owner denied; scope excludes others' rows).
- **Request specs**
  - Registration: options endpoint returns a valid challenge + stores it; verify creates a
    credential; lazy `webauthn_id` assignment; rename; delete.
  - Login: options endpoint; `:passkey` verify signs in a user via a fake assertion; tampered
    signature / stale challenge / unknown credential all fail closed with the generic message.
- **Warden-strategy spec** — success and each fail-closed branch in isolation.
- **System spec (highest risk)** — one end-to-end login via Chrome's **CDP virtual
  authenticator** (Cuprite exposes raw CDP: `WebAuthn.enable` + `addVirtualAuthenticator`),
  driving the real button + Stimulus controller. **Fallback:** if the virtual authenticator
  proves flaky in CI, rely on the request-level coverage above and keep the system spec minimal
  or pending.

## Open items carried into the plan

- Exact importmap pin (version + CDN) for `@github/webauthn-json`.
- Whether `/settings/passkeys` should later grow into a broader `/settings` account hub
  (out of scope now; single page for this work).
- CDP virtual-authenticator system-spec viability (best-effort; request-level is the safety net).
