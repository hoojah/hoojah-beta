# Slice 2 — Change Visibility (Destructive) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a top-level hujah's owner change its visibility, where *tightening* the audience permanently purges the votes/arguments of everyone who loses access, snapshots the pre-change post into a read-only archive, and redirects those users' links to it.

**Architecture:** A single service object (`VisibilityChange`) owns the affected-set computation, the fail-closed entanglement check, and the row-locked purge transaction (build snapshot → insert participants → delete affected votes + childless arguments → recompute counters from scratch → set visibility → notify). Two new FK-less-style tables (`hujah_archives`, `hujah_archive_participants`) survive the live hujah's later deletion, mirroring the notification pattern. Every controller action authorizes exactly once against new `HujahPolicy` methods; the tighten path re-checks counts and entanglement server-side and fails closed; `hujahs#show` redirects a purged participant to their frozen archive, and the existing `DebateChannel` gate stops streaming to them for free.

**Tech Stack:** Rails 8.1, PostgreSQL (jsonb), RSpec, FactoryBot, Pundit, Action Cable, FriendlyId

---

## File Structure

### Created
| File | Responsibility |
|---|---|
| `db/migrate/<ts>_create_hujah_archives.rb` | `hujah_archives` table: `hujah_id` (integer, no cascading FK), `snapshot` jsonb, `visibility_before` int, `token` string (unique), timestamps. |
| `db/migrate/<ts>_create_hujah_archive_participants.rb` | `hujah_archive_participants` table: `archive_id`, `user_id`, unique index on the pair. |
| `app/models/hujah_archive.rb` | Frozen snapshot record; `has_many :participants`; token-addressed. |
| `app/models/hujah_archive_participant.rb` | Join row mapping a purged user to their archive; `.for(user, hujah)` lookup scope. |
| `app/services/visibility_change.rb` | `VisibilityChange` — direction detection, `#affected_participants`, `#counts`, `#blockers`, `#apply!` (purge transaction + snapshot + recount + notifications). |
| `app/policies/hujah_archive_policy.rb` | `show?` — a participant row for `(user, archive)` exists. |
| `app/controllers/hujah_archives_controller.rb` | `#show` — resolves the viewer's latest archive for a hujah, renders the frozen snapshot. |
| `app/views/hujah_archives/show.html.erb` | Read-only frozen post (body, counts, full argument tree). No actions. |
| `app/views/hujahs/visibility_edit.html.erb` | Change-visibility form; doubles as the tighten confirmation screen (counts + entanglement list + typed-confirm). |
| `spec/factories/hujah_archives.rb` | `:hujah_archive` + `:hujah_archive_participant` factories. |
| `spec/models/hujah_archive_spec.rb` | Model/association + `.for` lookup specs. |
| `spec/services/visibility_change_spec.rb` | Unit specs: direction, affected set (per-direction), counts, blockers, purge transaction, counter recompute, secret-ballot. |
| `spec/policies/hujah_policy_visibility_spec.rb` | `change_visibility?` / `promote?` truth tables. |
| `spec/requests/hujah_promote_spec.rb` | Promote action request specs. |
| `spec/requests/hujah_visibility_change_spec.rb` | `visibility_edit` / `update_visibility` request specs (loosening, tighten, fail-closed, typed-confirm). |
| `spec/requests/hujah_archive_redirect_spec.rb` | Purged-user redirect-to-archive + live-post/API leak specs. |
| `spec/channels/debate_channel_purge_spec.rb` | Cable leak spec: purged user's subscription rejects. |
| `spec/system/change_visibility_spec.rb` | System spec of the confirm flow. |

### Modified
| File | Change |
|---|---|
| `app/models/notification.rb` | Add `hujah_archived: 16` to the `category` enum. |
| `app/models/hujah.rb` | Add `#promote!` (parent_id nil, vote nil, slug regen). |
| `app/policies/hujah_policy.rb` | Add `change_visibility?` and `promote?`. |
| `app/controllers/hujahs_controller.rb` | Add `:visibility_edit, :update_visibility, :promote` (before_action + actions); redirect-to-archive in `#show`; confirm-word constant. |
| `config/routes.rb` | Add the four routes with explanatory comments. |
| `app/views/hujahs/show.html.erb` | Owner menu gains "Change visibility" (top-level owner). |

---

## Task 1 — Migrations + notification category

**Files:** `db/migrate/<ts>_create_hujah_archives.rb`, `db/migrate/<ts>_create_hujah_archive_participants.rb`, `app/models/notification.rb`, `spec/models/notification_spec.rb`

The two tables carry an **integer `hujah_id` with NO database foreign key** — the same FK-less pattern as `notifications.hujah_id` (hujah.rb:9-14), so an archive survives the live hujah's later deletion. `strong_migrations` is active but `create_table` on a brand-new table is always safe (no populated table touched). The notification category is an integer column, so adding an enum value is a **model-only** change (no migration).

- [ ] **Step 1** — Write a failing model spec for the new notification category.

  `spec/models/notification_spec.rb` (append or create):
  ```ruby
  require "rails_helper"

  RSpec.describe Notification, type: :model do
    it "supports the hujah_archived category at integer 16" do
      expect(Notification.categories["hujah_archived"]).to eq(16)
    end

    it "does not email the hujah_archived category (in-app only)" do
      expect(Notification::EMAILED_CATEGORIES).not_to include("hujah_archived")
    end
  end
  ```

- [ ] **Step 2** — Run it; expect FAIL (`NoMethodError`/`nil` — category undefined).
  ```
  mise exec ruby@3.4.9 -- env RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/notification_spec.rb
  ```

- [ ] **Step 3** — Add the category. In `app/models/notification.rb`, extend the enum:
  ```ruby
    enum :category, {
      admin: 0,
      announcement: 1,
      flag: 2,
      new_hoojah_response: 3,
      new_vote: 4,
      mention: 5,
      new_follower: 6,
      debate_challenge: 7,
      debate_declined: 8,
      debate_your_turn: 9,
      debate_concluded: 10,
      badge_earned: 11,
      follow_request: 12,
      follow_accepted: 13,
      # Moderation (2026): author-facing. Exact integers are load-bearing — the legacy
      # API serializes the category as its integer.
      moderation_removed: 14,
      moderation_warning: 15,
      # Slice 2 (editable-hujah): sent to a participant whose votes/arguments were
      # purged when the author tightened this hoojah's visibility. FK-less hujah_id
      # (like every category here) so it survives the hoojah's later deletion. NOT in
      # EMAILED_CATEGORIES — a purge is not a high-signal per-user email event.
      hujah_archived: 16
    }
  ```
  Run again; expect PASS.

- [ ] **Step 4** — Generate the migrations (write the files directly — match `db/migrate/20260830100002_create_short_links.rb` style; use `ActiveRecord::Migration[8.1]`).

  `db/migrate/<ts>_create_hujah_archives.rb`:
  ```ruby
  class CreateHujahArchives < ActiveRecord::Migration[8.1]
    def change
      create_table :hujah_archives do |t|
        # Integer, NO foreign key: the archive is a permanent record that must OUTLIVE
        # the live hoojah (mirrors notifications.hujah_id, hujah.rb:9-14). A cascading
        # FK would erase the frozen evidence the purged user is entitled to read.
        t.integer :hujah_id, null: false
        t.jsonb :snapshot, null: false, default: {}
        t.integer :visibility_before, null: false
        t.string :token, null: false

        t.timestamps
      end

      add_index :hujah_archives, :hujah_id
      add_index :hujah_archives, :token, unique: true
    end
  end
  ```

  `db/migrate/<ts>_create_hujah_archive_participants.rb` (second timestamp, later):
  ```ruby
  class CreateHujahArchiveParticipants < ActiveRecord::Migration[8.1]
    def change
      create_table :hujah_archive_participants do |t|
        t.bigint :archive_id, null: false
        t.bigint :user_id, null: false

        t.timestamps
      end

      add_index :hujah_archive_participants, :archive_id
      # One row per (archive, user): a user is mapped to a given archive at most once.
      add_index :hujah_archive_participants, [:archive_id, :user_id], unique: true
    end
  end
  ```

- [ ] **Step 5** — Prepare the test schema and confirm it loads:
  ```
  mise exec ruby@3.4.9 -- bin/rails db:migrate
  mise exec ruby@3.4.9 -- env RAILS_ENV=test bin/rails db:test:prepare
  ```
  (`db:test:prepare` = schema only; do NOT use `db:prepare` on the test DB — it seeds.)

- [ ] **Step 6** — Commit: `Slice 2 Task 1.1: hujah_archives + participants migrations, hujah_archived notification category`

---

## Task 2 — Models: HujahArchive + HujahArchiveParticipant

