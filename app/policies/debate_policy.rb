# frozen_string_literal: true

class DebatePolicy < ApplicationPolicy
  # Slice 7b (Gate 8, D-1): a participant always sees their own debate; anyone else may
  # read a CONCLUDED transcript only when BOTH participants are visible to them (a
  # concluded debate with a private participant leaks that participant's arguments).
  def show? = record.participant?(user) ||
    (record.concluded? && record.challenger.visible_to?(user) && record.opponent.visible_to?(user))

  # Reject a challenge against a hidden (blocked/blocked-by) opponent — Slice 7.
  def create? = user.present? && !user.hidden_user_ids.include?(record.opponent_id)

  def accept? = user.present? && user == record.opponent && record.pending?

  def decline? = accept?

  def conclude? = record.participant?(user) && record.active?

  class Scope < ApplicationPolicy::Scope
    # The Debates lens on the hoojah page. A participant sees all their own debates;
    # everyone else sees a concluded debate only when both participants are visible
    # (Slice 7b, Gate 8). Visibility depends on the accepted-follower graph, so the
    # concluded set is filtered in Ruby — the lens is one hoojah's (small) debate set.
    def resolve
      concluded_visible = scope.where(status: :concluded).select do |d|
        d.challenger.visible_to?(user) && d.opponent.visible_to?(user)
      end
      return concluded_visible unless user
      mine = scope.where(challenger_id: user.id).or(scope.where(opponent_id: user.id)).to_a
      (concluded_visible + mine).uniq
    end
  end
end
