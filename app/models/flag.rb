class Flag < ApplicationRecord
  belongs_to :user
  belongs_to :hujah
  # Moderation (2026): the staff member who resolved this report. Optional — a
  # pending flag has no resolver yet.
  belongs_to :resolved_by, class_name: "User", optional: true

  enum :subject, {
    spam: 0,
    abusive: 1,
    irrelevant: 2,
    image_graphic: 3,
    image_not_theirs: 4
  }

  # Moderation (2026): the review lifecycle. `pending` is the enum-generated scope
  # (do NOT also hand-define one — that raises "already defined").
  enum :status, {pending: 0, dismissed: 1, actioned: 2}, default: :pending

  # One report per user per hoojah — backed by the unique [user_id, hujah_id] index.
  validates :user_id, uniqueness: {scope: :hujah_id}

  # Defense-in-depth (Slice 5): a subject-less flag is meaningless and a nil subject
  # is a real crash vector downstream (the serializer + moderation copy dereference it).
  # The frozen flag dialog always submits a subject, so this only rejects malformed
  # direct POSTs — it never breaks the real form.
  #
  # ON :create ONLY, deliberately. Legacy nil-subject rows can predate this validation
  # (subject is a nullable column with no DB constraint), and they must stay UPDATEABLE:
  # `resolve!`/`remove!` transition such rows via `update!`, and an unscoped presence
  # check would raise inside `Hujah#remove!`'s transaction and roll back the whole
  # removal — one poisoned legacy flag would make a hujah unremovable. Blocking new nil
  # subjects at create (belt) plus the controller's 422 guard (braces) is enough.
  validates :subject, presence: true, on: :create

  # One write: lifecycle transition + audit fields together, so a flag can never
  # be resolved without recording who and when.
  def resolve!(by:, as:)
    update!(status: as, resolved_by: by, resolved_at: Time.current)
  end
end
