# Hujah Image Attachments — Design Spec

**Date:** 2026-09-07
**Status:** Approved (brainstorming complete)
**Source design:** Claude Design project "Image attachment for Hujahs" (`3e310855-46c5-49b9-8c65-9ff876958c00`), file `Hujah Image Attachments.dc.html`. Screens 1a–1h + baselines 0a–0c.
**Decisions:** Full design in scope · ActiveStorage **direct upload** · single image-flag auto-holds the image (soft-hide with "Show anyway").

## 1. Summary

One image per hujah, always shown **16:9 below the claim**. Images are attached **only from the full composer** (`/hoojah/new`); the inline feed composer and the argument/reply composer stay text-only. Tapping an image on a card or the single-hujah page opens a **lightbox** (natural aspect, alt as caption). Flagging becomes **image-aware** (two new reasons, an image-held state, and a "Remove image only" moderation outcome). Dark theme comes free via existing tokens.

Storage is already provisioned: ActiveStorage is installed and configured (Cloudinary in dev, S3/Garage in prod, Disk in test). `User#avatar` is the template to mirror throughout.

## 2. Data model (`hujahs`)

- `has_one_attached :image`.
- Constants on `Hujah`: `MAX_IMAGE_BYTES = 5.megabytes`, `ALLOWED_IMAGE_TYPES = %w[image/png image/jpeg image/gif image/webp]`.
- `validate :image_is_valid_image` — content-type in `ALLOWED_IMAGE_TYPES` and `byte_size <= MAX_IMAGE_BYTES` (mirror `User#avatar_is_valid_image`, including the "skip if not attached" guard).
- New migration columns:
  - `image_alt :string` — optional alt text, validated `length: { maximum: 200 }`.
  - `image_removed_at :datetime` — set when a moderator chooses "Remove image only"; `nil` = image present. (`strong_migrations`: plain `add_column`, nullable, no default — safe.)
- **Derived** `image_held?`: `flags.pending.where(subject: %i[image_graphic image_not_theirs]).exists?`. Not stored — avoids drift. Add a helper `image_visible_to?(viewer)` / render-state method (see §4).
- Rendering-state method on `Hujah` (single source of truth for the three visual states):
  - `image_display_state` → `:none` (no attachment or `image_removed_at?`), `:held` (`image_held?`), or `:shown`.
- Serving: a helper (e.g. `ds_hujah_image_url(hujah)` or reuse pattern) returns `rails_storage_proxy_path(hujah.image)` — **never** `blob.url` (presigned URLs expire in 5 min and rot in cached HTML).
- Eager-loading: add `includes(image_attachment: :blob)` to the queries that feed `_hujah_card` (index/feed, profile, search) so prosopite stays quiet.

## 3. Composer + direct upload

Only the full composer (`app/views/hujahs/_compose_form.html.erb`, top-level only).

**Form changes:** add `multipart: true`; keep `turbo: false`. Add permitted params `:image` (a blob signed_id) and `:image_alt` to `HujahsController#compose_params`. ActiveStorage assigns the blob from the signed_id on `current_user.hujahs.new(compose_params)`. Server-side validation from §2 still applies.

**New `image_upload` Stimulus controller** (built on ActiveStorage `DirectUpload`; pin `@rails/activestorage` in importmap if not already pinned):

- **Add-an-image dialog** — native `<dialog>` + existing `dialog_controller`, same shell/copy as `_flag_dialog` (rounded-lg, shadow-lg, `backdrop:bg-black/40`, hairline header + grey `X`, divider-separated rows, bare grey Cancel). Opened by the (currently inert) footer "Add image" button.
  - Helper line: "JPG, PNG, WebP or GIF · up to 5 MB · one image".
  - Row 1 **Upload from device** ("Photos, files or a screenshot") → hidden `<input type="file" accept="image/png,image/jpeg,image/gif,image/webp">`.
  - Row 2 **Take a photo** ("Opens your camera") → hidden `<input type="file" accept="image/*" capture="environment">`.
  - Terms/Privacy microcopy; bare grey **Cancel**.
