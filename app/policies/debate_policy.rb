# frozen_string_literal: true

class DebatePolicy < ApplicationPolicy
  def show? = record.concluded? || record.participant?(user)

  def create? = user.present?

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
