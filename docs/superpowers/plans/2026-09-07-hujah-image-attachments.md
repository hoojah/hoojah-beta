# Hujah Image Attachments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user attach one image to a new top-level hujah (direct upload), show it 16:9 below the claim on cards and the single page, open it in a lightbox, and make flagging + moderation image-aware.

**Architecture:** Mirror the existing `User#avatar` ActiveStorage pattern for a `has_one_attached :image` on `Hujah`, served via `rails_storage_proxy_path`. The full composer uploads in the background with `@rails/activestorage`'s `DirectUpload`, writing a blob `signed_id` into a hidden field. Rendering, lightbox, flagging (two new `Flag#subject` values, additive to the frozen `_flag_dialog`), and a new "Remove image only" moderation outcome build on existing dialog/menu/queue conventions.

**Tech Stack:** Rails 8.1, ActiveStorage (Cloudinary/Garage/Disk), Hotwire (Turbo + Stimulus over importmap, no build step), Pundit, RSpec + FactoryBot + Cuprite, Tailwind v4.

**Reference:** `docs/superpowers/specs/2026-09-07-hujah-image-attachments-design.md`. Run all commands with the `RAILS_ENV=test RUBYOPT='-W0'` prefix shown; if mise is not active, prefix with `mise exec ruby@3.4.9 --`.

---

## File map

| File | Responsibility | Action |
|---|---|---|
| `db/migrate/*_add_image_columns_to_hujahs.rb` | `image_alt`, `image_removed_at` columns | Create |
| `app/models/hujah.rb` | attachment, constants, validation, `image_display_state`, `image_held?`, `remove_image!` | Modify |
| `app/models/flag.rb` | extend `subject` enum | Modify |
| `app/models/notification.rb` | add `image_removed` category | Modify |
| `app/controllers/hujahs_controller.rb` | permit `:image`, `:image_alt`; eager-load | Modify |
| `app/controllers/flags_controller.rb` | guard image subjects need an image | Modify |
| `app/controllers/moderation_controller.rb` | `remove_image` action | Modify |
| `app/policies/moderation_policy.rb` | `remove_image?` | Modify |
| `config/routes.rb` | `remove_image` route | Modify |
| `config/importmap.rb` | pin `@rails/activestorage` | Modify |
| `app/helpers/design_system_helper.rb` | `ds_hujah_image_url` | Modify |
| `app/javascript/controllers/image_upload_controller.js` | dialog + direct upload + attached state | Create |
| `app/javascript/controllers/lightbox_controller.js` | full-screen image viewer | Create |
| `app/views/hujahs/_compose_form.html.erb` | multipart, wire button, dialog, attached state, alt field | Modify |
| `app/views/hujahs/_add_image_dialog.html.erb` | the "Add an image" dialog | Create |
| `app/views/hujahs/_hujah_image.html.erb` | shared image block (card + show), 3 states | Create |
| `app/views/hujahs/_hujah_card.html.erb` | render image below body | Modify |
| `app/views/hujahs/show.html.erb` | render image below claim | Modify |
| `app/views/hujahs/_flag_dialog.html.erb` | conditional image rows + thumbnail | Modify |
| `app/views/moderation/_flagged_hujah.html.erb` | Remove-image-only button + context | Modify |
| `app/views/moderation/remove_image.turbo_stream.erb` | queue row update | Create |
| `app/assets/tailwind/application.css` | `@source inline` additions if any | Modify |
| specs under `spec/` | model/request/system coverage | Create/Modify |

---

## Slice 1 — Model & storage

### Task 1.1: Migration for image columns

**Files:**
- Create: `db/migrate/<timestamp>_add_image_columns_to_hujahs.rb`

- [ ] **Step 1: Generate the migration**

Run: `bin/rails g migration AddImageColumnsToHujahs image_alt:string image_removed_at:datetime`

- [ ] **Step 2: Verify the migration body** is exactly (both columns nullable, no default — `strong_migrations`-safe on a populated table):

```ruby
class AddImageColumnsToHujahs < ActiveRecord::Migration[8.1]
  def change
    add_column :hujahs, :image_alt, :string
    add_column :hujahs, :image_removed_at, :datetime
  end
end
```

- [ ] **Step 3: Migrate dev + test**

Run: `bin/rails db:migrate && bin/rails db:test:prepare`
Expected: `schema.rb` gains `image_alt` and `image_removed_at` on `hujahs`.

- [ ] **Step 4: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "Slice 1 Task 1.1: add image_alt and image_removed_at to hujahs"
```

### Task 1.2: Attachment, constants, validation (TDD)

**Files:**
- Modify: `app/models/hujah.rb`
- Test: `spec/models/hujah_spec.rb`

- [ ] **Step 1: Write failing specs.** Add to `spec/models/hujah_spec.rb`. Use a 1×1 PNG fixture — create `spec/fixtures/files/test_image.png` first (`Run: printf '\x89PNG\r\n\x1a\n' > /dev/null` — instead use a real fixture: copy an existing one if present, else generate with the helper below).

Add a shared helper at the top of the file's describe block:

```ruby
def attach_image(hujah, filename: "photo.png", type: "image/png", bytes: 1.kilobyte)
  hujah.image.attach(
    io: StringIO.new("x" * bytes), filename: filename, content_type: type
  )
  hujah
end
```

Specs:

```ruby
describe "image attachment" do
  let(:hujah) { build(:hujah) }

  it "accepts a PNG under 5 MB" do
    attach_image(hujah, type: "image/png", bytes: 1.megabyte)
    expect(hujah).to be_valid
  end

  it "rejects an unsupported content type" do
    attach_image(hujah, filename: "x.heic", type: "image/heic")
    expect(hujah).not_to be_valid
    expect(hujah.errors[:image]).to include("must be a PNG, JPEG, GIF, or WebP image")
  end

  it "rejects an image over 5 MB" do
    attach_image(hujah, bytes: 6.megabytes)
    expect(hujah).not_to be_valid
    expect(hujah.errors[:image]).to include("must be smaller than 5 MB")
  end

  it "limits image_alt to 200 characters" do
    hujah.image_alt = "a" * 201
    expect(hujah).not_to be_valid
    expect(hujah.errors[:image_alt]).to be_present
  end
end
```

- [ ] **Step 2: Run, expect FAIL**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/hujah_spec.rb -e "image attachment"`
Expected: FAIL (no `image` attachment / `image_alt` unvalidated).

- [ ] **Step 3: Implement in `app/models/hujah.rb`.** Near the other `has_many`/attachment declarations add:

```ruby
has_one_attached :image

MAX_IMAGE_BYTES = 5.megabytes
ALLOWED_IMAGE_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze

validates :image_alt, length: {maximum: 200}
validate :image_is_valid_image
```

In the `private` section add (mirrors `User#avatar_is_valid_image`):

