# Slice 3 — Custom Stance Labels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let authors who have posted 10+ default top-level hoojahs rename Agree/Neutral/Disagree inline on the composer, storing three immutable per-field labels that render only at that top-level record's own vote/breakdown/share surfaces.

**Architecture:** Three nullable string columns (`agree_label`/`neutral_label`/`disagree_label`) on `hujahs`, normalised-and-eligibility-coerced in a `before_validation on: :create` and frozen with `attr_readonly`. A `Hujah#stance_label(position)` accessor resolves custom-or-default per stance position (children always default); the existing colour/icon maps stay keyed to positions 1/2/3, so **no new Tailwind classes are produced** and the `@source inline(...)` safelist is untouched. A small `stance_labels_controller.js` turns the composer's three preview words into inline inputs syncing hidden form fields, shown only to eligible authors; the server re-coerces on create so a tampered POST cannot bypass the gate.

**Tech Stack:** Rails 8.1, RSpec, FactoryBot, Pundit, Hotwire/Stimulus (importmap), Tailwind v4

---

## File Structure

**Created**
- `db/migrate/<ts>_add_stance_labels_to_hujahs.rb` — adds the three nullable string columns.
- `app/javascript/controllers/stance_labels_controller.js` — inline click-to-edit for the composer's three stance words (auto-registered by `eagerLoadControllersFrom`).
- `spec/system/custom_stance_labels_spec.rb` — Cuprite (`js: true`) inline-edit interaction + ineligible-user negative.

**Modified**
- `app/models/hujah.rb` — `STANCE_LABEL_COLUMNS`, `CUSTOM_LABEL_MAX`, `stance_label`, `custom_stances?`, `default_hujah?`, normalisation + eligibility `before_validation` callbacks, `attr_readonly`, and the `award_authoring_badge` custom-badge branch.
- `app/models/user.rb` — `can_customize_stances?`.
- `app/models/badge.rb` — `first_custom_hoojah` registry entry.
- `app/controllers/hujahs_controller.rb` — permit the three label params in `compose_params`.
- `app/views/hujahs/_compose_form.html.erb` — eligible vs ineligible "How people will weigh in" block.
- `app/views/hujahs/_vote_bars.html.erb` — percent-legend + button text via `stance_label`.
- `app/views/hujahs/_vote_hero.html.erb` — button text + aria via `stance_label`.
- `app/views/hujahs/_card_menu.html.erb` — share text via `stance_label`.
- `app/views/hujahs/_share_menu.html.erb` — share text via `stance_label`.
- `spec/factories/hujahs.rb` — `:custom_stances` trait (test convenience).
- `spec/models/hujah_spec.rb`, `spec/models/user_spec.rb`, `spec/requests/compose_spec.rb`, `spec/models/badge_award_spec.rb` (or existing badge spec) — new examples.

**Definitions fixed up-front (used throughout):**
- A post is **custom** when any of the three label columns is present; **default** otherwise.
- `can_customize_stances?` counts **top-level, non-removed, default** posts: `hujahs.where(parent_id: nil).not_removed.where(agree_label: nil, neutral_label: nil, disagree_label: nil).count >= 10`. Custom posts are excluded because all three columns must be `nil` to count.
- Normalisation: trim, collapse internal whitespace (`\s+` → one space, which also strips newlines), cap at 24 chars, and a value case-insensitively equal to its default token stores `nil`.

---

## Task 1: Migration, storage columns, and model accessors/normalisation

**Files:** `db/migrate/<ts>_add_stance_labels_to_hujahs.rb`, `app/models/hujah.rb`, `spec/models/hujah_spec.rb`, `spec/factories/hujahs.rb`

- [ ] **Step 1.1** Write failing model specs for the accessors and normalisation. Append to `spec/models/hujah_spec.rb` (inside the top-level `RSpec.describe Hujah` block):