**Files:** `app/models/hujah_archive.rb`, `app/models/hujah_archive_participant.rb`, `spec/factories/hujah_archives.rb`, `spec/models/hujah_archive_spec.rb`

- [ ] **Step 1** — Add factories. `spec/factories/hujah_archives.rb`:
  ```ruby
  FactoryBot.define do
    factory :hujah_archive do
      association :hujah
      snapshot { {"body" => "Frozen body", "arguments" => []} }
      visibility_before { Hujah.visibilities[:visible_public] }
      sequence(:token) { |n| "tok_#{n}_#{SecureRandom.hex(4)}" }

      # hujah_id is set from the association above; HujahArchive stores the integer.
      after(:build) { |a| a.hujah_id ||= a.hujah&.id }
    end

    factory :hujah_archive_participant do
      association :archive, factory: :hujah_archive
      association :user
    end
  end
  ```
  Note: `HujahArchive` has no `belongs_to :hujah` association (FK-less integer), so the factory sets `hujah_id` explicitly from a built `:hujah`.

- [ ] **Step 2** — Write failing model specs. `spec/models/hujah_archive_spec.rb`:
  ```ruby
  require "rails_helper"

  RSpec.describe HujahArchive, type: :model do
    describe "associations + persistence" do
      it "persists a snapshot and lists its participants" do
        hujah = create(:hujah)
        archive = HujahArchive.create!(
          hujah_id: hujah.id,
          snapshot: {"body" => hujah.body, "arguments" => []},
          visibility_before: Hujah.visibilities[:visible_public],
          token: "abc123"
        )
        purged = create(:user)
        archive.participants.create!(user: purged)

        expect(archive.reload.snapshot["body"]).to eq(hujah.body)
        expect(archive.participants.map(&:user_id)).to eq([purged.id])
      end

      it "survives deletion of the live hoojah (FK-less hujah_id)" do
        hujah = create(:hujah)
        archive = create(:hujah_archive, hujah: hujah, hujah_id: hujah.id)
        hujah.destroy!
        expect(HujahArchive.find(archive.id).hujah_id).to eq(hujah.id)
      end
    end

    describe ".for" do
      it "returns the viewer's LATEST participant row for a hoojah, or nil" do
        hujah = create(:hujah)
        user = create(:user)
        old = create(:hujah_archive, hujah: hujah, hujah_id: hujah.id)
        old.participants.create!(user: user)
        newer = create(:hujah_archive, hujah: hujah, hujah_id: hujah.id)
        newer.participants.create!(user: user)

        found = HujahArchiveParticipant.for(user, hujah).first
        expect(found.archive_id).to eq(newer.id)
        expect(HujahArchiveParticipant.for(create(:user), hujah).first).to be_nil
      end
    end
  end
  ```

- [ ] **Step 3** — Run; expect FAIL (`uninitialized constant HujahArchive`).
  ```
  mise exec ruby@3.4.9 -- env RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/models/hujah_archive_spec.rb
  ```

- [ ] **Step 4** — Implement the models.

  `app/models/hujah_archive.rb`:
  ```ruby
  # A frozen, read-only snapshot of a top-level hoojah captured the instant its author
  # TIGHTENED visibility (Slice 2, editable-hujah). `hujah_id` is a plain integer with
  # NO database FK (mirrors notifications.hujah_id, hujah.rb:9-14): the archive is the
  # permanent record a purged participant is entitled to read, so it must survive the
  # live hoojah's later deletion. Immutable after creation — nothing edits `snapshot`.
  class HujahArchive < ApplicationRecord
    has_many :participants, class_name: "HujahArchiveParticipant",
      foreign_key: :archive_id, dependent: :destroy

    validates :token, presence: true, uniqueness: true
    validates :snapshot, presence: true
    validates :visibility_before, presence: true
  end
  ```

  `app/models/hujah_archive_participant.rb`:
  ```ruby
  # Maps ONE purged user to the archive captured at their purge moment (Slice 2). The
  # unique (archive_id, user_id) index makes re-insertion a no-op guard. `.for` resolves
  # "does this viewer have a frozen archive for this hoojah, and which is the latest"
  # — used by HujahsController#show (redirect gate) and HujahArchivesController#show.
  class HujahArchiveParticipant < ApplicationRecord
    belongs_to :archive, class_name: "HujahArchive"
    belongs_to :user

    # Latest-first participant rows for (user, hujah). A user re-admitted by a later
    # loosening and purged again maps to their MOST RECENT archive (design "Deferred
    # notes"): order by the archive's created_at desc so `.first` is the newest.
    def self.for(user, hujah)
      return none if user.nil?
      joins(:archive)
        .where(user_id: user.id, hujah_archives: {hujah_id: hujah.id})
        .order("hujah_archives.created_at DESC")
    end
  end
  ```

- [ ] **Step 5** — Run; expect PASS.

- [ ] **Step 6** — Commit: `Slice 2 Task 2.1: HujahArchive + HujahArchiveParticipant models`

---

## Task 3 — VisibilityChange service: direction + affected participants

**Files:** `app/services/visibility_change.rb`, `spec/services/visibility_change_spec.rb`

The **affected set** = users (≠ author) who voted on the top-level hoojah OR authored an argument anywhere in the subtree, who — evaluated **prospectively against the candidate visibility** — can no longer see the post. Prospective evaluation mirrors `Hujah#visible_to?`'s top-level branch (hujah.rb:123-128) exactly, using the candidate value.

- [ ] **Step 1** — Write failing direction + affected-set specs. `spec/services/visibility_change_spec.rb`:
  ```ruby
  require "rails_helper"

  RSpec.describe VisibilityChange do
    let(:author) { create(:user, username: "author") }
    let(:follower) { create(:user, username: "follower") }
    let(:stranger) { create(:user, username: "stranger") }

    def accept_follow(from:, to:)
      from.active_follows.create!(followed: to, status: :accepted)
    end

    describe "direction" do
      it "classifies tightening / loosening / no-op by enum rank" do
        h = create(:hujah, user: author, visibility: :followers_only)
        expect(VisibilityChange.new(h, to: "private_only")).to be_tightening
        expect(VisibilityChange.new(h, to: "visible_public")).to be_loosening
        expect(VisibilityChange.new(h, to: "followers_only")).to be_no_op
      end
    end

    describe "#affected_participants (public -> followers_only)" do
      it "affects a voting stranger but not an accepted follower or the author" do
        h = create(:hujah, user: author, visibility: :visible_public)
        accept_follow(from: follower, to: author)
        h.cast_vote(by: follower, choice: 1)
        h.cast_vote(by: stranger, choice: 3)

        change = VisibilityChange.new(h, to: "followers_only")
        ids = change.affected_participants.map(&:id)
        expect(ids).to contain_exactly(stranger.id)
      end
    end

    describe "#affected_participants (public -> private_only)" do
      it "affects every non-author participant, incl. a subtree argument author" do
        h = create(:hujah, user: author, visibility: :visible_public)
        accept_follow(from: follower, to: author)
        h.cast_vote(by: follower, choice: 1)                 # follower voted
        h.cast_vote(by: stranger, choice: 2)                 # stranger voted
        arg_author = create(:user, username: "argauthor")
        h.cast_vote(by: arg_author, choice: 1)
        create(:hujah, user: arg_author, parent_id: h.id, body: "A subtree argument")

        change = VisibilityChange.new(h, to: "private_only")
        expect(change.affected_participants.map(&:id))
          .to contain_exactly(follower.id, stranger.id, arg_author.id)
      end
    end

    describe "#counts" do
      it "reports users / votes / arguments to be removed" do
        h = create(:hujah, user: author, visibility: :visible_public)
        h.cast_vote(by: stranger, choice: 1)
        create(:hujah, user: stranger, parent_id: h.id, body: "Strangers argument here")

        counts = VisibilityChange.new(h, to: "private_only").counts
        expect(counts).to eq(users: 1, votes: 1, arguments: 1)
      end
    end
  end
  ```

- [ ] **Step 2** — Run; expect FAIL (`uninitialized constant VisibilityChange`).
  ```
  mise exec ruby@3.4.9 -- env RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/services/visibility_change_spec.rb
  ```

