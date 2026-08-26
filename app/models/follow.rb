# Counter-cache contract (gap 8 — see the plan's invariant checklist in
# docs/superpowers/plans/2026-08-26-slice-c-follow-gaps.md):
#   users.followers_count == user.passive_follows.accepted.count
#   users.following_count == user.active_follows.accepted.count
# The columns are ACCEPTED-ONLY, so we cannot use Rails' built-in `counter_cache:`
# (it counts every row, pending included). Instead the three callbacks below keep the
# columns in step with the accepted-only scopes. They are deliberately IN-TRANSACTION
# (after_create/after_update/after_destroy — NOT the _commit variants): a rolled-back
# write must roll back its deltas too, so the counts move atomically with the row.
# Any caller that skips these callbacks — a `delete_all`/`update_all`/`insert_all` on
# `follows` — OWNS its own explicit adjustment in the same transaction (today the only
# such caller is BlocksController#create; see the invariant checklist before adding
# another).
class Follow < ApplicationRecord
  belongs_to :follower, class_name: "User"
  belongs_to :followed, class_name: "User"

  # A follow of a private user starts `pending` (request→approve); a follow of a
  # public user is set `accepted` by the controller. The DB default is pending
  # (security-conservative: a forgotten status is inert, never a leak).
  enum :status, {pending: 0, accepted: 1}

  validates :followed_id, uniqueness: {scope: :follower_id}
  validate :not_self

  # ALL follow notifications/badges live here, gated on ACCEPTED. An accepted follow
  # (public target) fires new_follower + the first_follower badge; a pending follow
  # (private target) fires only a follow_request to the target — NEVER new_follower or
  # the badge (the v1 bug: the badge/notification used to fire on the request itself).
  after_create_commit :notify_new_follow
  # Accepting a request (pending -> accepted) tells the requester + belatedly runs the
  # new_follower + first_follower side effects that were withheld while pending.
  after_update_commit :notify_accepted, if: -> { saved_change_to_status? && accepted? }

  # Counter caches. IN-TRANSACTION (not _commit) so a rolled-back write rolls back its
  # deltas — notifications above stay on _commit (outbound side effects) on purpose;
  # counters are transactional state. Accepted-only: pending rows move nothing.
  after_create :increment_counters, if: :accepted?
  after_update :adjust_counters_for_status_change, if: :saved_change_to_status?
  after_destroy :decrement_counters, if: :accepted?

  # The follow_request notification for this row has been actioned (accepted,
  # declined, cancelled, or expired) — remove it so its card disappears. Returns the
  # destroyed rows so a Turbo caller can also remove their cards from the DOM.
  def dismiss_request_notification!
    Notification.where(user_id: followed_id, subject_user_id: follower_id,
      category: :follow_request).destroy_all
  end

  private

  # Atomic SQL (UPDATE ... SET x = x + n) — no callbacks/validations, race-free.
  def increment_counters
    User.update_counters(followed_id, followers_count: 1)
    User.update_counters(follower_id, following_count: 1)
  end

  def decrement_counters
    User.update_counters(followed_id, followers_count: -1)
    User.update_counters(follower_id, following_count: -1)
  end

  def adjust_counters_for_status_change
    # pending→accepted is the only transition the app performs; accepted→pending is
    # handled anyway so a future/console write can't silently corrupt the counts.
    accepted? ? increment_counters : decrement_counters
  end

  def not_self
    errors.add(:followed_id, "can't follow yourself") if follower_id == followed_id
  end

  def notify_new_follow
    if accepted?
      notify_followed
      award_first_follower
    else
      Notification.create!(user_id: followed_id, category: :follow_request, subject_user_id: follower_id)
    end
  end

  def notify_accepted
    Notification.create!(user_id: follower_id, category: :follow_accepted, subject_user_id: followed_id)
    notify_followed
    award_first_follower
  end

  def notify_followed
    Notification.create!(user_id: followed_id, category: :new_follower, subject_user_id: follower_id)
  end

  def award_first_follower
    UserBadge.award(followed, "first_follower")
  end
end
