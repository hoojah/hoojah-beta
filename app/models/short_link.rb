class ShortLink < ApplicationRecord
  # The open-redirect defense lives HERE, not in the controller. `target_path` is a
  # stored STRING (deliberately NOT a polymorphic association): this strict format
  # check is the *whole* guard. It matches only the two share surfaces' slug paths,
  # so nothing absolute (`https://evil.com`), protocol-relative (`//evil.com`),
  # path-traversing (`/hoojah/../etc`), or outside `/hoojah`|`/debates` can ever be
  # persisted — and therefore can never be handed to `redirect_to`.
  # NOTE: the slug char class assumes friendly_id stays within [a-zA-Z0-9_-] (today's
  # parameterize output). A future slug generator emitting a `.` or non-ASCII char would
  # fail this format check, so `ShortLink.for` would raise (RecordInvalid) at share-menu
  # render time rather than persist an out-of-shape path.
  INTERNAL_PATH_RE = %r{\A/(hoojah|debates)/[a-zA-Z0-9_-]+\z}

  validates :target_path, presence: true, uniqueness: true, format: {with: INTERNAL_PATH_RE}
  validates :code, presence: true, uniqueness: true

  before_validation { self.code ||= SecureRandom.alphanumeric(7) }

  # Idempotent per record: at most one row ever exists for a given hoojah/debate.
  # Called at share-menu render time. The rescue covers the concurrent first-render
  # race — two requests building the same target_path at once — by retrying the
  # lookup after a losing insert.
  def self.for(record)
    path =
      case record
      when Hujah then "/hoojah/#{record.slug}"
      when Debate then "/debates/#{record.slug}"
      else raise ArgumentError, "ShortLink.for does not support #{record.class}"
      end

    find_or_create_by!(target_path: path)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    find_by!(target_path: path)
  end
end