- [ ] **Step 3** — Implement direction + affected-set (no purge yet).

  `app/services/visibility_change.rb`:
  ```ruby
  # Encapsulates a top-level hoojah's visibility change (Slice 2, editable-hujah).
  # LOOSENING just updates the column. TIGHTENING is destructive: it purges the votes
  # and subtree arguments of every participant who loses access, snapshots the pre-change
  # post, and notifies them. The service owns three concerns so they are unit-testable in
  # isolation and cannot drift from the controller's server-side re-check:
  #   - #affected_participants / #counts : who loses access and how much is removed
  #   - #blockers                        : entangled arguments that FAIL the change closed
  #   - #apply!                          : the row-locked purge transaction
  class VisibilityChange
    class Blocked < StandardError; end
    class NotTightening < StandardError; end

    def initialize(hujah, to:)
      @hujah = hujah
      @to = to.to_s
    end

    attr_reader :hujah, :to

    # Direction by enum RANK — the enum integers are the audience order
    # (visible_public 0 < followers_only 1 < private_only 2), so a larger target rank
    # is a narrower audience = tightening.
    def from_rank = Hujah.visibilities.fetch(hujah.visibility)

    def to_rank = Hujah.visibilities.fetch(@to)

    def no_op? = to_rank == from_rank

    def loosening? = to_rank < from_rank

    def tightening? = to_rank > from_rank

    # Users (≠ author) who voted on the top-level hoojah OR authored a subtree argument,
    # and who — evaluated PROSPECTIVELY against the candidate visibility — can no longer
    # see the post. The author is never affected.
    def affected_participants
      @affected_participants ||= candidate_users.reject { |u| visible_under?(u, @to) }
    end

    def affected_participant_ids = affected_participants.map(&:id)

    def counts
      ids = affected_participant_ids.to_set
      {
        users: ids.size,
        votes: hujah.votes.where(user_id: ids.to_a).count,
        arguments: subtree_hujahs.count { |h| ids.include?(h.user_id) }
      }
    end

    private

    def candidate_users
      @candidate_users ||= User.where(id: candidate_ids).to_a
    end

    def candidate_ids
      @candidate_ids ||= begin
        voter_ids = hujah.votes.distinct.pluck(:user_id)
        author_ids = subtree_hujahs.map(&:user_id)
        (voter_ids + author_ids).uniq - [hujah.user_id]
      end
    end

    # The whole descendant set of the top-level hoojah, breadth-first (depth-bounded,
    # a handful of queries — not per-record N+1). Excludes the top hoojah itself.
    def subtree_hujahs
      @subtree_hujahs ||= begin
        collected = []
        frontier = hujah.children.to_a
        until frontier.empty?
          collected.concat(frontier)
          frontier = Hujah.where(parent_id: frontier.map(&:id)).to_a
        end
        collected
      end
    end

    # Mirrors Hujah#visible_to?'s TOP-LEVEL branch (hujah.rb:123-128) with the CANDIDATE
    # visibility — the hoojah is top-level and not removed, so no parent recursion / no
    # moderation gate applies. Kept in lockstep with that method: account privacy first,
    # then the per-post visibility case.
    def visible_under?(viewer, visibility)
      return false unless hujah.user.visible_to?(viewer)

      case visibility.to_s
      when "visible_public" then true
      when "followers_only" then viewer == hujah.user || hujah.user.accepted_follower?(viewer)
      when "private_only" then viewer == hujah.user
      else false
      end
    end
  end
  ```

- [ ] **Step 4** — Run; expect PASS.

- [ ] **Step 5** — Commit: `Slice 2 Task 3.1: VisibilityChange direction + affected-participant computation`

---

## Task 4 — VisibilityChange: entanglement / blockers

**Files:** `app/services/visibility_change.rb`, `spec/services/visibility_change_spec.rb`

An affected user's argument is **entangled** (and blocks the whole change, fail-closed) when it has replies or votes from **other** users, or **any** debate. Resolution is on the argument owner's side (delete or promote).

- [ ] **Step 1** — Add failing blocker specs to `spec/services/visibility_change_spec.rb`:
  ```ruby
    describe "#blockers (entanglement, fail closed)" do
      let(:author) { create(:user, username: "author") }
      let(:stranger) { create(:user, username: "stranger") }
      let(:other) { create(:user, username: "other") }

      def public_hujah = create(:hujah, user: author, visibility: :visible_public)

      it "is empty when an affected arg is a clean leaf (no others' replies/votes/debate)" do
        h = public_hujah
        h.cast_vote(by: stranger, choice: 1)
        create(:hujah, user: stranger, parent_id: h.id, body: "A lonely argument here")
        expect(VisibilityChange.new(h, to: "private_only").blockers).to be_empty
      end

      it "blocks when an affected arg has a reply from ANOTHER user" do
        h = public_hujah
        h.cast_vote(by: stranger, choice: 1)
        arg = create(:hujah, user: stranger, parent_id: h.id, body: "An argument with a reply")
        create(:hujah, user: other, parent_id: arg.id, body: "Someone elses reply here")

        blockers = VisibilityChange.new(h, to: "private_only").blockers
        expect(blockers.map(&:id)).to contain_exactly(arg.id)
      end

      it "blocks when an affected arg has a vote from ANOTHER user" do
        h = public_hujah
        h.cast_vote(by: stranger, choice: 1)
        arg = create(:hujah, user: stranger, parent_id: h.id, body: "An argument with a vote")
        arg.cast_vote(by: other, choice: 2)

        expect(VisibilityChange.new(h, to: "private_only").blockers.map(&:id))
          .to contain_exactly(arg.id)
      end

      it "blocks when an affected arg is attached to a debate" do
        h = public_hujah
        h.cast_vote(by: stranger, choice: 1)
        arg = create(:hujah, user: stranger, parent_id: h.id, body: "An argument in a debate")
        create(:debate, hujah: arg, challenger: stranger, opponent: other, status: :active)

        expect(VisibilityChange.new(h, to: "private_only").blockers.map(&:id))
          .to contain_exactly(arg.id)
      end
    end
  ```

- [ ] **Step 2** — Run; expect FAIL (`NoMethodError: undefined method 'blockers'`).
  ```
  mise exec ruby@3.4.9 -- env RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/services/visibility_change_spec.rb -e blockers
  ```

- [ ] **Step 3** — Implement. In `app/services/visibility_change.rb`, add public method after `#counts`:
  ```ruby
    # Affected arguments that are ENTANGLED with other users' participation. A non-empty
    # result FAILS the change closed (design: the whole change is blocked). Resolution is
    # the ARGUMENT OWNER's: delete it or promote it to a standalone top-level hoojah.
    def blockers
      @blockers ||= affected_arguments.select { |arg| entangled?(arg) }
    end
  ```
  and these privates:
  ```ruby
    def affected_arguments
      ids = affected_participant_ids.to_set
      subtree_hujahs.select { |h| ids.include?(h.user_id) }
    end

    # Entangled = carries OTHER users' content that a purge would wrongly destroy: a
    # reply or vote from someone other than the arg's own author, or ANY debate (a
    # debate always couples two users and its transcript is shared content). `.exists?`
    # issues an EXISTS, not a load.
    def entangled?(arg)
      arg.children.where.not(user_id: arg.user_id).exists? ||
        arg.votes.where.not(user_id: arg.user_id).exists? ||
        arg.debates.exists?
    end
  ```

- [ ] **Step 4** — Run; expect PASS.

- [ ] **Step 5** — Commit: `Slice 2 Task 4.1: VisibilityChange entanglement / blockers detection`

---

## Task 5 — VisibilityChange: purge transaction (snapshot + recount + notifications)

**Files:** `app/services/visibility_change.rb`, `spec/services/visibility_change_spec.rb`

`#apply!` runs inside `hujah.with_lock` (row lock + transaction). Order per design: (1) build snapshot from CURRENT state, create `HujahArchive`; (2) insert `HujahArchiveParticipant` per affected user; (3) delete affected votes + their now-childless arguments; (4) recompute all four counters from remaining votes; (5) set new visibility; (6) create FK-less `hujah_archived` notifications. It re-derives the affected set/blockers **under the lock** and raises `Blocked` if anything newly entangled appeared.

