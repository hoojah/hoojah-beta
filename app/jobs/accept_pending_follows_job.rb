class AcceptPendingFollowsJob < ApplicationJob
  # Sets at or below this run inline in the request (users#update); larger sets go
  # to the queue so the flip's response doesn't stall on N notification writes.
  INLINE_THRESHOLD = 25

  # Accept every pending follow request aimed at `user` (private->public flip).
  # Per-row update! (NOT update_all) on purpose: the Follow model's callbacks carry
  # ALL the accept side effects - follow_accepted to the requester, new_follower +
  # first_follower badge to the target, and the accepted-only counter caches.
  # Per-row rescue+log (like ConcludeStaleDebatesJob) so one bad row never wedges
  # the batch.
  def perform(user)
    user.passive_follows.pending.find_each do |follow|
      follow.update!(status: :accepted)
      follow.dismiss_request_notification!
    rescue => e
      Rails.logger.error("AcceptPendingFollowsJob: failed to accept follow #{follow.id}: #{e.class}: #{e.message}")
    end
  end
end
