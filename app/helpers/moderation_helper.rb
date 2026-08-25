module ModerationHelper
  # Hujahs awaiting review (not raw reports): distinct flagged hujahs with a
  # pending flag. Computed on read — queue volume at beta scale doesn't earn a cache.
  # Reused by the queue header, the dismiss/remove/warn Turbo Streams, and (Task 4.1)
  # the staff-only navbar entry.
  def pending_moderation_count
    Flag.pending.distinct.count(:hujah_id)
  end
end