- [ ] **Step 1** — Add failing purge specs to `spec/services/visibility_change_spec.rb`:
  ```ruby
    describe "#apply! (purge transaction)" do
      let(:author) { create(:user, username: "author") }
      let(:follower) { create(:user, username: "follower") }
      let(:stranger) { create(:user, username: "stranger") }

      def accept_follow(from:, to:)
        from.active_follows.create!(followed: to, status: :accepted)
      end

      it "recomputes counters EXACTLY from the votes that remain" do
        h = create(:hujah, user: author, visibility: :visible_public)
        accept_follow(from: follower, to: author)
        h.cast_vote(by: follower, choice: 1)   # agree — survives (follower still sees it)
        h.cast_vote(by: stranger, choice: 1)   # agree — purged
        h.cast_vote(by: create(:user), choice: 3) # disagree — purged
        expect(h.reload.agree_count).to eq(2)
        expect(h.disagree_count).to eq(1)

        VisibilityChange.new(h, to: "followers_only").apply!

        h.reload
        expect(h.agree_count).to eq(1)     # only the follower's agree remains
        expect(h.neutral_count).to eq(0)
        expect(h.disagree_count).to eq(0)
        expect(h.visibility).to eq("followers_only")
      end

      it "removes an affected user's CONVICTION vote (purge overrides the lock)" do
        h = create(:hujah, user: author, visibility: :visible_public)
        h.cast_vote(by: stranger, choice: 1, conviction: true)
        expect(h.reload.conviction_count).to eq(1)

        VisibilityChange.new(h, to: "private_only").apply!

        expect(h.reload.conviction_count).to eq(0)
        expect(Vote.where(hujah_id: h.id, user_id: stranger.id)).to be_empty
      end

      it "deletes affected users' subtree arguments but leaves unaffected users untouched" do
        h = create(:hujah, user: author, visibility: :visible_public)
        accept_follow(from: follower, to: author)
        h.cast_vote(by: follower, choice: 1)
        h.cast_vote(by: stranger, choice: 1)
        keep = create(:hujah, user: follower, parent_id: h.id, body: "Follower keeps this arg")
        drop = create(:hujah, user: stranger, parent_id: h.id, body: "Stranger loses this arg")

        VisibilityChange.new(h, to: "followers_only").apply!

        expect(Hujah.exists?(keep.id)).to be(true)
        expect(Hujah.exists?(drop.id)).to be(false)
        expect(Vote.exists?(hujah_id: h.id, user_id: follower.id)).to be(true)
      end

      it "creates a HujahArchive + participant rows + hujah_archived notifications" do
        h = create(:hujah, user: author, visibility: :visible_public, body: "Archive me please")
        h.cast_vote(by: stranger, choice: 2)

        expect { VisibilityChange.new(h, to: "private_only").apply! }
          .to change(HujahArchive, :count).by(1)
          .and change(HujahArchiveParticipant, :count).by(1)

        archive = HujahArchive.last
        expect(archive.snapshot["body"]).to eq("Archive me please")
        expect(archive.visibility_before).to eq(Hujah.visibilities[:visible_public])
        expect(archive.participants.map(&:user_id)).to eq([stranger.id])
        note = Notification.find_by(user_id: stranger.id, category: :hujah_archived)
        expect(note).to be_present
        expect(note.hujah_id).to eq(h.id)
      end

      it "preserves the secret ballot — the notification carries NO subject_user_id" do
        h = create(:hujah, user: author, visibility: :visible_public)
        h.cast_vote(by: stranger, choice: 1)

        VisibilityChange.new(h, to: "private_only").apply!

        note = Notification.find_by(category: :hujah_archived, user_id: stranger.id)
        expect(note.subject_user_id).to be_nil
      end

      it "raises Blocked and changes nothing when an affected arg is entangled" do
        h = create(:hujah, user: author, visibility: :visible_public)
        h.cast_vote(by: stranger, choice: 1)
        arg = create(:hujah, user: stranger, parent_id: h.id, body: "An entangled argument")
        arg.cast_vote(by: create(:user), choice: 2) # another user's vote entangles it

        expect { VisibilityChange.new(h, to: "private_only").apply! }
          .to raise_error(VisibilityChange::Blocked)
        expect(h.reload.visibility).to eq("visible_public")
        expect(HujahArchive.count).to eq(0)
      end
    end
  ```

- [ ] **Step 2** — Run; expect FAIL (`NoMethodError: undefined method 'apply!'`).
  ```
  mise exec ruby@3.4.9 -- env RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/services/visibility_change_spec.rb -e apply
  ```

- [ ] **Step 3** — Implement `#apply!` and helpers in `app/services/visibility_change.rb`.

  Public method (after `#blockers`):
  ```ruby
    # The destructive purge, row-locked. Re-derives the affected set/blockers UNDER the
    # lock (fail closed on anything newly entangled between the confirmation GET and
    # here) and performs the six ordered steps in one transaction. Returns the archive.
    def apply!
      raise NotTightening unless tightening?

      hujah.with_lock do
        reset_memos!
        raise Blocked if blockers.any?

        affected = affected_participants
        archive = HujahArchive.create!(
          hujah_id: hujah.id,
          snapshot: build_snapshot,                      # (1) from CURRENT state
          visibility_before: Hujah.visibilities.fetch(hujah.visibility),
          token: SecureRandom.urlsafe_base64(12)
        )
        affected.each { |u| archive.participants.create!(user_id: u.id) } # (2)

        affected_ids = affected.map(&:id)
        Vote.where(hujah_id: hujah.id, user_id: affected_ids).delete_all   # (3a)
        destroy_affected_arguments!(affected_ids.to_set)                   # (3b)
        recompute_counters!                                                # (4)
        hujah.update!(visibility: @to)                                     # (4 dirty counters + 5)

        affected.each do |u|                                               # (6)
          # Secret ballot: NO subject_user_id (identifying the author to nobody is not
          # the point — this row must not become a de-anonymization primitive, and the
          # category simply says "your participation was archived").
          Notification.create!(user_id: u.id, category: :hujah_archived, hujah_id: hujah.id)
        end
        archive
      end
    end
  ```

  Privates:
  ```ruby
    def reset_memos!
      @candidate_users = @candidate_ids = @subtree_hujahs = nil
      @affected_participants = @blockers = nil
    end

    # Destroy only the ROOTS of each affected-argument subtree; `dependent: :destroy`
    # cascades their descendants. Safe because a non-blocked change guarantees no
    # affected argument carries another user's reply/vote/debate — so every descendant
    # of an affected root is the same (affected) author's content, never a bystander's.
    def destroy_affected_arguments!(affected_ids)
      args = subtree_hujahs.select { |h| affected_ids.include?(h.user_id) }
      arg_ids = args.map(&:id).to_set
      roots = args.reject { |h| arg_ids.include?(h.parent_id) }
      roots.each(&:destroy!)
    end

    # Recount from scratch (design: safest). `votes.vote` is the legacy array column —
    # the LAST element is the current stance (hujah.rb:371). assign_attributes leaves the
    # counters dirty for the single update! in #apply! that also writes visibility.
    def recompute_counters!
      remaining = hujah.votes.reload.to_a
      hujah.assign_attributes(
        agree_count: remaining.count { |v| v.vote.last == 1 },
        neutral_count: remaining.count { |v| v.vote.last == 2 },
        disagree_count: remaining.count { |v| v.vote.last == 3 },
        conviction_count: remaining.count(&:conviction?)
      )
    end

    def build_snapshot
      {
        "body" => hujah.body,
        "author" => hujah.user.username,
        "author_name" => hujah.user.full_name,
        "created_at" => hujah.created_at.iso8601,
        "agree_count" => hujah.agree_count,
        "neutral_count" => hujah.neutral_count,
        "disagree_count" => hujah.disagree_count,
        "conviction_count" => hujah.conviction_count,
        # Effective stance labels: defaults today. If Slice 3 (custom labels) has shipped,
        # read hujah.stance_label(pos) here instead — labels-only, no other change.
        "stance_labels" => {"agree" => "Agree", "neutral" => "Neutral", "disagree" => "Disagree"},
        "arguments" => hujah.children.map { |c| snapshot_argument(c) }
      }
    end

    def snapshot_argument(arg)
      {
        "author" => arg.user.username,
        "body" => arg.body,
        "stance" => Hujah::STANCES[arg.vote],
        "agree_count" => arg.agree_count.to_i,
        "neutral_count" => arg.neutral_count.to_i,
        "disagree_count" => arg.disagree_count.to_i,
        "children" => arg.children.map { |g| snapshot_argument(g) }
      }
    end
  ```

- [ ] **Step 4** — Run; expect PASS (whole service file):
  ```
  mise exec ruby@3.4.9 -- env RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/services/visibility_change_spec.rb
  ```

- [ ] **Step 5** — Run StandardRB on the new service; fix any format drift:
  ```
  mise exec ruby@3.4.9 -- bundle exec standardrb app/services/visibility_change.rb --fix
  ```

- [ ] **Step 6** — Commit: `Slice 2 Task 5.1: VisibilityChange purge transaction, snapshot + counter recompute + notifications`

---

## Task 6 — Policy: change_visibility? + promote?

**Files:** `app/policies/hujah_policy.rb`, `spec/policies/hujah_policy_visibility_spec.rb`