```ruby
  describe "custom stance labels (Slice 3)" do
    describe "#stance_label" do
      it "returns the default token for each position on a plain top-level hoojah" do
        h = build(:hujah)
        expect(h.stance_label(1)).to eq("agree")
        expect(h.stance_label(2)).to eq("neutral")
        expect(h.stance_label(3)).to eq("disagree")
      end

      it "returns the stored custom label per position on a top-level hoojah" do
        h = build(:hujah, agree_label: "Yes", neutral_label: "Meh", disagree_label: "No")
        expect(h.stance_label(1)).to eq("Yes")
        expect(h.stance_label(2)).to eq("Meh")
        expect(h.stance_label(3)).to eq("No")
      end

      it "falls back to the default token for a position left uncustomised" do
        h = build(:hujah, agree_label: "Yes", neutral_label: nil, disagree_label: nil)
        expect(h.stance_label(1)).to eq("Yes")
        expect(h.stance_label(2)).to eq("neutral")
        expect(h.stance_label(3)).to eq("disagree")
      end

      it "always returns defaults for a reply, even if label columns are set" do
        parent = create(:hujah)
        child = build(:hujah, parent_id: parent.id, agree_label: "Yes", disagree_label: "No")
        expect(child.stance_label(1)).to eq("agree")
        expect(child.stance_label(3)).to eq("disagree")
      end
    end

    describe "#custom_stances? / #default_hujah?" do
      it "custom_stances? is true when any label column is present" do
        expect(build(:hujah, neutral_label: "Meh").custom_stances?).to be true
        expect(build(:hujah).custom_stances?).to be false
      end

      it "default_hujah? is true only for a top-level hoojah with no custom labels" do
        expect(build(:hujah).default_hujah?).to be true
        expect(build(:hujah, agree_label: "Yes").default_hujah?).to be false
      end

      it "default_hujah? is false for a reply" do
        parent = create(:hujah)
        expect(build(:hujah, parent_id: parent.id).default_hujah?).to be false
      end
    end

    describe "normalisation on create" do
      # These authors are eligible so labels survive coercion (Task 2 wires the gate;
      # here we stub it true to isolate normalisation).
      let(:author) { create(:user) }
      before { allow_any_instance_of(User).to receive(:can_customize_stances?).and_return(true) }

      it "trims and collapses internal whitespace" do
        h = author.hujahs.create!(body: "a normal claim body", agree_label: "  Totally   agreed  ")
        expect(h.agree_label).to eq("Totally agreed")
      end

      it "caps a label at 24 characters" do
        h = author.hujahs.create!(body: "a normal claim body", disagree_label: "x" * 40)
        expect(h.disagree_label.length).to eq(24)
      end

      it "stores nil when a label equals its default token case-insensitively" do
        h = author.hujahs.create!(body: "a normal claim body",
          agree_label: "AGREE", neutral_label: "Neutral", disagree_label: "  disagree ")
        expect(h.agree_label).to be_nil
        expect(h.neutral_label).to be_nil
        expect(h.disagree_label).to be_nil
      end

      it "stores nil for a blank label" do
        h = author.hujahs.create!(body: "a normal claim body", neutral_label: "   ")
        expect(h.neutral_label).to be_nil
      end
    end

    describe "immutability (attr_readonly)" do
      let(:author) { create(:user) }
      before { allow_any_instance_of(User).to receive(:can_customize_stances?).and_return(true) }

      it "ignores label changes on update" do
        h = author.hujahs.create!(body: "an editable claim body", agree_label: "Yes")
        h.update(agree_label: "Hacked", disagree_label: "Nope")
        h.reload
        expect(h.agree_label).to eq("Yes")
        expect(h.disagree_label).to be_nil
      end
    end
  end
```

- [ ] **Step 1.2** Run the specs to confirm they FAIL (columns/methods absent):

```
RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/hujah_spec.rb -e "custom stance labels"
```

Expected: FAIL — e.g. `unknown attribute 'agree_label'` / `NoMethodError: undefined method 'stance_label'`.

- [ ] **Step 1.3** Create the migration `db/migrate/<ts>_add_stance_labels_to_hujahs.rb` (use `bin/rails g migration AddStanceLabelsToHujahs` for the timestamp, then set contents). Adding nullable string columns is a safe operation under `strong_migrations`:

```ruby
class AddStanceLabelsToHujahs < ActiveRecord::Migration[8.1]
  def change
    add_column :hujahs, :agree_label, :string
    add_column :hujahs, :neutral_label, :string
    add_column :hujahs, :disagree_label, :string
  end
end
```

- [ ] **Step 1.4** Apply the migration to dev and prepare the test schema:

```
mise exec ruby@3.4.9 -- bin/rails db:migrate
mise exec ruby@3.4.9 -- bin/rails db:test:prepare
```

- [ ] **Step 1.5** Add the model code to `app/models/hujah.rb`. Place the constants next to the existing `STANCES`/`COUNTER_FOR` block (~line 293):

```ruby
  # Slice 3 — per-position custom stance labels. STANCE_LABEL_COLUMNS maps the same
  # 1/2/3 vote positions STANCES uses to the nullable string column that overrides each
  # default token. A column is nil when uncustomised, so `default` and `custom` are a
  # pure presence test (see #custom_stances? / #default_hujah?).
  STANCE_LABEL_COLUMNS = {1 => :agree_label, 2 => :neutral_label, 3 => :disagree_label}.freeze
  CUSTOM_LABEL_MAX = 24
```

