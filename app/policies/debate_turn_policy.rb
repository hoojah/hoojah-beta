# frozen_string_literal: true

class DebateTurnPolicy < ApplicationPolicy
  def create? = user.present? && record.debate.active? && record.debate.current_turn_user == user
end
