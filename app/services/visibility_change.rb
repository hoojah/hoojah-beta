# Encapsulates a top-level hoojah's visibility change (Slice 2, editable-hujah).
# LOOSENING just updates the column. TIGHTENING is destructive: it purges the votes
# and subtree arguments of every participant who loses access, snapshots the pre-change
# post, and notifies them. The service owns three concerns so they are unit-testable in
# isolation and cannot drift from the controller's server-side re-check:
#   - #affected_participants / #counts : who loses access and how much is removed
#   - #blockers                        : entangled arguments that FAIL the change closed
#   - #apply!                          : the row-locked purge transaction
class VisibilityChange
  class Blocked < StandardError; end

  class NotTightening < StandardError; end

  def initialize(hujah, to:)
    @hujah = hujah
    @to = to.to_s
  end

  attr_reader :hujah, :to

  # Direction by enum RANK — the enum integers are the audience order
  # (visible_public 0 < followers_only 1 < private_only 2), so a larger target rank
  # is a narrower audience = tightening.
  def from_rank = Hujah.visibilities.fetch(hujah.visibility)

  def to_rank = Hujah.visibilities.fetch(@to)

  def no_op? = to_rank == from_rank

  def loosening? = to_rank < from_rank

  def tightening? = to_rank > from_rank

  # Users (≠ author) who voted on the top-level hoojah OR authored a subtree argument,
  # and who — evaluated PROSPECTIVELY against the candidate visibility — can no longer
  # see the post. The author is never affected.
  def affected_participants
    @affected_participants ||= candidate_users.reject { |u| visible_under?(u, @to) }
  end

  def affected_participant_ids = affected_participants.map(&:id)

  def counts
    ids = affected_participant_ids.to_set
    {
      users: ids.size,
      votes: hujah.votes.where(user_id: ids.to_a).count,
      arguments: subtree_hujahs.count { |h| ids.include?(h.user_id) }
    }
  end

  # Affected arguments that are ENTANGLED with other users' participation. A non-empty
  # result FAILS the change closed (design: the whole change is blocked). Resolution is
  # the ARGUMENT OWNER's: delete it or promote it to a standalone top-level hoojah.
  def blockers
    @blockers ||= affected_arguments.select { |arg| entangled?(arg) }
  end

  private

  def affected_arguments
    ids = affected_participant_ids.to_set
    subtree_hujahs.select { |h| ids.include?(h.user_id) }
  end

  # Entangled = carries OTHER users' content that a purge would wrongly destroy: a reply
  # or vote from someone other than the arg's own author, or ANY debate (a debate always
  # couples two users and its transcript is shared content). `.exists?` issues an EXISTS,
  # not a load.
  def entangled?(arg)
    arg.children.where.not(user_id: arg.user_id).exists? ||
      arg.votes.where.not(user_id: arg.user_id).exists? ||
      arg.debates.exists?
  end

  def candidate_users
    @candidate_users ||= User.where(id: candidate_ids).to_a
  end

  def candidate_ids
    @candidate_ids ||= begin
      voter_ids = hujah.votes.distinct.pluck(:user_id)
      author_ids = subtree_hujahs.map(&:user_id)
      (voter_ids + author_ids).uniq - [hujah.user_id]
    end
  end

  # The whole descendant set of the top-level hoojah, breadth-first (depth-bounded,
  # a handful of queries — not per-record N+1). Excludes the top hoojah itself.
  def subtree_hujahs
    @subtree_hujahs ||= begin
      collected = []
      frontier = hujah.children.select(:id, :parent_id, :user_id).to_a
      until frontier.empty?
        collected.concat(frontier)
        frontier = Hujah.where(parent_id: frontier.map(&:id)).select(:id, :parent_id, :user_id).to_a
      end
      collected
    end
  end

  # The author's accepted-follower ids, loaded ONCE (accepted-only `followers` through
  # scope), so the affected-set scan tests membership in Ruby instead of a per-viewer
  # accepted_follower? exists? query (the N+1 this repo otherwise batches).
  def author_follower_ids
    @author_follower_ids ||= hujah.user.follower_ids.to_set
  end

  # Batched equivalent of User#visible_to?: a non-private author is visible to anyone;
  # a private author only to themselves + accepted followers.
  def author_visible_to?(viewer)
    return true unless hujah.user.private?
    viewer.id == hujah.user_id || author_follower_ids.include?(viewer.id)
  end

  # Mirrors Hujah#visible_to?'s TOP-LEVEL branch with the CANDIDATE visibility, batched —
  # the hoojah is top-level and not removed, so no parent recursion / no moderation gate
  # applies. Kept in lockstep with that method: account privacy first, then the per-post
  # visibility case. Uses the preloaded author_follower_ids instead of a per-viewer
  # accepted_follower? query.
  def visible_under?(viewer, visibility)
    return false unless author_visible_to?(viewer)

    case visibility.to_s
    when "visible_public" then true
    when "followers_only" then viewer.id == hujah.user_id || author_follower_ids.include?(viewer.id)
    when "private_only" then viewer.id == hujah.user_id
    else false
    end
  end
end