Add the readonly declaration near the associations (top of the class, after the `belongs_to`/`has_many` block):

```ruby
  # Slice 3: custom stance labels are IMMUTABLE after create. attr_readonly makes Rails
  # silently drop any assignment to these columns on UPDATE, so no edit path (present or
  # future) can rewrite them — the tamper-proof half of the gate; the create-time
  # eligibility coercion below is the other half.
  attr_readonly :agree_label, :neutral_label, :disagree_label
```

Register the callbacks near the other `before_*`/`after_*` hooks (e.g. just above `after_create_commit :notify_parent_owner` ~line 267):

```ruby
  # Slice 3: normalise first (so a tampered "Agree" collapses to nil BEFORE the
  # eligibility check reads it), then coerce away labels the author may not set. Both
  # run on create only — the columns are attr_readonly on update.
  before_validation :normalize_stance_labels, on: :create
  before_validation :enforce_stance_label_eligibility, on: :create
```

Add the public accessors near `STANCES` (after the constants above):

```ruby
  # The label shown for vote position 1/2/3 on THIS record's own surfaces: the custom
  # label when set, else the default STANCES token. Replies always render defaults —
  # only a top-level claim (parent_id nil) may carry custom labels.
  def stance_label(position)
    default = STANCES.fetch(position)
    return default unless parent_id.nil?
    self[STANCE_LABEL_COLUMNS.fetch(position)].presence || default
  end

  # Does this hoojah carry ANY custom label? (Presence test — a column is nil unless
  # customised.) Drives the badge award and the eligibility count's exclusion.
  def custom_stances?
    agree_label.present? || neutral_label.present? || disagree_label.present?
  end

  # A "default hoojah" for the Slice-3 eligibility count: top-level and uncustomised.
  def default_hujah?
    parent_id.nil? && !custom_stances?
  end
```

Add the private callbacks (in the `private` section, e.g. next to `award_authoring_badge` ~line 383):

```ruby
  # Trim, collapse internal whitespace (which also strips newlines), cap at
  # CUSTOM_LABEL_MAX, and treat a value equal to its default token (case-insensitive) as
  # "not customised" → nil. Empty/blank → nil.
  def normalize_stance_labels
    STANCES.each do |position, default_token|
      column = STANCE_LABEL_COLUMNS.fetch(position)
      raw = self[column]
      next if raw.nil?
      cleaned = raw.to_s.gsub(/\s+/, " ").strip[0, CUSTOM_LABEL_MAX]
      cleaned = nil if cleaned.blank? || cleaned.casecmp?(default_token)
      self[column] = cleaned
    end
  end

  # Custom labels survive ONLY on a top-level claim by an eligible author; anything else
  # (a reply, or an author under the 10-default-post threshold) has them coerced to nil,
  # so a hand-crafted POST cannot bypass the composer's server-side gate.
  def enforce_stance_label_eligibility
    return if parent_id.nil? && user&.can_customize_stances?
    self.agree_label = nil
    self.neutral_label = nil
    self.disagree_label = nil
  end
```

> Note: Task 1's normalisation/immutability specs stub `can_customize_stances?` true, so they pass before Task 2 defines the real method. `User` must still respond to it — Task 2 adds the real implementation; until then the `allow_any_instance_of` stub supplies it. If a bare `NoMethodError` appears here, land Step 2.4 (the method) first, then return; the two Tasks are otherwise independent.

- [ ] **Step 1.6** Add the `:custom_stances` trait to `spec/factories/hujahs.rb` (inside `factory :hujah`), for later tasks:

```ruby
    trait :custom_stances do
      agree_label { "Yes" }
      neutral_label { "Meh" }
      disagree_label { "No" }
    end
```

- [ ] **Step 1.7** Re-run and confirm PASS:

```
RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/hujah_spec.rb
```

Expected: all green (the new "custom stance labels" group plus the pre-existing examples).

- [ ] **Step 1.8** Commit:

```
git add -A && git commit -m "Slice 3 Task 1: Add stance-label columns, model accessors, normalisation"
```

---

## Task 2: `User#can_customize_stances?` eligibility gate

**Files:** `app/models/user.rb`, `spec/models/user_spec.rb`

- [ ] **Step 2.1** Write failing specs. Append to `spec/models/user_spec.rb` (inside `RSpec.describe User`):

