# Cloudinary (gem + ActiveStorage) & Google Sign-in — Design

**Date:** 2026-08-26
**Branch:** `feature/cloudinary-google-auth` (off `master`, isolated worktree)
**Status:** Approved (brainstorming)

## Summary

Two independent features:

- **Track A — Cloudinary:** move profile-photo uploads from today's client-side *unsigned*
  Cloudinary widget to a *server-side* path: the `cloudinary` Ruby gem providing an ActiveStorage
  storage service, with `User#avatar` as a `has_one_attached`. Config is ENV-driven
  (`CLOUDINARY_URL`).
- **Track B — Google auth:** add `omniauth-google-oauth2` so users can sign up / sign in with
  Google. Auto-link to an existing account by verified email; auto-generate a `@username` for new
  Google users (editable later).

## Prior state (discovered)

- **Cloudinary today** is entirely client-side and hardcoded: `cloudName: "hoojah"`,
  `uploadPreset: "user_photo"` in `app/javascript/controllers/cloudinary_upload_controller.js`; the
  `//widget.cloudinary.com/global/all.js` script in the layout; a hidden field filled by the widget
  and PATCHed to `/u/:username`; the server only validates the returned URL host is
  `res.cloudinary.com/hoojah/`. **No gem, no API key/secret, nothing ENV-driven.** ActiveStorage is
  scaffolded but has zero tables and zero attachments.
- **Google auth today**: nothing. No omniauth gems, no `provider`/`uid` columns, no `omniauthable`,
  no callbacks controller, no buttons.
- `User#photo` is a plain `string` column; `after_create :assign_random_photo` seeds one of four
  hardcoded `res.cloudinary.com/hoojah/…gif` URLs; `validate :photo_from_cloudinary` enforces the
  host. Avatars render through `app/views/ui/_avatar.html.erb` (attached photo → gradient initials
  tile fallback).

## Track A — Cloudinary via `cloudinary` gem + ActiveStorage

### Approach: non-destructive layering (approved)

