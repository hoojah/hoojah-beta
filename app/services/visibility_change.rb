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
    {
      users: affected_participant_ids.size,
      votes: hujah.votes.where(user_id: affected_participant_ids).count,
      arguments: affected_arguments.size
    }
  end

  # Affected arguments that are ENTANGLED with other users' participation. A non-empty
  # result FAILS the change closed (design: the whole change is blocked). Resolution is
  # the ARGUMENT OWNER's: delete it or promote it to a standalone top-level hoojah.
  def blockers
    @blockers ||= affected_arguments.select { |arg| entangled?(arg) }
  end

  # The destructive purge, row-locked. Re-derives the affected set/blockers UNDER the
  # lock (fail closed on anything newly entangled between the confirmation GET and here)
  # and performs the ordered steps in one transaction. Returns the archive.
  def apply!
    raise NotTightening unless tightening?

    hujah.with_lock do
      reset_memos!
      raise Blocked if blockers.any?

      affected = affected_participants
      archive = HujahArchive.create!(
        hujah_id: hujah.id,
        snapshot: build_snapshot,                      # (2) from CURRENT state
        visibility_before: Hujah.visibilities.fetch(hujah.visibility),
        token: SecureRandom.urlsafe_base64(12)
      )
      affected.each { |u| archive.participants.create!(user_id: u.id) } # (3)

      affected_ids = affected.map(&:id)
      Vote.where(hujah_id: hujah.id, user_id: affected_ids).delete_all   # (4a)
      destroy_affected_arguments!(affected_ids.to_set)                   # (4b)
      recompute_counters!                                                # (5)
      hujah.update!(visibility: @to)                                     # (5 dirty counters + 6)

      affected.each do |u|                                               # (7)
        # Secret ballot: NO subject_user_id — this row must not become a
        # de-anonymization primitive; the category just says "your participation
        # was archived".
        Notification.create!(user_id: u.id, category: :hujah_archived, hujah_id: hujah.id)
      end
      archive
    end
  end

  private

  def reset_memos!
    @candidate_users = @candidate_ids = @subtree_hujahs = nil
    @affected_participants = @affected_arguments = @blockers = nil
    @author_follower_ids = nil
  end

  # Destroy only the ROOTS of each affected-argument subtree; dependent: :destroy
  # cascades their descendants. Safe because a non-blocked change guarantees no affected
  # argument carries another user's reply/vote/debate — so every descendant of an
  # affected root is the same (affected) author's content, never a bystander's.
  # subtree_hujahs holds PARTIAL records (select :id, :parent_id, :user_id) — reload the
  # full record via Hujah.find before destroy! so the cascade + callbacks see every column.
  def destroy_affected_arguments!(affected_ids)
    args = subtree_hujahs.select { |h| affected_ids.include?(h.user_id) }
    arg_ids = args.map(&:id).to_set
    roots = args.reject { |h| arg_ids.include?(h.parent_id) }
    roots.each { |root| Hujah.find(root.id).destroy! }
  end

  # Recount from scratch (design: safest). votes.vote is the legacy array column — the
  # LAST element is the current stance. assign_attributes leaves the counters dirty for
  # the single update! in #apply! that also writes visibility.
  def recompute_counters!
    remaining = hujah.votes.reload.to_a
    hujah.assign_attributes(
      agree_count: remaining.count { |v| v.vote.last == 1 },
      neutral_count: remaining.count { |v| v.vote.last == 2 },
      disagree_count: remaining.count { |v| v.vote.last == 3 },
      conviction_count: remaining.count(&:conviction?)
    )
  end

  def build_snapshot
    {
      "body" => hujah.body,
      "author" => hujah.user.username,
      "author_name" => hujah.user.try(:full_name),
      "created_at" => hujah.created_at.iso8601,
      "agree_count" => hujah.agree_count,
      "neutral_count" => hujah.neutral_count,
      "disagree_count" => hujah.disagree_count,
      "conviction_count" => hujah.conviction_count,
      # Slice 3 shipped: use the hoojah's real (custom-or-default) stance labels.
      "stance_labels" => {
        "agree" => hujah.stance_label(1),
        "neutral" => hujah.stance_label(2),
        "disagree" => hujah.stance_label(3)
      },
      "arguments" => hujah.children.map { |c| snapshot_argument(c) }
    }
  end

  def snapshot_argument(arg)
    {
      "author" => arg.user.username,
      "body" => arg.body,
      "stance" => Hujah::STANCES[arg.vote],
      "agree_count" => arg.agree_count.to_i,
      "neutral_count" => arg.neutral_count.to_i,
      "disagree_count" => arg.disagree_count.to_i,
      "children" => arg.children.map { |g| snapshot_argument(g) }
    }
  end

  def affected_arguments
    @affected_arguments ||= begin
      ids = affected_participant_ids.to_set
      subtree_hujahs.select { |h| ids.include?(h.user_id) }
    end
  end

  # Entangled = carries OTHER users' content that a purge would wrongly destroy: a reply
  # or vote from someone other than the arg's own author, or ANY debate (a debate always
  # couples two users and its transcript is shared content). `.exists?` issues an EXISTS,
  # not a load. Per-arg EXISTS is deliberate: the affected-args set is bounded, so no batching.
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
