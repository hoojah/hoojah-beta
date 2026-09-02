module HujahArchivesHelper
  # The archived post's total vote count, summed from the frozen snapshot counts.
  def archive_total_votes(snap)
    snap["agree_count"].to_i + snap["neutral_count"].to_i + snap["disagree_count"].to_i
  end

  # Whether the archived per-stance breakdown may be shown — the SAME k-anonymity gate as
  # the live secret ballot (Hujah#breakdown_visible?), applied to the frozen snapshot so a
  # purged voter can't deduce a lone co-voter's stance. Kept in lockstep with the model's
  # VOTE_BREAKDOWN_MIN threshold.
  def archive_breakdown_visible?(snap)
    archive_total_votes(snap) >= Hujah::VOTE_BREAKDOWN_MIN
  end
end