```ruby
  describe "#can_customize_stances? (Slice 3 eligibility)" do
    let(:user) { create(:user) }

    it "is false for a new user with no posts" do
      expect(user.can_customize_stances?).to be false
    end

    it "is false at 9 default top-level hoojahs and true at 10 (boundary)" do
      create_list(:hujah, 9, user: user)
      expect(user.can_customize_stances?).to be false
      create(:hujah, user: user)
      expect(user.can_customize_stances?).to be true
    end

    it "excludes custom-labelled posts from the count" do
      create_list(:hujah, 9, user: user)
      # A 10th post that is CUSTOM does not count toward the threshold.
      create(:hujah, :custom_stances, user: user)
      expect(user.can_customize_stances?).to be false
    end

    it "excludes replies from the count" do
      parent = create(:hujah, user: create(:user))
      create_list(:hujah, 9, user: user)
      create(:hujah, user: user, parent_id: parent.id)
      expect(user.can_customize_stances?).to be false
    end

    it "excludes removed posts from the count" do
      create_list(:hujah, 9, user: user)
      create(:hujah, user: user, moderation_status: :removed)
      expect(user.can_customize_stances?).to be false
    end
  end
```

> The `:custom_stances` post in the second example is built by the factory directly (columns assigned, not via the coercing create path), so it persists its labels regardless of eligibility — exactly the state we need to prove the count excludes it.

- [ ] **Step 2.2** Run and confirm FAIL:

```
RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/user_spec.rb -e "can_customize_stances"
```

Expected: FAIL — `NoMethodError: undefined method 'can_customize_stances?'`.

- [ ] **Step 2.3** Add the method to `app/models/user.rb` (near `visible_hujahs_for`, ~line 166):

```ruby
  # Slice 3: an author may rename Agree/Neutral/Disagree on the composer once they have
  # posted 10+ DEFAULT top-level hoojahs — a claim is "default" only when none of its
  # three label columns are set, so custom posts (and replies, and removed posts) do not
  # count toward the threshold. One COUNT query; the composer calls it once per render.
  def can_customize_stances?
    hujahs.where(parent_id: nil).not_removed
      .where(agree_label: nil, neutral_label: nil, disagree_label: nil)
      .count >= 10
  end
```

- [ ] **Step 2.4** Re-run and confirm PASS:

```
RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/user_spec.rb -e "can_customize_stances"
```

Expected: green.

- [ ] **Step 2.5** Commit:

```
git add -A && git commit -m "Slice 3 Task 2: Add User#can_customize_stances? eligibility gate"
```

---

## Task 3: Create-path permit, server-side coercion, and immutability (request specs)

**Files:** `app/controllers/hujahs_controller.rb`, `spec/requests/compose_spec.rb`

- [ ] **Step 3.1** Write failing request specs. Append to `spec/requests/compose_spec.rb` (inside `RSpec.describe "Compose"`):

```ruby
  describe "custom stance labels (Slice 3)" do
    def make_eligible(u)
      # 10 default top-level posts clears the threshold.
      create_list(:hujah, 10, user: u)
    end

    it "persists normalised custom labels when the author is eligible" do
      make_eligible(user)
      sign_in user
      post "/hoojah", params: {hujah: {
        body: "A brand new claim about transit fares",
        agree_label: "  Totally  agreed ", neutral_label: "AGREE-ISH", disagree_label: "Disagree"
      }}
      h = Hujah.order(:created_at).last
      expect(h.agree_label).to eq("Totally agreed") # trimmed + collapsed
      expect(h.neutral_label).to eq("AGREE-ISH")    # kept (not the neutral default token)
      expect(h.disagree_label).to be_nil            # equals default token → nil
    end

    it "coerces custom labels to nil when the author is NOT eligible (tamper-proof)" do
      sign_in user # zero prior posts → ineligible
      post "/hoojah", params: {hujah: {
        body: "A brand new claim about transit fares",
        agree_label: "Yes", neutral_label: "Meh", disagree_label: "No"
      }}
      h = Hujah.order(:created_at).last
      expect(h.agree_label).to be_nil
      expect(h.neutral_label).to be_nil
      expect(h.disagree_label).to be_nil
    end

    it "ignores custom labels on a reply even from an eligible author" do
      make_eligible(user)
      parent = create(:hujah, user: create(:user))
      parent.cast_vote(by: user, choice: 1)
      sign_in user
      post "/hoojah", params: {hujah: {
        body: "my reply", parent_id: parent.id, vote: 1, agree_label: "Yes"
      }}
      expect(Hujah.order(:created_at).last.agree_label).to be_nil
    end
  end
```

- [ ] **Step 3.2** Run and confirm FAIL (labels not permitted → dropped, so the "eligible persists" example fails with `agree_label` nil):

```
RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/compose_spec.rb -e "custom stance labels"
```

Expected: FAIL on the first example (`expected: "Totally agreed" got: nil`).

