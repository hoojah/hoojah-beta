class ExpireStaleFollowRequestsJob < ApplicationJob
  # Expire follow requests that sat unanswered for 30+ days. destroy (not
  # delete_all) so Follow's callbacks run - a pending row adjusts no counters
  # (accepted-only guard), and destroying fires no notification. The requester is
  # deliberately NOT told (mirrors decline's no-blast convention); the target's
  # stale request card is dismissed. Per-row rescue+log (like
  # ConcludeStaleDebatesJob) so one bad row never wedges the sweep.
  def perform
    Follow.pending.where(created_at: ...30.days.ago).find_each do |follow|
      follow.dismiss_request_notification!
      follow.destroy
    rescue => e
      Rails.logger.error("ExpireStaleFollowRequestsJob: failed to expire follow #{follow.id}: #{e.class}: #{e.message}")
    end
  end
end