```ruby
def image_is_valid_image
  return unless image.attached?
  unless ALLOWED_IMAGE_TYPES.include?(image.blob.content_type)
    errors.add(:image, "must be a PNG, JPEG, GIF, or WebP image")
  end
  if image.blob.byte_size > MAX_IMAGE_BYTES
    errors.add(:image, "must be smaller than 5 MB")
  end
end
```

- [ ] **Step 4: Run, expect PASS**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/hujah_spec.rb -e "image attachment"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/hujah.rb spec/models/hujah_spec.rb
git commit -m "Slice 1 Task 1.2: attach image to hujah with type/size/alt validation"
```

### Task 1.3: `image_display_state` and `image_held?` (TDD)

**Files:**
- Modify: `app/models/hujah.rb`
- Test: `spec/models/hujah_spec.rb`

- [ ] **Step 1: Write failing specs:**

```ruby
describe "#image_display_state" do
  it "is :none without an attachment" do
    expect(build(:hujah).image_display_state).to eq(:none)
  end

  it "is :none when the image was removed by a moderator" do
    hujah = attach_image(create(:hujah))
    hujah.update!(image_removed_at: Time.current)
    expect(hujah.image_display_state).to eq(:none)
  end

  it "is :held when a pending image-subject flag exists" do
    hujah = attach_image(create(:hujah)); hujah.save!
    create(:flag, hujah: hujah, subject: :image_graphic) # status defaults to pending
    expect(hujah.reload.image_display_state).to eq(:held)
  end

  it "is :shown for an attached image with no image flags" do
    hujah = attach_image(create(:hujah)); hujah.save!
    expect(hujah.image_display_state).to eq(:shown)
  end
end
```

Note: this spec depends on Slice 5's enum values (`image_graphic`). Sequence Slice 5's enum change before running the `:held` example, OR stub with an existing subject. To keep Slice 1 self-contained, **write the enum extension (Task 5.1) now** if executing strictly in order is inconvenient — but the recommended order runs Task 5.1 before this example passes. Mark the `:held` example `pending` until Slice 5 if needed.

- [ ] **Step 2: Run, expect FAIL** (`image_display_state` undefined)

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/hujah_spec.rb -e "image_display_state"`

- [ ] **Step 3: Implement** in `app/models/hujah.rb` (public methods):

```ruby
IMAGE_FLAG_SUBJECTS = %i[image_graphic image_not_theirs].freeze

# Derived, per-viewer-independent visual state for the attached image.
def image_display_state
  return :none unless image.attached? && image_removed_at.nil?
  image_held? ? :held : :shown
end

# Soft-hidden while an image report is pending review. Not stored — derived so it
# clears automatically when the flag is resolved.
def image_held?
  flags.pending.where(subject: IMAGE_FLAG_SUBJECTS).exists?
end
```

- [ ] **Step 4: Run, expect PASS**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/hujah_spec.rb -e "image_display_state"`

- [ ] **Step 5: Commit**

```bash
git add app/models/hujah.rb spec/models/hujah_spec.rb
git commit -m "Slice 1 Task 1.3: derive image_display_state / image_held? on hujah"
```

### Task 1.4: Serving helper + eager-loading

**Files:**
- Modify: `app/helpers/design_system_helper.rb`
- Modify: `app/controllers/hujahs_controller.rb` (queries feeding cards)
- Test: `spec/helpers/design_system_helper_spec.rb`

- [ ] **Step 1: Write failing helper spec:**

```ruby
describe "#ds_hujah_image_url" do
  it "returns the storage proxy path for an attached image" do
    hujah = build_stubbed(:hujah)
    allow(hujah).to receive_message_chain(:image, :attached?).and_return(true)
    expect(helper.ds_hujah_image_url(hujah)).to be_present
  end
end
```

(If `receive_message_chain` is discouraged here, attach a real image on a persisted hujah and assert the path starts with `/rails/active_storage/`.)

- [ ] **Step 2: Run, expect FAIL**

- [ ] **Step 3: Implement** in `app/helpers/design_system_helper.rb`, next to `ds_avatar_url` (reuse the same proxy rationale comment):

```ruby
# Serve hujah images through the Active Storage proxy, never blob.url — presigned
# S3/Garage URLs expire in 5 min and rot in cached HTML. Same rule as ds_avatar_url.
def ds_hujah_image_url(hujah)
  rails_storage_proxy_path(hujah.image)
end
```

- [ ] **Step 4: Add eager-loading.** In `app/controllers/hujahs_controller.rb`, find the feed/index query and each query that renders `_hujah_card`; add `image_attachment: :blob` to their `includes(...)`. Example: `includes(:user, image_attachment: :blob)`. Do the same in `app/controllers/users_controller.rb` and `app/controllers/search_controller.rb` where they load hujahs for `_hujah_card`.

- [ ] **Step 5: Run helper spec + a quick prosopite check**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/helpers/design_system_helper_spec.rb`
Then after a feed request spec run, `grep -c 'N+1 queries detected' log/prosopite.log` should not increase for image loads.

- [ ] **Step 6: Commit**

```bash
git add app/helpers/design_system_helper.rb app/controllers spec/helpers
git commit -m "Slice 1 Task 1.4: proxy-path image helper + eager-load image blobs"
```

---

## Slice 2 — Composer & direct upload

### Task 2.1: Pin `@rails/activestorage`

**Files:**
- Modify: `config/importmap.rb`

- [ ] **Step 1: Pin it**

Run: `bin/importmap pin @rails/activestorage`
Expected: adds `pin "@rails/activestorage", to: "@rails--activestorage.js"` and downloads to `vendor/javascript/`.

- [ ] **Step 2: Verify** the file exists under `vendor/javascript/`. Do **not** call `ActiveStorage.start()` in `application.js` — the custom controller imports `DirectUpload` directly to avoid auto-wiring every file input.

- [ ] **Step 3: Commit**

```bash
git add config/importmap.rb vendor/javascript
git commit -m "Slice 2 Task 2.1: pin @rails/activestorage for direct upload"
```

### Task 2.2: Permit params + multipart form

**Files:**
- Modify: `app/controllers/hujahs_controller.rb`
- Modify: `app/views/hujahs/_compose_form.html.erb`
- Test: `spec/requests/hujahs_spec.rb`

- [ ] **Step 1: Write failing request spec** (uploads a blob, passes its signed_id):

```ruby
it "attaches an image supplied as a blob signed_id" do
  sign_in user
  blob = ActiveStorage::Blob.create_and_upload!(
    io: file_fixture("test_image.png").open, filename: "photo.png", content_type: "image/png"
  )
  post "/hoojah", params: {hujah: {body: "A claim long enough to pass", image: blob.signed_id, image_alt: "a train"}}
  hujah = Hujah.order(:created_at).last
  expect(hujah.image).to be_attached
  expect(hujah.image_alt).to eq("a train")
end
```

Ensure `spec/fixtures/files/test_image.png` exists (a small real PNG). If absent, add one (any valid PNG ≤ a few KB).

