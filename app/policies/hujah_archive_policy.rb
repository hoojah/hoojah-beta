# frozen_string_literal: true

# A frozen archive is readable only by a user who was PURGED into it — i.e. has a
# participant row for it (Slice 2). Defense in depth over the controller's
# HujahArchiveParticipant.for resolution, so a hand-crafted request can't read someone
# else's archive.
class HujahArchivePolicy < ApplicationPolicy
  def show? = user.present? && record.participants.exists?(user_id: user.id)
end