Keep the `photo` string column and its host validation as the **legacy default** (holds seeded
random GIFs and any existing users' URLs). Add a **new `has_one_attached :avatar`** for
user-uploaded photos, which takes precedence. No data migration, no data loss, seeds keep working.

### Changes

1. **Gemfile:** add `cloudinary` (~> latest 2.x). It ships `ActiveStorage::Service::CloudinaryService`.
2. **`config/storage.yml`:** add
   ```yaml
   cloudinary:
     service: Cloudinary
   ```
3. **Environments:** `config.active_storage.service = :cloudinary` in **production** and
   **development**; **test stays `:test`** (disk) so tests never touch Cloudinary — this also removes
   the headless-Chrome hang that today is worked around by blacklisting the Cloudinary host.
4. **Migration:** standard `active_storage:install` (creates `active_storage_blobs`,
   `active_storage_attachments`, `active_storage_variant_records`).
5. **`User` model:** `has_one_attached :avatar`. Add a content-type + size validation on the
   attachment (images only, reasonable max e.g. 5 MB). Keep `photo` string + `photo_from_cloudinary`
   + `assign_random_photo` untouched.
6. **Avatar resolution:** `ui/_avatar.html.erb` resolves in order:
   **attached `avatar` (rendered via the Cloudinary service URL) → `photo` URL → gradient initials
   tile.** A small helper (e.g. `DesignSystemHelper#ds_avatar_url(user)`) centralises the
   attached-vs-string decision so views stay clean.
7. **Upload UI:** the profile-edit form (`app/views/users/_profile_edit.html.erb`) gets a real
   `file_field :avatar` submitting a **multipart** PATCH to `/u/:username`. The users controller
   permits `:avatar`.
8. **Remove the old client-side widget:** delete
   `app/javascript/controllers/cloudinary_upload_controller.js`, its Stimulus registration, the
   hidden photo field wiring in `_profile_edit`, the `widget.cloudinary.com/all.js` `<script>` in the
   layout, and the corresponding CSP `frame-src`/`script-src` entries for Cloudinary that are no
   longer needed. No other image-upload UI is added.

### Rendering note

For the attached avatar, render the **direct Cloudinary secure URL** (via the service's `url`) rather
than a Rails proxy redirect, so images are served from Cloudinary's CDN. Sizing stays CSS-driven
(fixed `object-cover` boxes as today) — no ActiveStorage variants, so `image_processing`/`mini_magick`
are **not** required.

### Testing (Track A)

- Model spec: `avatar` attaches; validation rejects non-images / oversized; avatar-URL helper prefers
  attachment over `photo` string over tile.
- Request spec: multipart PATCH `/u/:username` with an uploaded fixture attaches the avatar (test disk
  service — no network).
- System spec: profile edit shows a file field; uploading a fixture updates the rendered avatar. No
  Cloudinary host is contacted in test.
- Confirm removing the widget doesn't break the profile-edit system spec.

## Track B — Google Sign-up / Sign-in

### Changes

1. **Gemfile:** add `omniauth-google-oauth2` and `omniauth-rails_csrf_protection` (required for
   OmniAuth 2 request-phase CSRF; makes the request phase POST-only).
2. **Migration:** add nullable `provider:string` and `uid:string` to `users`; unique index on
   `[provider, uid]` added **`algorithm: :concurrently`** (with `disable_ddl_transaction!`) per
   `strong_migrations`.
3. **`User` model:** add `:omniauthable, omniauth_providers: [:google_oauth2]` to the `devise` call.
   Add `User.from_omniauth(auth)`:
   1. find by `provider` + `uid` → return it;
   2. else find by verified `email` → **auto-link** (set `provider`/`uid`, save) → return it;
   3. else **create**: `email`, `full_name` from `auth.info.name`, a random password
      (`Devise.friendly_token[0, 20]`, satisfies `:validatable`), a seeded default `photo`, and an
      **auto-generated unique `@username`** via a `User.generate_username(seed)` helper
      (slugify email local-part/name to the existing username format rules, append the smallest
      numeric suffix that is free).
4. **Routes:** extend `devise_for :users` with
   `controllers: { omniauth_callbacks: "users/omniauth_callbacks" }` (keeping the existing
   `registrations` override, `path: ""`, and `path_names`). Keep the routes file's hand-written,
   commented style.
5. **Callbacks controller:** `Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController`
   with a `google_oauth2` action → `User.from_omniauth(request.env["omniauth.auth"])`; sign in +
   redirect on success, redirect to `/login` with a flash on failure. (Devise controller ⇒
   `verify_authorized` is auto-skipped.)
6. **Config:** in `config/initializers/devise.rb`,
   `config.omniauth :google_oauth2, ENV["GOOGLE_CLIENT_ID"], ENV["GOOGLE_CLIENT_SECRET"]`.
7. **UI:** a design-system pill **"Continue with Google"** button (a `button_to` POST to
   `user_google_oauth2_omniauth_authorize_path`, CSRF-protected) on `/login` and `/signup`, with a
   Google "G" glyph and a divider ("or"). Matches the house pill-button style.

### Account-linking rule (approved)

Auto-link by verified email: if the Google email matches an existing user, attach the Google identity
to that account. Google emails are treated as verified (Devise `:confirmable` is not enabled).

### Testing (Track B)

- Model spec: `from_omniauth` — new user creation (username generated, unique on collision, random
  password valid); auto-link path sets provider/uid on the existing email account; returning user
  found by provider+uid.
- Request spec: OmniAuth test-mode mock → callback creates/links and signs in; failure/`invalid`
  auth redirects with a flash.
- System spec: "Continue with Google" button on `/login` and `/signup`; with OmniAuth mock, the flow
  signs the user in and lands on the dashboard.

## Mechanics

- **Isolation:** git worktree off `master` at
  `~/.config/superpowers/worktrees/hoojah-beta/cloudinary-google-auth`. The `feature/content-moderation`
  working tree is untouched.
- **Execution:** Fable as architect/advisor; Opus subagents implement (TDD); review checkpoints
  between tasks.
- **Quality gates (must stay green):** `bundle exec standardrb`, `bundle exec brakeman -q`,
  `bundle exec bundler-audit check --update`, and the relevant RSpec. Full `bin/ci` before merge.
- **Completion:** merge `feature/cloudinary-google-auth` into `master`, push, then report the exact
  production ENV vars.

## Production ENV vars (final deliverable)

- `CLOUDINARY_URL` — `cloudinary://<api_key>:<api_secret>@<cloud_name>` (from the Cloudinary console;
  `cloud_name` is `hoojah`).
- `GOOGLE_CLIENT_ID` — OAuth 2.0 Web client ID (Google Cloud Console → Credentials).
- `GOOGLE_CLIENT_SECRET` — matching client secret. Authorized redirect URI:
  `https://hoojah.rudzainy.com/auth/google_oauth2/callback` (+ the dev URL for local testing).

## Out of scope / YAGNI

- No ActiveStorage variants / image processing gem.
- No hujah images or any new upload surface.
- No migration of existing `photo` string URLs into ActiveStorage blobs.
- No signed direct-from-browser uploads (server-side multipart is simpler and fully testable).
- No additional OAuth providers.