- [ ] **Step 2: Run, expect FAIL** (`image`/`image_alt` not permitted → not attached).

- [ ] **Step 3: Implement.** In `app/controllers/hujahs_controller.rb#compose_params` add `:image, :image_alt`:

```ruby
def compose_params
  params.require(:hujah).permit(:body, :parent_id, :vote, :visibility, :allow_debates,
    :agree_label, :neutral_label, :disagree_label, :image, :image_alt)
end
```

In `app/views/hujahs/_compose_form.html.erb` change the `form_with` to multipart and mount the upload controller. The existing `data: {controller: "composer", ...}` becomes:

```erb
data: {turbo: false, controller: "composer image-upload",
       composer_require_min_value: parent.nil?,
       image_upload_direct_url_value: rails_direct_uploads_path},
multipart: true,
```

- [ ] **Step 4: Run, expect PASS**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/hujahs_spec.rb -e "signed_id"`

- [ ] **Step 5: Commit**

```bash
git add app/controllers/hujahs_controller.rb app/views/hujahs/_compose_form.html.erb spec
git commit -m "Slice 2 Task 2.2: permit image/image_alt and make composer multipart"
```

### Task 2.3: The "Add an image" dialog partial

**Files:**
- Create: `app/views/hujahs/_add_image_dialog.html.erb`
- Modify: `app/views/hujahs/_compose_form.html.erb` (footer button + render dialog + hidden fields + attached-state container)

- [ ] **Step 1: Create `_add_image_dialog.html.erb`.** Native `<dialog>` on `dialog_controller`, same shell/copy as `_flag_dialog`. It contains the two hidden file inputs targeted by the `image-upload` controller, the idle choice rows, the error banner slot, and the uploading/failed states (toggled by the controller via `data-image-upload-target`). Full markup:

```erb
<%# "Add an image" dialog — opened by the composer footer image button. Shell/copy
    mirrors _flag_dialog (rounded-lg, shadow-lg, backdrop:bg-black/40, hairline header
    + grey X, divider rows, bare grey Cancel). Upload states are toggled by
    image_upload_controller via data-image-upload-target. %>
<dialog data-image-upload-target="dialog"
        data-action="click->dialog#backdropClose close->dialog#restoreFocus"
        aria-labelledby="dialog-title-image"
        class="rounded-lg shadow-lg p-0 w-full max-w-md backdrop:bg-black/40">
  <div class="flex items-center justify-between px-4 py-3 border-b border-gray-100">
    <h5 id="dialog-title-image" data-image-upload-target="title" class="text-lg font-medium m-0">Add an image</h5>
    <button type="button" data-action="dialog#close" aria-label="Close" class="<%= ds_button_classes(variant: :link, tone: "grey") %>">
      <%= lucide_icon("x", class: "w-5 h-5") %>
    </button>
  </div>

  <div class="p-4">
    <%# error banner (hidden by default; controller fills message + reveals) %>
    <div data-image-upload-target="error" hidden
         class="flex items-start gap-3 px-3.5 py-3 rounded-lg bg-red-50 mb-3">
      <span class="text-red-700 flex-none"><%= lucide_icon("circle-alert", class: "w-5 h-5") %></span>
      <div class="min-w-0">
        <div data-image-upload-target="errorTitle" class="text-sm font-semibold text-red-700"></div>
        <div data-image-upload-target="errorBody" class="mt-0.5 text-xs leading-snug text-red-700/85"></div>
      </div>
    </div>

    <%# IDLE: helper + two choice rows %>
    <div data-image-upload-target="chooser">
      <p class="m-0 mb-3 text-sm text-grey">JPG, PNG, WebP or GIF · up to 5 MB · one image</p>
      <div class="flex flex-col">
        <button type="button" data-action="image-upload#pickFile"
                class="flex items-center gap-3 px-4 py-3 bg-card cursor-pointer text-left border-0">
          <span class="w-10 h-10 rounded-xl bg-card-2 text-ink-2 flex items-center justify-center flex-none"><%= lucide_icon("upload", class: "w-5 h-5") %></span>
          <span class="min-w-0 flex-1"><span class="block text-sm font-semibold text-ink">Upload from device</span><span class="block mt-0.5 text-xs text-ink-2">Photos, files or a screenshot</span></span>
          <%= lucide_icon("chevron-right", class: "w-4 h-4 text-faint") %>
        </button>
        <%= render "ui/divider" %>
        <button type="button" data-action="image-upload#pickCamera"
                class="flex items-center gap-3 px-4 py-3 bg-card cursor-pointer text-left border-0">
          <span class="w-10 h-10 rounded-xl bg-card-2 text-ink-2 flex items-center justify-center flex-none"><%= lucide_icon("camera", class: "w-5 h-5") %></span>
          <span class="min-w-0 flex-1"><span class="block text-sm font-semibold text-ink">Take a photo</span><span class="block mt-0.5 text-xs text-ink-2">Opens your camera</span></span>
          <%= lucide_icon("chevron-right", class: "w-4 h-4 text-faint") %>
        </button>
      </div>
      <div class="mt-3 text-[11px] leading-snug text-faint">By attaching an image you confirm you have the right to share it. See our <a href="#" class="text-primary font-semibold">Terms</a> and <a href="#" class="text-primary font-semibold">Privacy</a>.</div>
    </div>

    <%# UPLOADING: progress %>
    <div data-image-upload-target="progress" hidden>
      <div class="relative rounded-xl overflow-hidden aspect-video bg-card-2">
        <img data-image-upload-target="progressPreview" alt="" class="w-full h-full object-cover">
        <span class="absolute inset-0 bg-white/35 pointer-events-none"></span>
      </div>
      <div class="mt-3">
        <div class="flex justify-between text-xs font-bold text-ink-2"><span data-image-upload-target="progressName"></span><span data-image-upload-target="progressPct">0%</span></div>
        <div class="mt-1.5 h-2 rounded-full bg-field overflow-hidden"><div data-image-upload-target="progressBar" class="h-full rounded-full bg-primary" style="width:0%"></div></div>
      </div>
      <div class="mt-2.5 text-[11px] leading-snug text-faint">The image is attached when this finishes — you can keep typing your hoojah meanwhile.</div>
      <div class="text-right mt-4"><button type="button" data-action="image-upload#cancelUpload" class="text-sm text-grey cursor-pointer border-0 bg-transparent">Cancel upload</button></div>
    </div>

    <%# FAILED (network) %>
    <div data-image-upload-target="failed" hidden>
      <div class="relative rounded-xl border border-dashed border-red-700 aspect-video bg-card flex flex-col items-center justify-center gap-2.5">
        <span class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-red-50 text-red-700 text-xs font-bold"><%= lucide_icon("circle-alert", class: "w-3.5 h-3.5") %> Upload didn't finish</span>
        <div data-image-upload-target="failedName" class="text-xs text-faint"></div>
      </div>
      <div class="flex gap-2 mt-3">
        <button type="button" data-action="image-upload#retry" class="<%= ds_button_classes(tone: "primary", size: :sm) %>">Retry</button>
        <button type="button" data-action="image-upload#pickFile" class="<%= ds_button_classes(tone: "grey", size: :sm) %>">Choose another</button>
      </div>
    </div>

    <div class="text-right mt-4"><button type="button" data-action="dialog#close" class="text-sm text-grey cursor-pointer border-0 bg-transparent">Cancel</button></div>
  </div>

  <%# hidden file inputs (device + camera) %>
  <input type="file" data-image-upload-target="fileInput" data-action="image-upload#fileChosen"
         accept="image/png,image/jpeg,image/gif,image/webp" class="hidden">
  <input type="file" data-image-upload-target="cameraInput" data-action="image-upload#fileChosen"
         accept="image/*" capture="environment" class="hidden">