- [ ] **Step 1** — Write failing policy specs. `spec/policies/hujah_policy_visibility_spec.rb`:
  ```ruby
  require "rails_helper"

  RSpec.describe HujahPolicy do
    let(:owner) { create(:user) }
    let(:other) { create(:user) }

    describe "#change_visibility?" do
      it "allows the owner of a top-level, active hoojah" do
        h = create(:hujah, user: owner)
        expect(HujahPolicy.new(owner, h).change_visibility?).to be(true)
      end

      it "denies a non-owner" do
        h = create(:hujah, user: owner)
        expect(HujahPolicy.new(other, h).change_visibility?).to be(false)
      end

      it "denies on a reply (not top-level)" do
        parent = create(:hujah, user: owner)
        reply = create(:hujah, user: owner, parent_id: parent.id, body: "A reply hoojah here")
        expect(HujahPolicy.new(owner, reply).change_visibility?).to be(false)
      end

      it "denies on a removed hoojah" do
        h = create(:hujah, user: owner, moderation_status: :removed)
        expect(HujahPolicy.new(owner, h).change_visibility?).to be(false)
      end
    end

    describe "#promote?" do
      it "allows the owner of a child (reply)" do
        parent = create(:hujah, user: owner)
        reply = create(:hujah, user: owner, parent_id: parent.id, body: "A reply hoojah here")
        expect(HujahPolicy.new(owner, reply).promote?).to be(true)
      end

      it "denies on a top-level hoojah (nothing to promote)" do
        h = create(:hujah, user: owner)
        expect(HujahPolicy.new(owner, h).promote?).to be(false)
      end

      it "denies a non-owner and a removed reply" do
        parent = create(:hujah, user: owner)
        reply = create(:hujah, user: owner, parent_id: parent.id, body: "A reply hoojah here")
        expect(HujahPolicy.new(other, reply).promote?).to be(false)
        reply.update!(moderation_status: :removed)
        expect(HujahPolicy.new(owner, reply).promote?).to be(false)
      end
    end
  end
  ```

- [ ] **Step 2** — Run; expect FAIL (`NoMethodError: undefined method 'change_visibility?'`).
  ```
  mise exec ruby@3.4.9 -- env RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/policies/hujah_policy_visibility_spec.rb
  ```

- [ ] **Step 3** — Add to `app/policies/hujah_policy.rb` (after `destroy?`):
  ```ruby
    # Slice 2 (editable-hujah): visibility is changeable only by the OWNER of a
    # TOP-LEVEL, non-removed claim. Top-level only — a reply inherits its parent's
    # visibility (hujah.rb:26), so it has none of its own to change. Removed mirrors
    # destroy?: a removed claim is staff-only and its author must not act on it.
    def change_visibility? =
      user.present? && record.user_id == user.id &&
        record.parent_id.nil? && !record.moderation_removed?

    # Slice 2: promoting a reply to a standalone top-level claim is owner-only and
    # valid only on a CHILD (parent_id present) that is not removed.
    def promote? =
      user.present? && record.user_id == user.id &&
        record.parent_id.present? && !record.moderation_removed?
  ```

- [ ] **Step 4** — Run; expect PASS.

- [ ] **Step 5** — Commit: `Slice 2 Task 6.1: HujahPolicy change_visibility? + promote?`

---

## Task 7 — Promote action + route + model method

**Files:** `config/routes.rb`, `app/models/hujah.rb`, `app/controllers/hujahs_controller.rb`, `spec/requests/hujah_promote_spec.rb`

Promote sets `parent_id = nil` (subtree travels — descendants keep pointing at it), clears the `vote` (stance-toward-parent) column, and regenerates the slug. Slug regeneration: `should_generate_new_friendly_id?` fires on blank slug (hujah.rb:286-288), so `promote!` sets `slug: nil`; FriendlyId `:history` keeps the old slug redirecting. Top-level `body >= 8` validation (hujah.rb:80) now applies.

- [ ] **Step 1** — Write failing request spec. `spec/requests/hujah_promote_spec.rb`:
  ```ruby
  require "rails_helper"

  RSpec.describe "Promote a hoojah to top-level", type: :request do
    let(:owner) { create(:user) }
    let(:other) { create(:user) }
    def sign_in_fresh(u) = sign_in(User.find(u.id))

    it "detaches the reply, clears its stance vote, regenerates the slug, keeps its subtree" do
      parent = create(:hujah, user: owner, body: "Parent claim body here")
      reply = create(:hujah, user: owner, parent_id: parent.id, vote: 1, body: "Reply worth promoting")
      grandchild = create(:hujah, user: other, parent_id: reply.id, body: "Grandchild reply body")
      old_slug = reply.slug

      sign_in_fresh owner
      post "/hoojah/#{reply.slug}/promote"

      reply.reload
      expect(reply.parent_id).to be_nil
      expect(reply.vote).to be_nil
      expect(reply.slug).not_to eq(old_slug)
      expect(grandchild.reload.parent_id).to eq(reply.id) # subtree travelled
      # FriendlyId history: the old slug still resolves to the promoted record.
      expect(Hujah.friendly.find(old_slug).id).to eq(reply.id)
      expect(response).to have_http_status(:see_other).or have_http_status(:found)
    end

    it "denies a non-owner (Pundit redirect, no change)" do
      parent = create(:hujah, user: owner, body: "Parent claim body here")
      reply = create(:hujah, user: owner, parent_id: parent.id, body: "Reply worth promoting")
      sign_in_fresh other
      post "/hoojah/#{reply.slug}/promote"
      expect(reply.reload.parent_id).to eq(parent.id)
    end

    it "denies promoting a top-level hoojah" do
      h = create(:hujah, user: owner, body: "Already top level here")
      sign_in_fresh owner
      post "/hoojah/#{h.slug}/promote"
      expect(h.reload.parent_id).to be_nil # unchanged, still top-level
      expect(flash[:alert]).to be_present.or(satisfy { response.status.in?([302, 303]) })
    end
  end
  ```

- [ ] **Step 2** — Run; expect FAIL (routing error — no promote route).
  ```
  mise exec ruby@3.4.9 -- env RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/hujah_promote_spec.rb
  ```

- [ ] **Step 3** — Add the route. In `config/routes.rb`, immediately after the `delete "/hoojah/:slug"` block (line ~64):
  ```ruby
    # Promote a reply to a standalone top-level claim (Slice 2, editable-hujah). A WRITE
    # action → MAIN route (CSRF on; `button_to` carries the token), never Api::V1.
    # Owner-only + child-only via HujahPolicy#promote?. Used both from the reply's own
    # owner menu and as an entanglement resolution when the author tightens a parent's
    # visibility. `parent_id` is set to nil (the subtree travels with it) and the slug
    # regenerates; FriendlyId :history keeps the old slug redirecting.
    post "/hoojah/:slug/promote", to: "hujahs#promote", as: :promote_hujah
  ```

- [ ] **Step 4** — Add the model method. In `app/models/hujah.rb` (after `deletable?` or near `should_generate_new_friendly_id?`):
  ```ruby
    # Slice 2 (editable-hujah): detach this reply into a standalone top-level claim. The
    # whole subtree travels with it (descendants keep pointing here). `vote: nil` drops
    # the stance-toward-parent context — a top-level claim has no parent to take a stance
    # on. `slug: nil` forces FriendlyId to regenerate from the body (should_generate_new_
    # friendly_id? returns true on a blank slug); :history keeps the old slug redirecting.
    # The top-level `body >= 8` validation (see above) now applies via update!.
    def promote!
      update!(parent_id: nil, vote: nil, slug: nil)
    end
  ```

- [ ] **Step 5** — Add the controller action + before_action. In `app/controllers/hujahs_controller.rb`, extend the before_action and add `promote`:
  ```ruby
    before_action :authenticate_user!, only: [:new, :create, :destroy, :promote, :visibility_edit, :update_visibility]
  ```
  ```ruby
    def promote
      @hujah = Hujah.friendly.find(params[:slug])
      # Owner + child + not-removed via HujahPolicy#promote?. A non-owner / top-level
      # target trips Pundit::NotAuthorizedError → the ApplicationController rescue
      # redirects back with an alert (not a bare 403).
      authorize @hujah, :promote?
      @hujah.promote!
      redirect_to hujah_path(@hujah.slug), notice: "Promoted to a standalone hoojah.", status: :see_other
    rescue ActiveRecord::RecordInvalid
      redirect_back fallback_location: hujah_path(@hujah.slug),
        alert: "This hoojah can't be promoted (its body is too short for a top-level claim).",
        status: :see_other
    end
  ```

- [ ] **Step 6** — Run; expect PASS. Commit: `Slice 2 Task 7.1: promote action + route + Hujah#promote!`

---

## Task 8 — visibility_edit + update_visibility + confirmation view

**Files:** `config/routes.rb`, `app/controllers/hujahs_controller.rb`, `app/views/hujahs/visibility_edit.html.erb`, `spec/requests/hujah_visibility_change_spec.rb`

`visibility_edit` renders the change form; when a `?to=` is present it also shows counts + blockers + typed-confirm. `update_visibility` runs the loosening path or the destructive path, **recomputing counts and re-checking entanglement server-side**, failing closed. The confirm word is a controller constant.

