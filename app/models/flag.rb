class Flag < ApplicationRecord
  belongs_to :user
  belongs_to :hujah
  # Moderation (2026): the staff member who resolved this report. Optional — a
  # pending flag has no resolver yet.
  belongs_to :resolved_by, class_name: "User", optional: true

  enum :subject, {
    spam: 0,
    abusive: 1,
    irrelevant: 2
  }

  # Moderation (2026): the review lifecycle. `pending` is the enum-generated scope
  # (do NOT also hand-define one — that raises "already defined").
  enum :status, {pending: 0, dismissed: 1, actioned: 2}, default: :pending

  # One report per user per hoojah — backed by the unique [user_id, hujah_id] index.
  validates :user_id, uniqueness: {scope: :hujah_id}

  # One write: lifecycle transition + audit fields together, so a flag can never
  # be resolved without recording who and when.
  def resolve!(by:, as:)
    update!(status: as, resolved_by: by, resolved_at: Time.current)
  end
end
