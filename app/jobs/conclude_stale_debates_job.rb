class ConcludeStaleDebatesJob < ApplicationJob
  # Auto-conclude debates that have gone idle (no accepted turn or status change)
  # for more than 7 days. `updated_at` is touch-tracked by DebateTurn, so it
  # reflects the last turn — an actively-argued debate is never swept. by: nil is
  # the system path (notifies both participants, no actor to exclude).
  def perform
    Debate.active.where("updated_at < ?", 7.days.ago).find_each do |debate|
      debate.conclude!(by: nil)
    end
  end
end
