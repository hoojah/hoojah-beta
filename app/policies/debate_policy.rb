# frozen_string_literal: true

class DebatePolicy < ApplicationPolicy
  def show? = record.concluded? || record.participant?(user)

  # Reject a challenge against a hidden (blocked/blocked-by) opponent — Slice 7.
  def create? = user.present? && !user.hidden_user_ids.include?(record.opponent_id)

  def accept? = user.present? && user == record.opponent && record.pending?

  def decline? = accept?

  def conclude? = record.participant?(user) && record.active?

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user
        scope.where(status: :concluded).or(scope.where(challenger_id: user.id)).or(scope.where(opponent_id: user.id))
      else
        scope.where(status: :concluded)
      end
    end
  end
end