</dialog>
```

Wrap the dialog + trigger under a single `dialog` controller: put `data-controller="dialog"` on a wrapper, OR (preferred, since the composer form already has `image-upload`) mount `dialog` on the `<dialog>`'s parent and keep `image-upload` on the form. Simplest: wrap the `<dialog>` in `<div data-controller="dialog">` and reference `dialog` for open/close, while `image-upload` (on the form) reaches the dialog via a target. To keep both controllers coordinated, mount **both** `dialog` and `image-upload` on the same wrapper `<div>` that also holds the `<dialog>` and the hidden `hujah[image]` field.

- [ ] **Step 2: Wire the footer button + hidden field + attached container in `_compose_form.html.erb`.**

Replace the inert footer button (top-level only) with:
```erb
<button type="button" aria-label="Add image" data-action="image-upload#openDialog"
        data-image-upload-target="triggerButton"
        class="w-10 h-10 rounded-xl bg-card-2 flex items-center justify-center text-ink-2">
  <%= lucide_icon("image", class: "w-5 h-5") %>
</button>
```

Add the hidden attachment field inside the form (value set by the controller on upload success):
```erb
<%= f.hidden_field :image, data: {image_upload_target: "signedId"} %>
```

Add the attached-state container in `<main>`, right after the body textarea block:
```erb
<div data-image-upload-target="attached" hidden class="mt-4">
  <div class="relative rounded-2xl overflow-hidden aspect-video bg-card-2">
    <img data-image-upload-target="attachedPreview" alt="" class="w-full h-full object-cover">
    <button type="button" data-action="image-upload#remove" aria-label="Remove image"
            class="absolute top-2 right-2 w-8 h-8 rounded-full bg-black/60 text-white flex items-center justify-center"><%= lucide_icon("x", class: "w-4 h-4") %></button>
    <span class="absolute left-2 bottom-2 px-2 py-1 rounded-full bg-black/60 text-white text-[11px] font-extrabold tracking-wide">ALT</span>
    <span data-image-upload-target="attachedMeta" class="absolute right-2 bottom-2 px-2 py-1 rounded-full bg-black/60 text-white text-[11px] font-bold"></span>
  </div>
  <div class="mt-2 flex items-start gap-2 bg-card border border-hairline rounded-xl px-3 py-2.5"
       data-controller="char-counter" data-char-counter-max-value="200">
    <%= f.text_field :image_alt, placeholder: "Describe the image…",
        data: {char_counter_target: "input"},
        class: "flex-1 text-sm leading-snug text-ink bg-transparent border-0 outline-none" %>
    <span data-char-counter-target="count" class="flex-none text-xs text-faint font-semibold">0/200</span>
  </div>
  <div class="mt-1.5 text-[11px] leading-snug text-faint">Optional — describe the image for people who can't see it.</div>
</div>
```

Render the dialog once inside the form wrapper (top-level only): `<%= render "hujahs/add_image_dialog" if parent.nil? %>`.

Confirm `char_counter_controller.js` targets are `input` + `count` and value `max`; if the existing controller uses different names, match them (check the controller file).

- [ ] **Step 3: Commit** (no test yet — system spec in 2.5)

```bash
git add app/views/hujahs/_add_image_dialog.html.erb app/views/hujahs/_compose_form.html.erb
git commit -m "Slice 2 Task 2.3: add-an-image dialog + attached state markup"
```

### Task 2.4: `image_upload` Stimulus controller

**Files:**
- Create: `app/javascript/controllers/image_upload_controller.js`

- [ ] **Step 1: Implement the controller.** Uses `DirectUpload` directly (no `ActiveStorage.start()`), validates client-side, drives progress, writes signed_id.

```js
import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"

const ALLOWED = ["image/png", "image/jpeg", "image/gif", "image/webp"]
const MAX_BYTES = 5 * 1024 * 1024

// Wires the composer's "Add image" flow: opens the dialog, validates the chosen
// file, direct-uploads it in the background, and writes the blob signed_id into the
// hidden hujah[image] field. Post stays disabled while an upload is in flight.
export default class extends Controller {
  static targets = [
    "dialog", "title", "chooser", "error", "errorTitle", "errorBody",
    "progress", "progressPreview", "progressName", "progressPct", "progressBar",
    "failed", "failedName", "fileInput", "cameraInput", "signedId",
    "attached", "attachedPreview", "attachedMeta", "triggerButton"
  ]
  static values = { directUrl: String }

  connect() { this.upload = null; this.lastFile = null }

  openDialog() { this.resetToChooser(); this.dialogTarget.showModal() }
  pickFile() { this.fileInputTarget.click() }
  pickCamera() { this.cameraInputTarget.click() }

  fileChosen(event) {
    const file = event.target.files[0]
    event.target.value = "" // allow re-choosing the same file
    if (!file) return
    this.lastFile = file
    const err = this.validate(file)
    if (err) return this.showError(err.title, err.body)
    this.startUpload(file)
  }

  validate(file) {
    if (!ALLOWED.includes(file.type)) {
      const ext = (file.name.split(".").pop() || "file").toLowerCase()
      return { title: `We can't attach a .${ext} file.`, body: "Export it as JPG or PNG, then try again." }
    }
    if (file.size > MAX_BYTES) {
      const mb = (file.size / 1024 / 1024).toFixed(1)
      return { title: `That image is ${mb} MB — the limit is 5 MB.`, body: "Try a smaller one, or screenshot it first." }
    }
    return null
  }

  startUpload(file) {
    this.showProgress(file)
    const preview = URL.createObjectURL(file)
    this.progressPreviewTarget.src = preview
    this.setPostDisabled(true)

    this.upload = new DirectUpload(file, this.directUrlValue, {
      directUploadWillStoreFileWithXHR: (xhr) => {
        xhr.upload.addEventListener("progress", (e) => {
          if (!e.lengthComputable) return
          const pct = Math.round((e.loaded / e.total) * 100)
          this.progressPctTarget.textContent = `${pct}%`
          this.progressBarTarget.style.width = `${pct}%`
        })
      }
    })

    this.upload.create((error, blob) => {
      this.upload = null
      if (error) return this.showFailed(file)
      this.signedIdTarget.value = blob.signed_id
      this.showAttached(file, preview, blob)
      this.setPostDisabled(false)
      this.dialogTarget.close()
    })
  }