- [ ] **Step 1** — Write failing request specs. `spec/requests/hujah_visibility_change_spec.rb`:
  ```ruby
  require "rails_helper"

  RSpec.describe "Change hoojah visibility", type: :request do
    let(:owner) { create(:user, username: "owner") }
    let(:follower) { create(:user, username: "follower") }
    let(:stranger) { create(:user, username: "stranger") }
    def sign_in_fresh(u) = sign_in(User.find(u.id))
    def accept_follow(from:, to:) = from.active_follows.create!(followed: to, status: :accepted)

    describe "loosening never purges" do
      it "widens the audience and touches no votes/arguments" do
        h = create(:hujah, user: owner, visibility: :followers_only)
        h.cast_vote(by: stranger, choice: 1) # stranger is a non-follower voter
        sign_in_fresh owner
        expect {
          patch "/hoojah/#{h.slug}/visibility", params: {hujah: {visibility: "visible_public"}}
        }.not_to change(HujahArchive, :count)
        expect(h.reload.visibility).to eq("visible_public")
        expect(Vote.exists?(hujah_id: h.id, user_id: stranger.id)).to be(true)
      end
    end

    describe "tightening happy path" do
      it "purges after the confirm word is typed" do
        h = create(:hujah, user: owner, visibility: :visible_public)
        h.cast_vote(by: stranger, choice: 1)
        sign_in_fresh owner
        expect {
          patch "/hoojah/#{h.slug}/visibility",
            params: {hujah: {visibility: "private_only"}, confirm: HujahsController::VISIBILITY_CONFIRM_WORD}
        }.to change(HujahArchive, :count).by(1)
        expect(h.reload.visibility).to eq("private_only")
        expect(Vote.exists?(hujah_id: h.id, user_id: stranger.id)).to be(false)
      end
    end

    describe "fail closed" do
      it "does NOT purge when the confirm word is wrong" do
        h = create(:hujah, user: owner, visibility: :visible_public)
        h.cast_vote(by: stranger, choice: 1)
        sign_in_fresh owner
        expect {
          patch "/hoojah/#{h.slug}/visibility",
            params: {hujah: {visibility: "private_only"}, confirm: "nope"}
        }.not_to change(HujahArchive, :count)
        expect(h.reload.visibility).to eq("visible_public")
        expect(response).to redirect_to(visibility_hujah_path(h.slug, to: "private_only"))
      end

      it "blocks when an affected argument is entangled, even with the confirm word" do
        h = create(:hujah, user: owner, visibility: :visible_public)
        h.cast_vote(by: stranger, choice: 1)
        arg = create(:hujah, user: stranger, parent_id: h.id, body: "An entangled argument")
        arg.cast_vote(by: create(:user), choice: 2)
        sign_in_fresh owner
        expect {
          patch "/hoojah/#{h.slug}/visibility",
            params: {hujah: {visibility: "private_only"}, confirm: HujahsController::VISIBILITY_CONFIRM_WORD}
        }.not_to change(HujahArchive, :count)
        expect(h.reload.visibility).to eq("visible_public")
      end

      it "unblocks after the argument owner promotes the entangled argument" do
        h = create(:hujah, user: owner, visibility: :visible_public)
        h.cast_vote(by: stranger, choice: 1)
        arg = create(:hujah, user: stranger, parent_id: h.id, body: "An entangled argument")
        arg.cast_vote(by: create(:user), choice: 2)
        arg.promote! # argument owner detaches it → no longer in the subtree
        sign_in_fresh owner
        expect {
          patch "/hoojah/#{h.slug}/visibility",
            params: {hujah: {visibility: "private_only"}, confirm: HujahsController::VISIBILITY_CONFIRM_WORD}
        }.to change(HujahArchive, :count).by(1)
        expect(h.reload.visibility).to eq("private_only")
      end
    end

    describe "authorization + form" do
      it "renders the confirmation counts on the edit screen for a tighten target" do
        h = create(:hujah, user: owner, visibility: :visible_public)
        h.cast_vote(by: stranger, choice: 1)
        sign_in_fresh owner
        get "/hoojah/#{h.slug}/visibility", params: {to: "private_only"}
        expect(response.body).to include("1") # 1 user affected
        expect(response.body).to include(HujahsController::VISIBILITY_CONFIRM_WORD)
      end

      it "denies a non-owner" do
        h = create(:hujah, user: owner, visibility: :visible_public)
        sign_in_fresh stranger
        get "/hoojah/#{h.slug}/visibility"
        expect(response).to have_http_status(:redirect)
      end
    end
  end
  ```

- [ ] **Step 2** — Run; expect FAIL (routing error / missing constant).
  ```
  mise exec ruby@3.4.9 -- env RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/hujah_visibility_change_spec.rb
  ```

- [ ] **Step 3** — Add routes. In `config/routes.rb`, after the `promote` route from Task 7:
  ```ruby
    # Change a top-level hoojah's visibility (Slice 2, editable-hujah). GET renders the
    # change form; when `?to=` names a TIGHTER audience it doubles as the confirmation
    # screen (exact counts + entanglement blockers + typed-confirm). PATCH applies it.
    # WRITE → MAIN routes (CSRF on), never Api::V1. Owner + top-level + not-removed via
    # HujahPolicy#change_visibility?. update_visibility RE-COMPUTES counts and RE-CHECKS
    # entanglement server-side inside VisibilityChange#apply!'s row lock — never trusting
    # the client — and fails closed. Only the GET is named (the PATCH shares the path).
    get "/hoojah/:slug/visibility", to: "hujahs#visibility_edit", as: :visibility_hujah
    patch "/hoojah/:slug/visibility", to: "hujahs#update_visibility"
  ```

- [ ] **Step 4** — Add the controller constant + actions. In `app/controllers/hujahs_controller.rb`:
  ```ruby
    # The word the owner must type to confirm a destructive (tightening) visibility
    # change. A deliberate friction step; the server compares against it verbatim.
    VISIBILITY_CONFIRM_WORD = "REMOVE"
  ```
  ```ruby
    def visibility_edit
      @hujah = Hujah.friendly.find(params[:slug])
      authorize @hujah, :change_visibility?
      # When a candidate value is present, build the change so the view can render the
      # exact counts + entanglement blockers + typed-confirm affordance for a tighten.
      if params[:to].present? && Hujah.visibilities.key?(params[:to])
        @change = VisibilityChange.new(@hujah, to: params[:to])
      end
    end

    def update_visibility
      @hujah = Hujah.friendly.find(params[:slug])
      authorize @hujah, :change_visibility?
      to = params.require(:hujah).permit(:visibility)[:visibility]

      unless Hujah.visibilities.key?(to)
        redirect_to visibility_hujah_path(@hujah.slug), alert: "Unknown visibility." and return
      end

      change = VisibilityChange.new(@hujah, to: to)

      if change.no_op?
        redirect_to hujah_path(@hujah.slug), notice: "Visibility unchanged.", status: :see_other
      elsif change.loosening?
        # Widening the audience is non-destructive — just update the column.
        @hujah.update!(visibility: to)
        redirect_to hujah_path(@hujah.slug), notice: "Visibility updated.", status: :see_other
      else
        # Tightening: fail closed on entanglement, then on a wrong/absent confirm word.
        # VisibilityChange#apply! re-derives BOTH under its row lock; these pre-checks
        # give the owner the confirmation screen back rather than a 500.
        if change.blockers.any?
          redirect_to visibility_hujah_path(@hujah.slug, to: to),
            alert: "Resolve the entangled arguments before tightening." and return
        end
        if params[:confirm] != VISIBILITY_CONFIRM_WORD
          redirect_to visibility_hujah_path(@hujah.slug, to: to),
            alert: "Type #{VISIBILITY_CONFIRM_WORD} to confirm the permanent removal." and return
        end
        begin
          change.apply!
          redirect_to hujah_path(@hujah.slug),
            notice: "Visibility tightened. Affected participation was permanently removed.",
            status: :see_other
        rescue VisibilityChange::Blocked
          # A new entanglement appeared between the pre-check and the lock — fail closed.
          redirect_to visibility_hujah_path(@hujah.slug, to: to),
            alert: "An argument became entangled — the change was blocked.", status: :see_other
        end
      end
    end
  ```

