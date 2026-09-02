# Maps ONE purged user to the archive captured at their purge moment (Slice 2). The
# unique (archive_id, user_id) index makes re-insertion a no-op guard. `.for` resolves
# "does this viewer have a frozen archive for this hoojah, and which is the latest"
# — used by HujahsController#show (redirect gate) and HujahArchivesController#show.
class HujahArchiveParticipant < ApplicationRecord
  belongs_to :archive, class_name: "HujahArchive"
  belongs_to :user

  # Latest-first participant rows for (user, hujah). A user re-admitted by a later
  # loosening and purged again maps to their MOST RECENT archive: order by the archive's
  # created_at desc (id desc tiebreaker) so `.first` is the newest.
  def self.for(user, hujah)
    return none if user.nil?
    joins(:archive)
      .where(user_id: user.id, hujah_archives: {hujah_id: hujah.id})
      .order("hujah_archives.created_at DESC, hujah_archives.id DESC")
  end
end
