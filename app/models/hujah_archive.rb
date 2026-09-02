# A frozen, read-only snapshot of a top-level hoojah captured the instant its author
# TIGHTENED visibility (Slice 2, editable-hujah). `hujah_id` is a plain integer with
# NO database FK (mirrors notifications.hujah_id): the archive is the permanent record
# a purged participant is entitled to read, so it must survive the live hoojah's later
# deletion. Immutable after creation — nothing edits `snapshot`.
class HujahArchive < ApplicationRecord
  has_many :participants, class_name: "HujahArchiveParticipant",
    foreign_key: :archive_id, dependent: :destroy

  validates :token, presence: true, uniqueness: true
  validates :snapshot, presence: true
  validates :visibility_before, presence: true
end
