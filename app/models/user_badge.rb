class UserBadge < ApplicationRecord
  belongs_to :user

  validates :badge_key, inclusion: {in: Badge::REGISTRY.keys}

  # Award `key` to `user` — idempotent and safe to call from any post-commit
  # callback. The `exists?` guard avoids a guaranteed-fail insert on the common
  # already-earned path; the unique index + `RecordNotUnique` rescue closes the
  # race where two requests award concurrently (one wins, the other no-ops — no
  # duplicate row, no duplicate notification). NEVER call this inside a hot-path
  # transaction (e.g. Hujah#cast_vote): a rescued RecordNotUnique still poisons
  # an open Postgres transaction, which would lose the enclosing write.
  def self.award(user, key)
    return if user.user_badges.exists?(badge_key: key)
    user.user_badges.create!(badge_key: key)
    Notification.create!(user:, category: :badge_earned, body: key)
  rescue ActiveRecord::RecordNotUnique
    nil
  end
end