- [ ] **Step 5** — Add the view. `app/views/hujahs/visibility_edit.html.erb`:
  ```erb
  <%# Change-visibility form (Slice 2). When @change is set AND tightens, this is also
      the confirmation screen: exact counts, entanglement blockers, and the typed-confirm
      field. No JS required — the select submits back here with ?to=, then to PATCH. %>
  <div class="max-w-xl mx-auto p-4">
    <%= render layout: "ui/card", locals: {padded: true} do %>
      <h1 class="text-lg font-semibold text-ink mb-2">Change visibility</h1>
      <p class="text-sm text-muted mb-4">Current: <strong><%= @hujah.visibility.humanize %></strong></p>

      <%# Step 1 — pick a target. Submitting reloads this page with ?to= so the server can
          compute the confirmation for a tighten. %>
      <%= form_with url: visibility_hujah_path(@hujah.slug), method: :get do |f| %>
        <%= f.select :to, Hujah.visibilities.keys.map { |k| [k.humanize, k] }, {selected: params[:to]},
              class: "w-full rounded-xl border border-hairline p-2" %>
        <%= f.submit "Preview change", class: ds_button_classes(tone: "neutral") %>
      <% end %>

      <% if @change %>
        <% if @change.loosening? || @change.no_op? %>
          <%# Non-destructive — one-tap apply. %>
          <%= form_with url: visibility_hujah_path(@hujah.slug), method: :patch, class: "mt-4" do |f| %>
            <%= f.hidden_field "hujah[visibility]", value: @change.to %>
            <%= f.submit "Apply", class: ds_button_classes(tone: "primary") %>
          <% end %>
        <% else %>
          <%# Destructive tighten — counts, blockers, typed-confirm. %>
          <% counts = @change.counts %>
          <div class="mt-4 p-3 rounded-xl bg-surface-2 text-sm">
            <p class="font-medium text-ink">This permanently removes:</p>
            <ul class="list-disc ml-5 text-muted">
              <li><strong><%= counts[:users] %></strong> participant(s)</li>
              <li><strong><%= counts[:votes] %></strong> vote(s)</li>
              <li><strong><%= counts[:arguments] %></strong> argument(s)</li>
            </ul>
          </div>

          <% if @change.blockers.any? %>
            <div class="mt-4 p-3 rounded-xl border border-hairline text-sm">
              <p class="font-medium text-disagree">Blocked — these arguments are entangled with
                other people's replies, votes, or a debate. Their authors must delete or promote them:</p>
              <ul class="list-disc ml-5 text-muted">
                <% @change.blockers.each do |arg| %>
                  <li><%= link_to truncate(arg.body, length: 60), hujah_path(arg.slug) %></li>
                <% end %>
              </ul>
            </div>
          <% else %>
            <%= form_with url: visibility_hujah_path(@hujah.slug), method: :patch, class: "mt-4" do |f| %>
              <%= f.hidden_field "hujah[visibility]", value: @change.to %>
              <label class="block text-sm text-muted mb-1">
                Type <strong><%= HujahsController::VISIBILITY_CONFIRM_WORD %></strong> to confirm:
              </label>
              <%= f.text_field :confirm, class: "w-full rounded-xl border border-hairline p-2 mb-3" %>
              <%= f.submit "Tighten visibility permanently", class: ds_button_classes(tone: "neutral") %>
            <% end %>
          <% end %>
        <% end %>
      <% end %>
    <% end %>
  </div>
  ```
  > NOTE: verify `ds_button_classes` tone names and the `bg-surface-2`/`text-disagree`/`border-hairline` tokens against the current design system (`app/assets/tailwind/application.css` + `DesignSystemHelper`) before finalizing — substitute the live token names if these differ. Any interpolated stance utility here must already be in the `@source inline(...)` safelist; this view uses only static utilities, so no new safelist entry is needed.

- [ ] **Step 6** — Run; expect PASS. Run StandardRB `--fix` on the controller. Commit: `Slice 2 Task 8.1: visibility_edit + update_visibility, confirmation view, server re-check`

---

## Task 9 — show redirect-to-archive + HujahArchivesController + archive view + Cable leak spec

**Files:** `app/controllers/hujahs_controller.rb`, `app/controllers/hujah_archives_controller.rb`, `app/policies/hujah_archive_policy.rb`, `app/views/hujah_archives/show.html.erb`, `config/routes.rb`, `spec/requests/hujah_archive_redirect_spec.rb`, `spec/channels/debate_channel_purge_spec.rb`

A purged participant hitting the live post (or an old slug that 301s to it) is redirected to their frozen archive. The `DebateChannel` gate (`DebatePolicy#show?` → `record.hujah.visible_to?(user)`) already rejects them once the hujah is tightened — add a leak spec proving it.

- [ ] **Step 1** — Write failing request + channel specs.

  `spec/requests/hujah_archive_redirect_spec.rb`:
  ```ruby
  require "rails_helper"

  RSpec.describe "Purged participant redirect to archive", type: :request do
    let(:owner) { create(:user, username: "owner") }
    let(:stranger) { create(:user, username: "stranger") }
    def sign_in_fresh(u) = sign_in(User.find(u.id))

    def purge_stranger!(hujah)
      hujah.cast_vote(by: stranger, choice: 1)
      VisibilityChange.new(hujah, to: "private_only").apply!
    end

    it "redirects a purged user from the live post to their frozen archive" do
      h = create(:hujah, user: owner, visibility: :visible_public, body: "Contested claim here")
      purge_stranger!(h)

      sign_in_fresh stranger
      get "/hoojah/#{h.slug}"
      expect(response).to redirect_to("/hoojah/#{h.slug}/archived")
    end

    it "renders the FULL frozen post (incl. the purged user's own vote/args) on the archive" do
      h = create(:hujah, user: owner, visibility: :visible_public, body: "Contested claim here")
      create(:hujah, user: stranger, parent_id: h.id, body: "Strangers own argument text")
      purge_stranger!(h)

      sign_in_fresh stranger
      get "/hoojah/#{h.slug}/archived"
      expect(response.body).to include("Contested claim here")
      expect(response.body).to include("Strangers own argument text")
    end

    it "does NOT redirect a still-visible user (owner sees the live post)" do
      h = create(:hujah, user: owner, visibility: :visible_public, body: "Contested claim here")
      purge_stranger!(h)
      sign_in_fresh owner
      get "/hoojah/#{h.slug}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Contested claim here")
    end

    it "a non-participant stranger cannot reach the archive" do
      h = create(:hujah, user: owner, visibility: :visible_public, body: "Contested claim here")
      purge_stranger!(h)
      outsider = create(:user, username: "outsider")
      sign_in_fresh outsider
      get "/hoojah/#{h.slug}/archived"
      expect(response).to have_http_status(:redirect) # policy denies; no archive for them
    end
  end
  ```

  `spec/channels/debate_channel_purge_spec.rb`:
  ```ruby
  require "rails_helper"

  RSpec.describe DebateChannel, type: :channel do
    let(:owner) { create(:user, username: "owner") }
    let(:spectator) { create(:user, username: "spectator") }
    let(:foe) { create(:user, username: "foe") }

    def subscribe_to(debate)
      subscribe(signed_stream_name: Turbo::StreamsChannel.signed_stream_name(debate))
    end

    it "stops streaming an active debate to a spectator purged by a visibility tighten" do
      hujah = create(:hujah, user: owner, visibility: :visible_public)
      debate = create(:debate, hujah: hujah, challenger: owner, opponent: foe, status: :active)

      # A public spectator can subscribe today (DebatePolicy#show? admits them).
      hujah.cast_vote(by: spectator, choice: 1)
      stub_connection current_user: spectator
      subscribe_to(debate)
      expect(subscription).to be_confirmed

      # Tighten to private_only → the spectator is purged and can no longer see the
      # claim, so hujah.visible_to? fails and the Cable gate rejects the re-subscribe.
      VisibilityChange.new(hujah, to: "private_only").apply!
      stub_connection current_user: User.find(spectator.id)
      subscribe_to(debate)
      expect(subscription).to be_rejected
    end
  end
  ```

- [ ] **Step 2** — Run both; expect FAIL (routing/const errors).
  ```
  mise exec ruby@3.4.9 -- env RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/requests/hujah_archive_redirect_spec.rb spec/channels/debate_channel_purge_spec.rb
  ```

- [ ] **Step 3** — Add the archive route. In `config/routes.rb`, after the visibility routes:
  ```ruby
    # Frozen read-only archive of a tightened hoojah (Slice 2, editable-hujah). Resolves
    # the VIEWER's latest archive for :slug (HujahArchiveParticipant.for). A purged user
    # who hits the live post is redirected here by HujahsController#show; old slugs 301
    # via FriendlyId :history and then hit that same gate. Read-only, no actions; MAIN
    # route (never Api::V1). Addressed by the hoojah's slug — the archive it maps to is
    # per-viewer, so no archive token appears in the URL.
    get "/hoojah/:slug/archived", to: "hujah_archives#show", as: :hujah_archive
  ```

- [ ] **Step 4** — Add the redirect gate to `HujahsController#show` (top of the method, before `authorize`):
  ```ruby
    def show
      @hujah = Hujah.friendly.find(params[:slug])
      # Slice 2 (editable-hujah): a participant purged by a visibility tighten can no
      # longer see the live post — but they ARE entitled to their frozen archive. Route
      # them there instead of the generic not-authorized redirect. `skip_authorization`
      # satisfies verify_authorized on this early-return branch (no `authorize` runs).
      if !@hujah.visible_to?(current_user) && HujahArchiveParticipant.for(current_user, @hujah).exists?
        skip_authorization
        redirect_to hujah_archive_path(@hujah.slug) and return
      end
      authorize @hujah
      @children = @hujah.visible_children_for(current_user)
      @debates = policy_scope(@hujah.debates)
    end
  ```

