# frozen_string_literal: true

class DebatePolicy < ApplicationPolicy
  # Slice 7b (Gate 8, D-1): a participant always sees their own debate; anyone else may
  # read a CONCLUDED transcript only when BOTH participants are visible to them (a
  # concluded debate with a private participant leaks that participant's arguments).
  # 2026: a concluded debate renders @debate.hujah.body in the transcript, so a
  # non-participant may read it only when BOTH participants AND the underlying claim
  # are visible to them (a followers_only claim must not leak via a public transcript).
  #
  # Hoojah 2026 (redesign Phase 3, Task 3.5): the same visibility clause now ALSO
  # admits an ACTIVE debate, not only a concluded one — the mockup's spectator view
  # (`debates/show`'s non-participant branch) reads a live transcript, so a visible
  # spectator's page can subscribe to the debate's Cable stream (`DebateChannel`
  # re-checks this same predicate at subscribe time) while turns are still being
  # posted, not only after the debate concludes. This introduces no new leak surface
  # beyond what the concluded branch already accepted: the exact same three
  # `visible_to?` checks gate it, so anyone who could read tomorrow's concluded
  # transcript could already read today's argument content via the Debates lens once
  # it concludes — this only moves WHEN they can start reading it, not WHETHER. A
  # `pending` debate is deliberately excluded — an unaccepted challenge is not yet a
  # public back-and-forth, and `_debate_pending` (Phase 3.3) has no spectator layout.
  def show? = record.participant?(user) ||
    ((record.active? || record.concluded?) && record.challenger.visible_to?(user) &&
     record.opponent.visible_to?(user) && record.hujah.visible_to?(user))

  # Reject a challenge against a hidden (blocked/blocked-by) opponent — Slice 7 — and
  # honor the claim's 2026 allow_debates toggle (no challenge when it's off).
  def create? = user.present? &&
    !user.hidden_user_ids.include?(record.opponent_id) &&
    record.hujah.allow_debates?

  def accept? = user.present? && user == record.opponent && record.pending?

  def decline? = accept?

  def conclude? = record.participant?(user) && record.active?

  # Slice 9. DELIBERATELY as coarse as conclude?: "is this actor a party to a
  # live debate", nothing finer. The closing-round window and the MAX_ROUNDS
  # ceiling are APPLICABILITY, not authorization — Debate#extendable_by? owns
  # them and the controller turns its `false` into 422. Pull either condition up
  # here and a legitimate participant asking at the wrong moment is told "not
  # allowed", which is untrue and indistinguishable from a non-participant's
  # denial. No visibility clause is needed (unlike show?): both branches of
  # `participant?` can always read their own debate, so there is nothing to leak.
  def extend? = record.participant?(user) && record.active?

  class Scope < ApplicationPolicy::Scope
    # The Debates lens on the hoojah page. A participant sees all their own debates;
    # everyone else sees a concluded debate only when both participants are visible
    # (Slice 7b, Gate 8). Visibility depends on the accepted-follower graph, so the
    # concluded set is filtered in Ruby — the lens is one hoojah's (small) debate set.
    def resolve
      concluded_visible = scope.where(status: :concluded).includes(:challenger, :opponent, :hujah).select do |d|
        d.challenger.visible_to?(user) && d.opponent.visible_to?(user) && d.hujah.visible_to?(user)
      end
      return concluded_visible unless user
      mine = scope.where(challenger_id: user.id).or(scope.where(opponent_id: user.id)).to_a
      (concluded_visible + mine).uniq
    end
  end
end