- **On file pick:** client-side validate type + size first.
  - Too large → red-50 banner "That image is N MB — the limit is 5 MB." / "Try a smaller one, or screenshot it first." (dialog stays open, rows still shown).
  - Unsupported type → red-50 banner "We can't attach a .EXT file." / "Export it as JPG or PNG, then try again."
- **On valid file:** start `DirectUpload` immediately. Dialog switches to the "Adding your image" state — dimmed 16:9 preview, filename + size + live **progress bar** + %, copy "The image is attached when this finishes — you can keep typing your hoojah meanwhile.", **Post button disabled**, "Cancel upload".
  - Success → write blob `signed_id` into a hidden `hujah[image]` field; close/replace dialog; reveal the attached state in `<main>`; re-enable Post.
  - Network failure → dashed red box "Upload didn't finish" + filename + "check your connection", buttons **Retry** / **Choose another**.
  - "Cancel upload" / remove → abort, clear hidden field, restore idle.
- **Attached state (in the composer body, below the claim):** 16:9 preview (`aspect-ratio:16/9; object-cover; rounded-2xl; bg-card-2`), top-right circular **remove (X)**, **ALT** badge (bottom-left), size/crop badge (bottom-right). Below it, the optional **alt-text field** (card, hairline border, rounded-xl) with a `char_counter_controller` "n/200" and helper "Optional — describe the image for people who can't see it."

**Do NOT ship the design-canvas runtime.** `image-slot.js`, `support.js`, `_ds_bundle.js`, `styles.css` from the imported project are canvas scaffolding — reference only. Rebuild with the app's real design system (`ds_button_classes`, `ui/_card`, `ui/_divider`, `dialog_controller`, tokens already in `application.css`).

## 4. Rendering — feed card & single page

Add an image block **below the claim body**, above the vote bars, in:
- `app/views/hujahs/_hujah_card.html.erb` (after the body div).
- `app/views/hujahs/show.html.erb` (after the `<h1>` claim).

Extract a shared partial `app/views/hujahs/_hujah_image.html.erb` taking `hujah` + a `context:` (`:card` | `:show`). It branches on `hujah.image_display_state`:
- `:none` → render nothing.
- `:held` → the held placeholder: "Image hidden while we review a report." / "The claim stays votable. Only the image is held." + **Show anyway** button. Reveal is a small `image_reveal` Stimulus action (or a `data-action` on `lightbox`/reveal controller) — **per-viewer, not stored**.
- `:shown` → the 16:9 image, `tap → lightbox` (see §5), with `alt` = `image_alt` (or a sensible default).

Whole-hujah removal (`moderation_status: removed`) already hides everything via `not_removed`/`visible_to?` — no image-specific handling needed there.

## 5. Lightbox

New **`lightbox` Stimulus controller** on a full-screen native `<dialog>` (one per page, or one per image — decide in plan; prefer a single shared dialog populated on open to keep DOM light):
- Natural-aspect image (not cropped), `@user · date` header, **alt text as caption**.
- Close on backdrop click, Esc (native `<dialog>`), and **swipe-down** (touch). "Pinch to zoom · swipe down to close" hint.
- `teardown()` closes it on `turbo:before-cache`.
- Any interpolated/utility classes the controller toggles must be in the `@source inline` safelist.

## 6. Flagging — image-aware (additive to the frozen `_flag_dialog`)

- Extend `Flag#subject`: `enum :subject, { spam: 0, abusive: 1, irrelevant: 2, image_graphic: 3, image_not_theirs: 4 }`.
- **Frozen contract:** the existing three rows, all `dom_id`s (`flag_control`, `flag_dialog`), all `data-*`, the POST target, and every word of existing copy stay **byte-identical** (`spec/system/flag_spec.rb`). The two image rows — "The image is graphic or explicit" / "The image isn't theirs to post" — and the image-thumbnail context row ("@user · the claim and its image are reviewed together.") render **only when `hujah.image.attached? && !hujah.image_removed_at?`**.
- `FlagsController#create` already `permit(:subject)` and `find_or_initialize_by(hujah:)`; the new subjects need no controller change beyond allowing them (enum validation). Guard: reject image subjects when the hujah has no image (defense-in-depth in the policy or model).
- Filing an image-subject flag → `image_held?` true → card renders the held state (§4). Existing `create.turbo_stream.erb` success row copy may gain the image-aware "Thanks — image and claim are with review." only when an image reason was chosen (keep the existing copy otherwise).