- [ ] **Step 5** — Add the policy. `app/policies/hujah_archive_policy.rb`:
  ```ruby
  # frozen_string_literal: true

  # A frozen archive is readable only by a user who was PURGED into it — i.e. has a
  # participant row for it (Slice 2). Defense in depth: HujahArchivesController#show
  # already resolves the archive via HujahArchiveParticipant.for(current_user, hujah),
  # but this re-checks the (user, archive) mapping so a hand-crafted request can't read
  # someone else's archive.
  class HujahArchivePolicy < ApplicationPolicy
    def show? = user.present? && record.participants.exists?(user_id: user.id)
  end
  ```

- [ ] **Step 6** — Add the controller. `app/controllers/hujah_archives_controller.rb`:
  ```ruby
  class HujahArchivesController < ApplicationController
    before_action :authenticate_user!

    def show
      hujah = Hujah.friendly.find(params[:slug])
      # Resolve THIS viewer's latest archive for the hoojah. Nil when they were never
      # purged into one → skip_authorization + redirect (verify_authorized satisfied on
      # the nil branch; authorize runs exactly once on the found branch).
      participant = HujahArchiveParticipant.for(current_user, hujah).first
      @archive = participant&.archive
      if @archive.nil?
        skip_authorization
        redirect_to root_path, alert: "No archive found." and return
      end
      authorize @archive, :show?
    end
  end
  ```

- [ ] **Step 7** — Add the view. `app/views/hujah_archives/show.html.erb`:
  ```erb
  <%# Read-only frozen snapshot of a tightened hoojah (Slice 2). Renders entirely from
      @archive.snapshot (jsonb) — no live records, no actions. This is the faithful record
      of what the purged viewer participated in, including their own vote and arguments. %>
  <% snap = @archive.snapshot %>
  <div class="max-w-xl mx-auto p-4">
    <div class="mb-3 text-xs text-muted uppercase tracking-wide">Archived · read-only</div>
    <%= render layout: "ui/card", locals: {padded: true} do %>
      <div class="text-sm text-muted mb-1">@<%= snap["author"] %></div>
      <p class="text-ink whitespace-pre-line"><%= snap["body"] %></p>
      <div class="mt-3 text-sm text-muted">
        <%= snap.dig("stance_labels", "agree") %>: <%= snap["agree_count"] %> ·
        <%= snap.dig("stance_labels", "neutral") %>: <%= snap["neutral_count"] %> ·
        <%= snap.dig("stance_labels", "disagree") %>: <%= snap["disagree_count"] %>
      </div>
    <% end %>

    <% if snap["arguments"].present? %>
      <h2 class="mt-6 mb-2 text-sm font-semibold text-ink">Arguments</h2>
      <%= render "hujah_archives/argument_tree", args: snap["arguments"] %>
    <% end %>
  </div>
  ```
  and the recursive partial `app/views/hujah_archives/_argument_tree.html.erb`:
  ```erb
  <ul class="space-y-2">
    <% args.each do |arg| %>
      <li>
        <%= render layout: "ui/card", locals: {padded: true} do %>
          <div class="text-sm text-muted mb-1">@<%= arg["author"] %> · <%= arg["stance"] %></div>
          <p class="text-ink whitespace-pre-line"><%= arg["body"] %></p>
        <% end %>
        <% if arg["children"].present? %>
          <div class="ml-4 mt-2">
            <%= render "hujah_archives/argument_tree", args: arg["children"] %>
          </div>
        <% end %>
      </li>
    <% end %>
  </ul>
  ```

- [ ] **Step 8** — Run both spec files; expect PASS. Commit: `Slice 2 Task 9.1: archive redirect gate, HujahArchivesController + view, Cable leak spec`

---

## Task 10 — Owner-menu wiring + system spec of the confirm flow

**Files:** `app/views/hujahs/show.html.erb`, `spec/system/change_visibility_spec.rb`

- [ ] **Step 1** — Write a failing system spec. `spec/system/change_visibility_spec.rb`:
  ```ruby
  require "rails_helper"

  RSpec.describe "Change visibility flow", type: :system, js: true do
    let(:owner) { create(:user, username: "owner", password: "hoojah88") }
    let(:stranger) { create(:user, username: "stranger") }

    def login(user)
      visit "/login"
      fill_in "user[email]", with: user.email
      fill_in "user[password]", with: "hoojah88"
      click_button "Log in"
    end

    it "lets the owner tighten a public claim after typing the confirm word" do
      hujah = create(:hujah, user: owner, visibility: :visible_public, body: "System-spec claim body")
      hujah.cast_vote(by: stranger, choice: 1)

      login(owner)
      visit "/hoojah/#{hujah.slug}/visibility?to=private_only"
      expect(page).to have_content("permanently removes")
      fill_in "confirm", with: "REMOVE"
      click_button "Tighten visibility permanently"

      expect(page).to have_current_path("/hoojah/#{hujah.slug}")
      expect(hujah.reload.visibility).to eq("private_only")
      expect(Vote.exists?(hujah_id: hujah.id, user_id: stranger.id)).to be(false)
    end

    it "shows the Change visibility menu item only to a top-level owner" do
      hujah = create(:hujah, user: owner, visibility: :visible_public, body: "Menu-visibility claim")
      login(owner)
      visit "/hoojah/#{hujah.slug}"
      expect(page).to have_link("Change visibility")
    end
  end
  ```
  > NOTE: match the login field selectors + submit-button label to the app's real `/login` form and the confirm-field DOM `id` Rails emits for `f.text_field :confirm` (likely `confirm`); adjust if the actual markup differs.

- [ ] **Step 2** — Run; expect FAIL (no "Change visibility" link).
  ```
  mise exec ruby@3.4.9 -- env RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec spec/system/change_visibility_spec.rb
  ```

- [ ] **Step 3** — Add the owner-menu item. In `app/views/hujahs/show.html.erb`, inside the owner-only menu block (after the existing "Delete hoojah" `button_to`, still within `if user_signed_in? && @hujah.user_id == current_user.id`):
  ```erb
              <%# Slice 2 (editable-hujah): visibility is a TOP-LEVEL-only affordance — a
                  reply inherits its parent's visibility. A read-only link to the change
                  form (which becomes the destructive confirmation screen on a tighten). %>
              <% if @hujah.parent_id.nil? && !@hujah.moderation_removed? %>
                <%= link_to "Change visibility", visibility_hujah_path(@hujah.slug),
                      class: ds_menu_item_classes %>
              <% end %>
  ```

- [ ] **Step 4** — Run; expect PASS.

- [ ] **Step 5** — Run the full Slice-2 spec set + gates:
  ```
  mise exec ruby@3.4.9 -- env RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec \
    spec/models/hujah_archive_spec.rb spec/models/notification_spec.rb \
    spec/services/visibility_change_spec.rb spec/policies/hujah_policy_visibility_spec.rb \
    spec/requests/hujah_promote_spec.rb spec/requests/hujah_visibility_change_spec.rb \
    spec/requests/hujah_archive_redirect_spec.rb spec/channels/debate_channel_purge_spec.rb
  mise exec ruby@3.4.9 -- bundle exec standardrb
  mise exec ruby@3.4.9 -- bundle exec brakeman -q
  ```
  All green. (System spec runs under `bin/ci --only-system-specs`.)

- [ ] **Step 6** — Commit: `Slice 2 Task 10.1: owner-menu Change visibility item + confirm-flow system spec`

---

## Cross-cutting checks (do before declaring Slice 2 done)

- [ ] **Prosopite N+1 baseline** — the purge/archive paths add loops (per-affected-user inserts, subtree traversal). Run a purge-heavy spec, then `grep -c 'N+1 queries detected' log/prosopite.log`; keep the count from climbing past the Slice-10 baseline (146). Prosopite is **log-only** — do not turn it into a failing gate.
- [ ] **Tailwind** — the new ERB views use only static utilities. Confirm no new interpolated stance classes were introduced (no `@source inline(...)` change needed). Verify token names (`bg-surface-2`, `text-disagree`, `border-hairline`, `ds_button_classes` tones, `ds_menu_item_classes`) against the live design system before finalizing the views.
- [ ] **Full `bin/ci`** — run once at the end; it is the definition of green (StandardRB, Brakeman, bundler-audit, db:test:prepare, tailwind build, all specs).
- [ ] **Shared test DB** — all agents share one Postgres test DB; run the targeted spec files above rather than the full suite while iterating, to avoid `PG::ObjectInUse`.