  cancelUpload() { this.upload = null; this.setPostDisabled(false); this.resetToChooser(); this.dialogTarget.close() }
  retry() { if (this.lastFile) this.startUpload(this.lastFile) }

  remove() {
    this.signedIdTarget.value = ""
    this.attachedTarget.hidden = true
    this.attachedPreviewTarget.removeAttribute("src")
    this.triggerButtonTarget.classList.remove("bg-primary-soft", "text-primary")
    this.triggerButtonTarget.classList.add("bg-card-2", "text-ink-2")
  }

  // --- view state helpers ---
  resetToChooser() {
    this.errorTarget.hidden = true
    this.progressTarget.hidden = true
    this.failedTarget.hidden = true
    this.chooserTarget.hidden = false
    this.titleTarget.textContent = "Add an image"
  }
  showError(title, body) {
    this.resetToChooser()
    this.errorTitleTarget.textContent = title
    this.errorBodyTarget.textContent = body
    this.errorTarget.hidden = false
  }
  showProgress(file) {
    this.chooserTarget.hidden = true
    this.errorTarget.hidden = true
    this.failedTarget.hidden = true
    this.titleTarget.textContent = "Adding your image"
    this.progressNameTarget.textContent = `${file.name} · ${(file.size / 1024 / 1024).toFixed(1)} MB`
    this.progressPctTarget.textContent = "0%"
    this.progressBarTarget.style.width = "0%"
    this.progressTarget.hidden = false
  }
  showFailed(file) {
    this.setPostDisabled(false)
    this.progressTarget.hidden = true
    this.failedNameTarget.textContent = `${file.name} · ${(file.size / 1024 / 1024).toFixed(1)} MB · check your connection`
    this.failedTarget.hidden = false
  }
  showAttached(file, preview, blob) {
    this.attachedPreviewTarget.src = preview
    this.attachedMetaTarget.textContent = `${(file.size / 1024 / 1024).toFixed(1)} MB · 16:9 crop`
    this.attachedTarget.hidden = false
    this.triggerButtonTarget.classList.remove("bg-card-2", "text-ink-2")
    this.triggerButtonTarget.classList.add("bg-primary-soft", "text-primary")
  }
  setPostDisabled(disabled) {
    const post = this.element.querySelector('[data-composer-target="post"]')
    if (post) { post.disabled = disabled; post.classList.toggle("opacity-50", disabled) }
  }
  teardown() { if (this.hasDialogTarget && this.dialogTarget.open) this.dialogTarget.close() }
}
```

Note the `data-controller` on the form must include both `composer` and `image-upload` (Task 2.2). The `dialog` open/close here is done directly on `dialogTarget` (showModal/close) rather than delegating to `dialog_controller`, so the dialog does NOT need a separate `dialog` controller — but keep `data-action="click->dialog#backdropClose"` only if a `dialog` controller is present; otherwise change the dialog's backdrop handling to an `image-upload` action. **Decision: drop the `dialog#` actions from `_add_image_dialog` and handle Esc/backdrop natively** (native `<dialog>` closes on Esc automatically; add `data-action="click->image-upload#backdropClose"` and implement `backdropClose(e){ if (e.target === this.dialogTarget) this.dialogTarget.close() }`). Update Task 2.3 markup accordingly.

- [ ] **Step 2: Add `@source inline` safelist entry** in `app/assets/tailwind/application.css` for the interpolated toggle classes used above so Tailwind emits them even though they only appear in JS strings:

```css
@source inline("bg-primary-soft text-primary bg-card-2 text-ink-2 opacity-50");
```

(Most already exist via other usages — add only the ones not already present; verify with an md5 check per CLAUDE.md.)

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/image_upload_controller.js app/assets/tailwind/application.css app/views/hujahs/_add_image_dialog.html.erb
git commit -m "Slice 2 Task 2.4: image_upload Stimulus controller (direct upload + states)"
```

### Task 2.5: Composer system spec

**Files:**
- Create: `spec/system/hujah_image_compose_spec.rb`

- [ ] **Step 1: Write the system spec** (`js: true`, Cuprite). Direct upload hits the `:test` disk service, so a real `attach_file` works end-to-end in headless Chrome:

```ruby
require "rails_helper"

RSpec.describe "Attaching an image to a new hujah", :js do
  let(:user) { create(:user) }
  before { sign_in user }

  it "attaches an image via the dialog and posts the hujah" do
    visit new_hujah_path
    find('textarea').set("LRT3 will cut Klang Valley traffic more than any highway.")
    click_button "Add image"
    expect(page).to have_text("up to 5 MB")
    # the device file input
    attach_file(Rails.root.join("spec/fixtures/files/test_image.png"), make_visible: true)
    expect(page).to have_css('[data-image-upload-target="attached"]:not([hidden])', wait: 10)
    fill_in "hujah[image_alt]", with: "LRT3 train at Bandar Utama"
    click_button "Post"
    expect(Hujah.order(:created_at).last.image).to be_attached
  end
end
```

- [ ] **Step 2: Run, iterate to green**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/system/hujah_image_compose_spec.rb`
Expected: PASS (may need selector tweaks — adjust to real DOM).

- [ ] **Step 3: Commit**

```bash
git add spec/system/hujah_image_compose_spec.rb
git commit -m "Slice 2 Task 2.5: system spec for composer image upload"
```

---

## Slice 3 — Rendering (feed card + single page)

### Task 3.1: `_hujah_image` partial (TDD via view/system)

**Files:**
- Create: `app/views/hujahs/_hujah_image.html.erb`
- Modify: `app/views/hujahs/_hujah_card.html.erb`
- Modify: `app/views/hujahs/show.html.erb`
- Test: `spec/system/hujah_image_display_spec.rb`

- [ ] **Step 1: Write the failing system spec:**

```ruby
require "rails_helper"

RSpec.describe "Hujah image display", :js do
  let(:hujah) do
    h = create(:hujah, image_alt: "a train")
    h.image.attach(io: Rails.root.join("spec/fixtures/files/test_image.png").open, filename: "t.png", content_type: "image/png")
    h
  end

  it "shows the image on the single page and opens the lightbox on tap" do
    visit hujah_path(hujah.slug)
    expect(page).to have_css('img[alt="a train"]')
  end

  it "hides the image behind a held state when an image flag is pending" do
    create(:flag, hujah: hujah, subject: :image_graphic)
    visit hujah_path(hujah.slug)
    expect(page).to have_text("Image hidden while we review a report")
    expect(page).to have_button("Show anyway")
  end
end
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Create `_hujah_image.html.erb`** (branches on `hujah.image_display_state`; `context` local is `:card` or `:show`):

```erb
<%# Shared hujah image block. locals: hujah, context (:card | :show). One image,
    16:9 crop below the claim; tap opens the lightbox. Held/removed states per spec. %>