## 7. Moderation — "Remove image only" (net-new)

- `Hujah#remove_image!(by:)`: idempotent (`return if image_removed_at?`); in a transaction set `image_removed_at = Time.current`, `image.purge_later`, resolve pending image-subject flags as `:actioned` (mirror `remove!`'s flag-resolution), create a `Notification` with a new category `image_removed`. Claim stays `active`/votable.
- Notification: add `image_removed` to the `Notification` category enum + its rendering (mirror `moderation_removed`).
- `/moderation` queue (`app/views/moderation/_flagged_hujah.html.erb`): when the row's hujah has image flags / an attached image, show an image thumbnail + context ("N reports · image is graphic") and a **Remove image only** button (`ds_button_classes` tone `disagree` or `neutral`) alongside the existing Dismiss / Warn / Remove. `dom_id(hujah, :moderation_item)` stays frozen; additive only.
- New route: `delete "/moderation/:slug/image", to: "moderation#remove_image", as: :remove_image_moderation` (or `post .../remove_image`). New `moderation#remove_image` action, `authorize :moderation, :remove_image?` in the policy. New `remove_image.turbo_stream.erb` updating the row + pending-count chip (dismiss the row only if no non-image flags remain — otherwise keep it for the claim).

## 8. Testing & quality gates

- **Model specs** (`spec/models/hujah_spec.rb`, `flag_spec.rb`): image type/size validation, `image_alt` length, `image_display_state` / `image_held?`, `remove_image!` (purge + flag resolution + notification + claim stays active), new flag subjects.
- **Request specs**: create hujah with `hujah[image]=<signed_id>` (+ `image_alt`); reject oversize/wrong-type; flag with image subjects (and rejection when no image); `moderation#remove_image` authorization + effect.
- **System specs** (Cuprite, `js: true`): composer dialog open → attach (stub/perform direct upload) → preview + alt + remove → Post; feed/single render; lightbox open/close; flag image rows appear only with an image; "Show anyway" reveals held image; moderation "Remove image only". Respect the shared-test-DB rule (one suite at a time; targeted specs in parallel).
- **Frozen contracts stay green:** `flag_spec.rb`, moderation specs, `design_system_helper_spec.rb`.
- **Tailwind:** add any interpolated classes to `@source inline`; md5 the built bundle before/after comment-only edits; positive-control check.
- **`bin/ci` green** at the end (StandardRB, Brakeman, bundler-audit, full specs).

## 9. Slice order (for the plan)

1. **Model & storage** — attachment, columns/migration, validations, `image_display_state`, serving helper, eager-loads. (No UI.)
2. **Composer & direct upload** — dialog, `image_upload` controller, direct-upload wiring, params, attached state + alt text.
3. **Rendering** — `_hujah_image` partial on card + show.
4. **Lightbox** — controller + dialog + wiring from the shown image.
5. **Flagging** — enum extension, conditional image rows, held state, image-aware flag copy.
6. **Moderation** — `remove_image!`, notification category, queue row + action + route + turbo_stream.

Each slice: TDD (failing spec first), independent review, batched fixes, re-verify. Fable orchestrates/routes/reviews; Opus subagents implement.

## 10. Non-goals / deferred

- No image on inline or argument/reply composers.
- No server-side cropping (16:9 is a CSS display crop; original stored; lightbox shows natural).
- No multiple images, no image editing (rotate/crop UI), no EXIF stripping beyond what the storage service does.
- No API (`Api::V1`) image support in this slice (kept text-only for now).