- [ ] **Step 3.3** Permit the three params in `app/controllers/hujahs_controller.rb#compose_params` (~line 175). Immutability needs no controller work — there is no HTML `update` action here, and the model's `attr_readonly` protects the columns against any future one:

```ruby
  def compose_params
    # Slice 3: agree/neutral/disagree_label ride the create path only. They are
    # attr_readonly on the model (immutable after create) and coerced to nil there when
    # the author is not eligible, so permitting them here is safe — the gate is enforced
    # in the model, not by withholding the param.
    params.require(:hujah).permit(:body, :parent_id, :vote, :visibility, :allow_debates,
      :agree_label, :neutral_label, :disagree_label)
  end
```

- [ ] **Step 3.4** Re-run and confirm PASS:

```
RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/compose_spec.rb
```

Expected: the new group green and the pre-existing compose examples still green.

- [ ] **Step 3.5** Commit:

```
git add -A && git commit -m "Slice 3 Task 3: Permit stance-label params; verify server-side coercion + immutability"
```

---

## Task 4: `first_custom_hoojah` badge

**Files:** `app/models/badge.rb`, `app/models/hujah.rb`, `spec/models/badge_award_spec.rb`

- [ ] **Step 4.1** Write failing specs. Create `spec/models/badge_award_spec.rb` (or append to the existing badge spec if one covers `award_authoring_badge`):

```ruby
require "rails_helper"

RSpec.describe "first_custom_hoojah badge (Slice 3)", type: :model do
  let(:user) { create(:user) }

  def eligible!(u)
    create_list(:hujah, 10, user: u)
  end

  it "registers the badge key" do
    expect(Badge::REGISTRY).to have_key("first_custom_hoojah")
  end

  it "awards first_custom_hoojah when an eligible author posts a top-level custom hoojah" do
    eligible!(user)
    expect {
      user.hujahs.create!(body: "a claim with custom stances", agree_label: "Yes")
    }.to change { user.user_badges.where(badge_key: "first_custom_hoojah").count }.by(1)
  end

  it "does not award it for a default top-level hoojah" do
    eligible!(user)
    expect {
      user.hujahs.create!(body: "a plain default claim body")
    }.not_to change { user.user_badges.where(badge_key: "first_custom_hoojah").count }
  end

  it "does not award it when labels are coerced away for an ineligible author" do
    # Zero prior posts → ineligible → labels nilled → not a custom post.
    expect {
      user.hujahs.create!(body: "a claim that wanted custom stances", agree_label: "Yes")
    }.not_to change { user.user_badges.where(badge_key: "first_custom_hoojah").count }
  end

  it "awards it at most once" do
    eligible!(user)
    user.hujahs.create!(body: "first custom claim body", agree_label: "Yes")
    expect {
      user.hujahs.create!(body: "second custom claim body", disagree_label: "No")
    }.not_to change { user.user_badges.where(badge_key: "first_custom_hoojah").count }
  end
end
```

- [ ] **Step 4.2** Run and confirm FAIL:

```
RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/badge_award_spec.rb
```

Expected: FAIL — registry has no `first_custom_hoojah` key; no badge awarded.

- [ ] **Step 4.3** Add the registry entry in `app/models/badge.rb` (inside `REGISTRY`):

```ruby
    "first_custom_hoojah" => {
      name: "First Custom Hoojah",
      description: "Posted a hoojah with your own stance labels",
      icon: "pencil"
    },
```

- [ ] **Step 4.4** Extend `award_authoring_badge` in `app/models/hujah.rb` (~line 383). It runs `after_create_commit`, off the hot path, so the second `UserBadge.award` is safe:

```ruby
  def award_authoring_badge
    UserBadge.award(user, is_parent? ? "first_hoojah" : "first_argument")
    # Slice 3: a top-level claim that carries any custom label earns the custom badge.
    # `custom_stances?` reads the persisted (already-coerced) columns, so an ineligible
    # author whose labels were nilled never qualifies.
    UserBadge.award(user, "first_custom_hoojah") if is_parent? && custom_stances?
  end
```

- [ ] **Step 4.5** Re-run and confirm PASS:

```
RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/badge_award_spec.rb
```

Expected: green.

- [ ] **Step 4.6** Commit:

```
git add -A && git commit -m "Slice 3 Task 4: Add first_custom_hoojah badge on first custom top-level hoojah"
```

---

## Task 5: Render points + Stimulus inline-edit controller + system spec