<% case hujah.image_display_state
   when :shown %>
  <div class="mt-3 rounded-2xl overflow-hidden aspect-video bg-card-2">
    <img src="<%= ds_hujah_image_url(hujah) %>"
         alt="<%= hujah.image_alt.presence || "Image attached to this hoojah" %>"
         loading="lazy"
         class="w-full h-full object-cover cursor-zoom-in"
         data-controller="lightbox"
         data-action="click->lightbox#open"
         data-lightbox-src-value="<%= ds_hujah_image_url(hujah) %>"
         data-lightbox-alt-value="<%= hujah.image_alt %>"
         data-lightbox-byline-value="@<%= hujah.user.username %> · <%= hujah.created_at.strftime("%b %-d") %>">
  </div>
<% when :held %>
  <div class="mt-3 rounded-2xl aspect-video bg-card-2 border border-hairline flex flex-col items-center justify-center gap-2 text-center px-4"
       data-controller="image-reveal">
    <div data-image-reveal-target="veil">
      <div class="text-sm font-semibold text-ink-2">Image hidden while we review a report</div>
      <div class="mt-1 text-xs text-faint">The claim stays votable. Only the image is held.</div>
      <button type="button" data-action="image-reveal#show" class="mt-2 <%= ds_button_classes(tone: "grey", size: :sm) %>">Show anyway</button>
    </div>
    <img data-image-reveal-target="image" hidden src="<%= ds_hujah_image_url(hujah) %>"
         alt="<%= hujah.image_alt %>" class="w-full h-full object-cover rounded-2xl">
  </div>
<% end %>
```

For `:none`, nothing renders (no `else`).

- [ ] **Step 4: Add a tiny `image_reveal` controller** `app/javascript/controllers/image_reveal_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"
// Per-viewer reveal of a held image. Nothing persists — refresh re-hides it.
export default class extends Controller {
  static targets = ["veil", "image"]
  show() { this.veilTarget.hidden = true; this.imageTarget.hidden = false }
}
```

- [ ] **Step 5: Render the partial.** In `_hujah_card.html.erb`, immediately after the body div, add `<%= render "hujahs/hujah_image", hujah: hujah, context: :card %>`. In `show.html.erb`, immediately after the `<h1>` claim, add `<%= render "hujahs/hujah_image", hujah: @hujah, context: :show %>`.

- [ ] **Step 6: Run, expect PASS** (first example — second needs Slice 5's enum; mark pending if running strictly in order).

- [ ] **Step 7: Commit**

```bash
git add app/views/hujahs/_hujah_image.html.erb app/views/hujahs/_hujah_card.html.erb app/views/hujahs/show.html.erb app/javascript/controllers/image_reveal_controller.js spec/system/hujah_image_display_spec.rb
git commit -m "Slice 3 Task 3.1: render hujah image (shown/held) on card + single page"
```

---

## Slice 4 — Lightbox

### Task 4.1: `lightbox` controller + system spec

**Files:**
- Create: `app/javascript/controllers/lightbox_controller.js`
- Modify: `app/assets/tailwind/application.css` (safelist)
- Test: extend `spec/system/hujah_image_display_spec.rb`

- [ ] **Step 1: Add a failing example:**

```ruby
it "opens and closes the lightbox" do
  visit hujah_path(hujah.slug)
  find('img[alt="a train"]').click
  expect(page).to have_css('[data-lightbox-target="root"]:not([hidden])')
  expect(page).to have_text("Pinch to zoom")
  find('[data-lightbox-target="root"]').send_keys(:escape)
  expect(page).to have_css('[data-lightbox-target="root"][hidden]', wait: 5)
end
```

- [ ] **Step 2: Implement `lightbox_controller.js`.** Builds a full-screen `<dialog>` lazily on first open, natural aspect, alt caption, close on backdrop/Esc/swipe-down.

```js
import { Controller } from "@hotwired/stimulus"

// Full-screen image viewer opened from a hujah image. Natural aspect, alt caption,
// @user · date byline. Closes on backdrop click, Esc, or swipe-down. A single
// <dialog> is created per image element on first open and reused.
export default class extends Controller {
  static values = { src: String, alt: String, byline: String }

  open(event) {
    event.preventDefault()
    if (!this.dialog) this.build()
    this.dialog.showModal()
  }

  build() {
    const d = document.createElement("dialog")
    d.setAttribute("data-lightbox-target", "root")
    d.className = "p-0 m-0 w-screen h-screen max-w-none max-h-none bg-black/90 backdrop:bg-black/90"
    d.innerHTML = `
      <div class="w-full h-full flex flex-col text-white" data-role="wrap">
        <div class="flex items-center justify-between px-4 py-3 text-sm">
          <span>${this.escape(this.bylineValue)}</span>
          <button type="button" data-role="close" aria-label="Close" class="p-1">✕</button>
        </div>
        <div class="flex-1 flex items-center justify-center overflow-auto px-4">
          <img src="${this.escape(this.srcValue)}" alt="${this.escape(this.altValue)}" class="max-w-full max-h-full object-contain">
        </div>
        <div class="px-4 py-3 text-center text-xs text-white/70">
          ${this.altValue ? `<div class="mb-1 text-white/90">${this.escape(this.altValue)}</div>` : ""}
          Pinch to zoom · swipe down to close
        </div>
      </div>`
    d.querySelector('[data-role="close"]').addEventListener("click", () => d.close())
    d.addEventListener("click", (e) => { if (e.target === d) d.close() })
    this.bindSwipeDown(d)
    document.body.appendChild(d)
    this.dialog = d
  }

  bindSwipeDown(d) {
    let startY = null
    const wrap = d.querySelector('[data-role="wrap"]')
    wrap.addEventListener("touchstart", (e) => { startY = e.touches[0].clientY }, { passive: true })
    wrap.addEventListener("touchend", (e) => {
      if (startY !== null && e.changedTouches[0].clientY - startY > 80) d.close()
      startY = null
    }, { passive: true })
  }

  escape(s) { return String(s || "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])) }

  teardown() { if (this.dialog) { if (this.dialog.open) this.dialog.close(); this.dialog.remove(); this.dialog = null } }
}
```

- [ ] **Step 3: Safelist** the lightbox's static classes in `application.css` (they appear only in a JS template string, so the ERB scanner won't see them):

```css
@source inline("w-screen h-screen max-w-none max-h-none bg-black/90 object-contain text-white/70 text-white/90");
```

- [ ] **Step 4: Run, iterate to green.**

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/system/hujah_image_display_spec.rb -e "lightbox"`

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/lightbox_controller.js app/assets/tailwind/application.css spec/system/hujah_image_display_spec.rb
git commit -m "Slice 4 Task 4.1: image lightbox controller + spec"
```

---

## Slice 5 — Flagging (image-aware)

### Task 5.1: Extend `Flag#subject` enum (TDD)

**Files:**
- Modify: `app/models/flag.rb`
- Test: `spec/models/flag_spec.rb`

- [ ] **Step 1: Failing spec:**

```ruby
it "supports image subjects" do
  expect(Flag.subjects.keys).to include("image_graphic", "image_not_theirs")
end
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement** — extend the enum in `app/models/flag.rb`:

```ruby
enum :subject, {spam: 0, abusive: 1, irrelevant: 2, image_graphic: 3, image_not_theirs: 4}
```

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add app/models/flag.rb spec/models/flag_spec.rb
git commit -m "Slice 5 Task 5.1: add image_graphic/image_not_theirs flag subjects"
```

### Task 5.2: Guard image subjects require an image (TDD)

**Files:**
- Modify: `app/controllers/flags_controller.rb`
- Test: `spec/requests/flags_spec.rb`

- [ ] **Step 1: Failing request spec:**

```ruby
it "rejects an image subject when the hujah has no image" do
  sign_in create(:user)
  hujah = create(:hujah) # no image
  post hujah_flags_path(hujah.slug), params: {flag: {subject: "image_graphic"}}
  expect(hujah.flags).to be_empty
end
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement** in `flags_controller.rb#create` — after loading `@hujah`, before saving:

```ruby
if Hujah::IMAGE_FLAG_SUBJECTS.map(&:to_s).include?(flag_params[:subject]) &&
    !(@hujah.image.attached? && @hujah.image_removed_at.nil?)
  return head :unprocessable_content
end
```

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add app/controllers/flags_controller.rb spec/requests/flags_spec.rb
git commit -m "Slice 5 Task 5.2: reject image flag subjects when no image present"
```

### Task 5.3: Conditional image rows in `_flag_dialog` (frozen-safe)

**Files:**
- Modify: `app/views/hujahs/_flag_dialog.html.erb`
- Test: `spec/system/flag_spec.rb` (must stay green) + new example

- [ ] **Step 1: Confirm the frozen contract.** Run the existing flag system spec first and keep it green throughout:

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/system/flag_spec.rb`
Expected: PASS (baseline).

- [ ] **Step 2: Add a new example** (image rows appear only with an image):

```ruby
it "offers image reasons only when the hoojah has an image", :js do
  hujah = create(:hujah)
  hujah.image.attach(io: Rails.root.join("spec/fixtures/files/test_image.png").open, filename: "t.png", content_type: "image/png")
  sign_in hujah.user
  visit hujah_path(hujah.slug)
  # open the More-actions menu then the flag dialog (match existing spec's steps)
  # ...open flag dialog...
  expect(page).to have_button("The image is graphic or explicit")
  expect(page).to have_button("The image isn't theirs to post")
end
```

- [ ] **Step 3: Implement** — in `_flag_dialog.html.erb`, **without touching the existing three rows, dom_ids, data-*, or copy**, add after the `irrelevant` row (and its trailing divider), guarded by image presence:

```erb
<% if hujah.image.attached? && hujah.image_removed_at.nil? %>
  <%= render "ui/divider" %>
  <button type="submit" name="flag[subject]" value="image_graphic"
          class="text-left px-4 py-3 hover:bg-gray-50 border-0 bg-card cursor-pointer">
    The image is graphic or explicit
  </button>
  <%= render "ui/divider" %>
  <button type="submit" name="flag[subject]" value="image_not_theirs"
          class="text-left px-4 py-3 hover:bg-gray-50 border-0 bg-card cursor-pointer">
    The image isn't theirs to post
  </button>
<% end %>
```

Also add, just under the "Why are you flagging this hoojah?" paragraph, the image-context row (only when image present):

```erb
<% if hujah.image.attached? && hujah.image_removed_at.nil? %>
  <div class="flex items-center gap-2.5 p-2 rounded-lg bg-card-2 mb-3">
    <div class="w-16 h-9 rounded-md overflow-hidden flex-none bg-field">
      <img src="<%= ds_hujah_image_url(hujah) %>" alt="" class="w-full h-full object-cover">
    </div>
    <div class="min-w-0 text-xs leading-snug text-ink-2">@<%= hujah.user.username %> · the claim and its image are reviewed together.</div>
  </div>
<% end %>
```

- [ ] **Step 4: Run both** — existing frozen spec + the new example:

Run: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/system/flag_spec.rb`
Expected: PASS (both).

- [ ] **Step 5: Commit**

```bash
git add app/views/hujahs/_flag_dialog.html.erb spec/system/flag_spec.rb
git commit -m "Slice 5 Task 5.3: image-aware flag reasons + context (frozen-safe)"
```

---

## Slice 6 — Moderation ("Remove image only")

### Task 6.1: `image_removed` notification category (TDD)

**Files:**
- Modify: `app/models/notification.rb`
- Test: `spec/models/notification_spec.rb`

- [ ] **Step 1: Failing spec:**

```ruby
it "supports the image_removed category" do
  expect(Notification.categories.keys).to include("image_removed")
end
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement** — add `image_removed` to the `category` enum in `app/models/notification.rb` (append with the next integer; do NOT renumber existing values). Check the current enum and add e.g. `image_removed: <next_int>`. Mirror `moderation_removed`'s rendering wherever notification categories map to copy/partials (grep for `moderation_removed` and add an `image_removed` branch: e.g. "A moderator removed the image from your hoojah.").

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add app/models/notification.rb spec/models/notification_spec.rb app/views/notifications
git commit -m "Slice 6 Task 6.1: image_removed notification category"
```

### Task 6.2: `Hujah#remove_image!` (TDD)

**Files:**
- Modify: `app/models/hujah.rb`
- Test: `spec/models/hujah_spec.rb`

- [ ] **Step 1: Failing spec:**

```ruby
describe "#remove_image!" do
  let(:moderator) { create(:user, role: :moderator) }
  let(:hujah) do
    h = create(:hujah)
    h.image.attach(io: Rails.root.join("spec/fixtures/files/test_image.png").open, filename: "t.png", content_type: "image/png")
    h
  end

  it "detaches the image, keeps the claim active, resolves image flags, notifies the author" do
    create(:flag, hujah: hujah, subject: :image_graphic)
    expect { hujah.remove_image!(by: moderator) }.to change { Notification.where(category: :image_removed).count }.by(1)
    hujah.reload
    expect(hujah.image_removed_at).to be_present
    expect(hujah.moderation_status).to eq("active")
    expect(hujah.flags.where(subject: Hujah::IMAGE_FLAG_SUBJECTS).all?(&:actioned?)).to be(true)
  end

  it "is idempotent" do
    hujah.remove_image!(by: moderator)
    expect { hujah.remove_image!(by: moderator) }.not_to change { Notification.count }
  end
end
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement** in `app/models/hujah.rb` (mirror `remove!`'s structure — check its exact flag-resolution code and notification call, and follow it):

```ruby
# Moderator outcome: remove only the attached image; the claim stays votable/active.
def remove_image!(by:)
  return if image_removed_at.present?
  transaction do
    update!(image_removed_at: Time.current)
    flags.pending.where(subject: IMAGE_FLAG_SUBJECTS).find_each { |f| f.resolve!(by: by, as: :actioned) }
    image.purge_later
    Notification.create!(user_id: user_id, category: :image_removed, hujah_id: id)
  end
end
```

Match the exact `Notification.create!` argument shape used by `remove!` (it may use different attrs — copy them).

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add app/models/hujah.rb spec/models/hujah_spec.rb
git commit -m "Slice 6 Task 6.2: Hujah#remove_image! (image-only moderation outcome)"
```

### Task 6.3: Route, policy, controller action (TDD)

**Files:**
- Modify: `config/routes.rb`, `app/policies/moderation_policy.rb`, `app/controllers/moderation_controller.rb`
- Create: `app/views/moderation/remove_image.turbo_stream.erb`
- Test: `spec/requests/moderation_spec.rb`

- [ ] **Step 1: Failing request spec:**

```ruby
it "removes only the image and keeps the hujah" do
  moderator = create(:user, role: :moderator)
  hujah = create(:hujah)
  hujah.image.attach(io: Rails.root.join("spec/fixtures/files/test_image.png").open, filename: "t.png", content_type: "image/png")
  create(:flag, hujah: hujah, subject: :image_graphic)
  sign_in moderator
  delete remove_image_moderation_path(hujah.slug)
  hujah.reload
  expect(hujah.image_removed_at).to be_present
  expect(hujah.moderation_status).to eq("active")
end

it "forbids non-moderators" do
  hujah = create(:hujah)
  sign_in create(:user)
  delete remove_image_moderation_path(hujah.slug)
  expect(response).to have_http_status(:found).or have_http_status(:forbidden)
end
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement.**

Route in `config/routes.rb` (next to the other moderation routes):
```ruby
delete "/moderation/:slug/image", to: "moderation#remove_image", as: :remove_image_moderation
```

Policy in `app/policies/moderation_policy.rb` — add (mirror the others):
```ruby
def remove_image? = !!user&.can_moderate?
```

Controller in `app/controllers/moderation_controller.rb` (mirror `remove`):
```ruby
def remove_image
  @hujah = Hujah.friendly.find(params[:slug])
  authorize :moderation, :remove_image?
  @hujah.remove_image!(by: current_user)
  respond_to do |format|
    format.turbo_stream
    format.html { redirect_to moderation_path, notice: "Image removed." }
  end
end
```

`remove_image.turbo_stream.erb` — if the hujah still has non-image pending flags keep the row (replace it), else remove it; always refresh the pending-count chip. Mirror `remove.turbo_stream.erb`'s structure:
```erb
<% if @hujah.flags.pending.where.not(subject: Hujah::IMAGE_FLAG_SUBJECTS).exists? %>
  <%= turbo_stream.replace dom_id(@hujah, :moderation_item) do %>
    <%= render "moderation/flagged_hujah", hujah: @hujah %>
  <% end %>
<% else %>
  <%= turbo_stream.remove dom_id(@hujah, :moderation_item) %>
<% end %>
<%= turbo_stream.replace "moderation-pending-count" do %>
  <%# copy the exact chip markup from remove.turbo_stream.erb %>
<% end %>
```

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add config/routes.rb app/policies/moderation_policy.rb app/controllers/moderation_controller.rb app/views/moderation/remove_image.turbo_stream.erb spec/requests/moderation_spec.rb
git commit -m "Slice 6 Task 6.3: remove_image moderation route/policy/action"
```

### Task 6.4: Queue row button + context

**Files:**
- Modify: `app/views/moderation/_flagged_hujah.html.erb`
- Test: `spec/system/moderation_spec.rb` (or request-level assertion on the button)

- [ ] **Step 1: Failing spec** (button present only when the hujah has image flags):

```ruby
it "offers Remove image only for an image-flagged hujah", :js do
  moderator = create(:user, role: :moderator)
  hujah = create(:hujah)
  hujah.image.attach(io: Rails.root.join("spec/fixtures/files/test_image.png").open, filename: "t.png", content_type: "image/png")
  create(:flag, hujah: hujah, subject: :image_graphic)
  sign_in moderator
  visit moderation_path
  expect(page).to have_button("Remove image only")
end
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement** — in `_flagged_hujah.html.erb`, without changing the frozen `dom_id(hujah, :moderation_item)` wrapper, add (when the hujah has image flags) a thumbnail/context line and a `Remove image only` `button_to`:

```erb
<% if hujah.image.attached? && hujah.image_removed_at.nil? && hujah.flags.pending.where(subject: Hujah::IMAGE_FLAG_SUBJECTS).exists? %>
  <%= button_to "Remove image only", remove_image_moderation_path(hujah.slug), method: :delete,
        class: ds_button_classes(tone: "disagree", size: :sm), form: {data: {turbo_stream: true}} %>
<% end %>
```

Place it alongside the existing Dismiss / Warn / Remove buttons. Match their `button_to` form conventions exactly.

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add app/views/moderation/_flagged_hujah.html.erb spec/system/moderation_spec.rb
git commit -m "Slice 6 Task 6.4: Remove-image-only button in moderation queue"
```

---

## Final verification

- [ ] **Run the full gate.** `bin/ci` (or `bin/ci --skip-system-specs` then `bin/ci --only-system-specs` given the shared test DB). Expected: green.
- [ ] **StandardRB / Brakeman / bundler-audit** are inside `bin/ci`; if run separately, all clean.
- [ ] **Tailwind md5 sanity** on any comment-only CSS edits (per CLAUDE.md).
- [ ] **Prosopite:** `grep -c 'N+1 queries detected' log/prosopite.log` did not rise due to image loads.
- [ ] **Manual smoke** (optional): `bin/dev`, post a hujah with an image, view feed/single, open lightbox, flag the image, remove image in `/moderation`.

## Self-review notes (author)

- Spec coverage: §2 model → Slice 1; §3 composer/direct-upload → Slice 2; §4 rendering → Slice 3; §5 lightbox → Slice 4; §6 flagging → Slice 5; §7 moderation → Slice 6; §8 testing woven through. Covered.
- Cross-slice dependency: `image_display_state`'s `:held` branch and the display "held" example depend on Slice 5's enum. Flagged in Task 1.3 / 3.1 — run Task 5.1 early or mark those examples `pending` until Slice 5. Recommended execution order: 1.1, 1.2, 1.4, **5.1**, 1.3, then 2.x, 3.x, 4.x, 5.2–5.3, 6.x.
- `IMAGE_FLAG_SUBJECTS` defined in Task 1.3 (model) and referenced in 5.2/6.2/6.3 — consistent name.
- Notification `create!` arg shape and `remove!` flag-resolution: plan says "match the existing code" rather than guessing — implementer must read `remove!` first.