**Files:** `app/views/hujahs/_vote_bars.html.erb`, `app/views/hujahs/_vote_hero.html.erb`, `app/views/hujahs/_card_menu.html.erb`, `app/views/hujahs/_share_menu.html.erb`, `app/views/hujahs/_compose_form.html.erb`, `app/javascript/controllers/stance_labels_controller.js`, `spec/requests/compose_spec.rb`, `spec/system/custom_stance_labels_spec.rb`

### Render points (top-level record's own surfaces only)

- [ ] **Step 5.1** Write a failing request spec asserting custom labels render on the show page and defaults render for a child. Append to `spec/requests/compose_spec.rb`:

```ruby
  describe "custom stance labels rendering (Slice 3)" do
    let(:author) { create(:user, username: "labeler") }

    it "shows custom labels on the top-level vote hero and share text" do
      create_list(:hujah, 10, user: author)
      h = author.hujahs.create!(body: "a claim with renamed stances",
        agree_label: "Yes", neutral_label: "Meh", disagree_label: "No")
      get "/hoojah/#{h.slug}"
      expect(response.body).to include("Yes").and include("Meh").and include("No")
      # Share text (byte-frozen shape) now carries the uppercased custom labels.
      expect(response.body).to include("Do you YES? MEH? NO?")
    end

    it "renders default tokens on a hoojah with no custom labels (share text unchanged)" do
      h = create(:hujah, user: author, body: "a plain default claim body")
      get "/hoojah/#{h.slug}"
      expect(response.body).to include("Do you AGREE? NEUTRAL? DISAGREE?")
    end
  end
```

- [ ] **Step 5.2** Run and confirm FAIL (the vote hero/share text still say Agree/Neutral/Disagree):

```
RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/compose_spec.rb -e "custom stance labels rendering"
```

Expected: FAIL on the first example (`"Do you YES? MEH? NO?"` absent).

- [ ] **Step 5.3** `app/views/hujahs/_vote_bars.html.erb`: capture `choice` in the two `rows.each` loops and swap the displayed stance WORD for `hujah.stance_label(choice)`. The class interpolation keeps using the `stance` string, so **no new class tokens are produced**.

Percent legend (lines 71-73) — change the loop header and the label text:

```erb
      <% rows.each do |stance, choice, _count| %>
        <span class="text-<%= stance %>"><%= pct[stance] %>% <%= hujah.stance_label(choice) %></span>
      <% end %>
```

Vote buttons (line 79 loop already binds `choice`) — change the button text on line 94 from `<%= stance.capitalize %>` to:

```erb
        <%= hujah.stance_label(choice) %>
```

- [ ] **Step 5.4** `app/views/hujahs/_vote_hero.html.erb`: the `stances.each` already binds `choice`. Change the aria-label (line 58) and button text (line 67):

```erb
                  aria-label="<%= hujah.stance_label(choice) %>"
```

```erb
              <span class="text-xs font-bold"><%= hujah.stance_label(choice) %></span>
```

- [ ] **Step 5.5** `app/views/hujahs/_card_menu.html.erb`: replace the frozen share text (line ~36) with label-driven text. For a default hoojah this is byte-identical to before, so `share_spec` stays green:

```erb
<% share_text = "\"#{strip_tags(hujah.body)} (by @#{hujah.user.username})\" Do you #{hujah.stance_label(1).upcase}? #{hujah.stance_label(2).upcase}? #{hujah.stance_label(3).upcase}?" %>
```

- [ ] **Step 5.6** `app/views/hujahs/_share_menu.html.erb`: same replacement for its `share_text` line:

```erb
<% share_text = "\"#{strip_tags(hujah.body)} (by @#{hujah.user.username})\" Do you #{hujah.stance_label(1).upcase}? #{hujah.stance_label(2).upcase}? #{hujah.stance_label(3).upcase}?" %>
```

- [ ] **Step 5.7** Re-run the render request spec AND the existing share request/system contract specs to confirm the byte-frozen default text is intact:

```
RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/compose_spec.rb -e "custom stance labels rendering" spec/requests/share_spec.rb
```

Expected: green (default share text unchanged; custom labels appear).

### Composer inline-edit affordance + Stimulus controller

- [ ] **Step 5.8** Rewrite the "How people will weigh in" block in `app/views/hujahs/_compose_form.html.erb` (the `parent.nil?` branch, lines 100-112) to branch on eligibility. Eligible authors get click-to-edit words + hidden fields wired to a `stance-labels` controller; ineligible authors get the unchanged static block:

```erb
        <% if current_user.can_customize_stances? %>
          <%# Slice 3: eligible authors rename each stance inline. Tapping a word swaps it
              for an input; stance_labels_controller syncs the value into the adjacent
              hidden hujah[<stance>_label] field. No hints, no extra chrome — discovered by
              tapping. Colours/icons stay keyed to the stance word, so no new Tailwind
              classes are produced by this block. %>
          <div class="mt-3.5 rounded-2xl bg-card shadow p-3.5" data-controller="stance-labels">
            <div class="text-xs font-bold text-ink-2 mb-2.5">How people will weigh in</div>
            <div class="flex gap-2.5">
              <% {agree: "Agree", neutral: "Neutral", disagree: "Disagree"}.each do |stance, label| %>
                <div class="flex-1 flex flex-col items-center gap-1.5 text-<%= stance %>">
                  <span class="w-9 h-9 rounded-full border-2 border-<%= stance %> flex items-center justify-center">
                    <%= stance_icon(stance.to_s, class: "w-4 h-4") %>
                  </span>
                  <span class="text-[11px] font-bold cursor-text"
                        data-stance-labels-target="word"
                        data-default="<%= label %>"
                        data-action="click->stance-labels#edit"><%= label %></span>
                  <%= f.hidden_field :"#{stance}_label" %>
                </div>
              <% end %>
            </div>
          </div>
        <% else %>
          <div class="mt-3.5 rounded-2xl bg-card shadow p-3.5">
            <div class="text-xs font-bold text-ink-2 mb-2.5">How people will weigh in</div>
            <div class="flex gap-2.5">
              <% {agree: "Agree", neutral: "Neutral", disagree: "Disagree"}.each do |stance, label| %>
                <div class="flex-1 flex flex-col items-center gap-1.5 text-<%= stance %>">
                  <span class="w-9 h-9 rounded-full border-2 border-<%= stance %> flex items-center justify-center">
                    <%= stance_icon(stance.to_s, class: "w-4 h-4") %>
                  </span>
                  <span class="text-[11px] font-bold"><%= label %></span>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
```

> `cursor-text` is the one new *static* utility this block introduces — it is a plain class name (not an interpolated stance class), so it does not touch the `@source inline(...)` safelist. It is expected to add a rule to the bundle; that is why the md5-unchanged guarantee in Task 6 is scoped to the four render-point views, not the composer.

- [ ] **Step 5.9** Create `app/javascript/controllers/stance_labels_controller.js` (auto-registered as `stance-labels` by `eagerLoadControllersFrom` — no `index.js` edit needed):

```javascript
import { Controller } from "@hotwired/stimulus"

// Slice 3 — inline click-to-edit for the composer's three stance words
// (Agree / Neutral / Disagree) on the "How people will weigh in" block. Tapping a word
// swaps it for a text input; committing (blur or Enter) writes the value into the
// adjacent hidden hujah[<stance>_label] field the form submits. A value left blank or
// equal to the default token submits empty, so the model normalises it back to nil and
// the post stays default. Rendered ONLY for eligible authors — ineligible users get the
// static block with no data-controller, so this never runs for them.
export default class extends Controller {
  static targets = ["word"]

  edit(event) {
    const word = event.currentTarget
    if (word.dataset.editing === "true") return
    word.dataset.editing = "true"

    const hidden = word.parentElement.querySelector("input[type=hidden]")
    const field = document.createElement("input")
    field.type = "text"
    field.maxLength = 24
    field.value = hidden.value || word.textContent.trim()
    field.className = word.className + " bg-transparent text-center w-full outline-none border-b border-current"
    field.setAttribute("aria-label", "Custom " + word.dataset.default + " label")

    word.replaceWith(field)
    field.focus()
    field.select()

    const commit = () => {
      const value = field.value.replace(/\s+/g, " ").trim().slice(0, 24)
      const isDefault = value === "" || value.toLowerCase() === word.dataset.default.toLowerCase()
      hidden.value = isDefault ? "" : value
      word.textContent = isDefault ? word.dataset.default : value
      word.dataset.editing = "false"
      field.replaceWith(word)
    }

    field.addEventListener("blur", commit)
    field.addEventListener("keydown", (e) => {
      if (e.key === "Enter") { e.preventDefault(); field.blur() }
      if (e.key === "Escape") { field.value = hidden.value; field.blur() }
    })
  }
}
```

- [ ] **Step 5.10** Write the system spec `spec/system/custom_stance_labels_spec.rb`:

```ruby
require "rails_helper"

# Cuprite (headless Chrome) coverage for the Slice-3 inline stance-label editor on the
# composer. Eligible authors (10+ default top-level hoojahs) can tap a stance word and
# rename it; ineligible authors get the static, non-editable block.
RSpec.describe "Custom stance labels", type: :system, js: true do
  let(:author) { create(:user, username: "labeler") }

  it "lets an eligible author rename a stance inline and persists it on create" do
    create_list(:hujah, 10, user: author)
    login_as author, scope: :user
    visit new_hujah_path

    find("[data-stance-labels-target='word'][data-default='Agree']").click
    field = find("input[aria-label='Custom Agree label']")
    field.set("Yes")
    field.native.send_keys(:enter)

    fill_in "What's your hoojah?", with: "a claim with renamed stances"
    click_button "Post"

    h = Hujah.order(:created_at).last
    expect(h.agree_label).to eq("Yes")
    expect(h.neutral_label).to be_nil
    expect(h.disagree_label).to be_nil
  end

  it "shows a non-editable block to an ineligible author" do
    login_as author, scope: :user # zero prior posts → ineligible
    visit new_hujah_path

    expect(page).to have_css("div", text: "How people will weigh in")
    expect(page).to have_no_css("[data-controller='stance-labels']")
    expect(page).to have_no_css("[data-stance-labels-target='word']")
  end
end
```

> `login_as(user, scope: :user)` routes through Warden's helper for system specs (the request-spec `login_as` override only triggers without a `:scope`). If the project's system specs use a different sign-in helper, mirror whatever `spec/system/share_spec.rb`-adjacent specs use to authenticate.

- [ ] **Step 5.11** Run the system spec (headless Chrome). Clear stale precompiled assets first per the CI/shared-DB note if a mid-phase JS spec misbehaves:

```
RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/system/custom_stance_labels_spec.rb
```

Expected: green — the eligible author's `agree_label` persists as "Yes"; the ineligible author sees no `stance-labels` controller.

- [ ] **Step 5.12** Commit:

```
git add -A && git commit -m "Slice 3 Task 5: Render stance_label at top-level surfaces; inline-edit composer controller"
```

---

## Task 6: Verify the render-point view edits produced no new Tailwind classes

**Files:** none (verification only)

The four render-point edits (Steps 5.3–5.6) swap displayed WORDS for `stance_label(...)` text while keeping every class keyed to the literal `stance` string — so they must not change the built bundle. (The composer block and the JS controller legitimately add plain static utilities like `cursor-text`/`bg-transparent`; those are out of scope for this hash check.)

- [ ] **Step 6.1** Build the bundle and record the baseline hash BEFORE re-confirming the render-point edits. (If following the plan top-to-bottom, capture this by temporarily `git stash`-ing Steps 5.3–5.6 or hashing at the Task 4 commit; otherwise hash `HEAD~1`'s bundle.) The reliable procedure:

```
git stash                 # park the working tree if needed
mise exec ruby@3.4.9 -- bin/rails tailwindcss:build
md5 app/assets/builds/tailwind.css   # baseline (macOS `md5`; use md5sum on Linux)
```

- [ ] **Step 6.2** Restore the render-point edits, rebuild, and confirm the hash is UNCHANGED:

```
git stash pop
mise exec ruby@3.4.9 -- bin/rails tailwindcss:build
md5 app/assets/builds/tailwind.css   # must equal the baseline
```

Expected: identical hash — the render-point ERB edits emit no new class tokens.

> Simpler practical variant when the composer/JS work is already committed: diff only the render-point views against their pre-Slice-3 versions and confirm no added token is a class name (all additions are `<%= hujah.stance_label(...) %>` / `choice` bindings). The md5 method above is the authoritative check for the four files in isolation.

- [ ] **Step 6.3** Positive control (per CLAUDE.md — a broken harness is otherwise indistinguishable from a clean result). Append a throwaway ERB comment naming an unused utility to one render-point view, rebuild, and confirm the hash MOVES; then remove it and rebuild back to baseline:

```
# add, e.g., `<%# tailwind-probe: mt-96 %>` to _vote_bars.html.erb
mise exec ruby@3.4.9 -- bin/rails tailwindcss:build
md5 app/assets/builds/tailwind.css   # must DIFFER from baseline
# remove the probe comment
mise exec ruby@3.4.9 -- bin/rails tailwindcss:build
md5 app/assets/builds/tailwind.css   # back to baseline
```

Expected: the probe moves the hash; removing it restores the baseline — proving the harness detects change.

- [ ] **Step 6.4** Run the full quality gates and suite to confirm Slice 3 is green end-to-end:

```
bin/ci
```

Expected: StandardRB, Brakeman, bundler-audit, and the full spec suite pass. (Use `bundle exec standardrb --fix` for any formatting nits before committing.)

- [ ] **Step 6.5** Commit any StandardRB autocorrections (verification steps themselves leave no tracked changes):

```
git add -A && git commit -m "Slice 3 Task 6: StandardRB cleanup; verify Tailwind bundle unchanged by render-point edits" || echo "nothing to commit"
```
