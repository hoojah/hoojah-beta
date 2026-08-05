class Debate < ApplicationRecord
  extend FriendlyId

  friendly_id :slug_source, use: :slugged

  belongs_to :hujah
  belongs_to :challenger, class_name: "User"
  belongs_to :opponent, class_name: "User"
  has_many :turns, class_name: "DebateTurn", dependent: :destroy

  enum :status, {pending: 0, active: 1, concluded: 2, declined: 3}, default: :pending

  validates :challenger_stance, :opponent_stance, presence: true
  validate { errors.add(:opponent_stance, "must oppose") if challenger_stance == opponent_stance }
  validate { errors.add(:opponent_id, "must differ") if challenger_id == opponent_id }

  after_create_commit :notify_challenge

  def slug_source = ActionController::Base.helpers.strip_tags(hujah.body.to_s).split.first(8).join(" ")

  # Derived — no column. nil unless active; challenger moves first (no turns yet),
  # else whichever participant did NOT author the last turn.
  def current_turn_user
    return nil unless active?
    last = turns.order(:position).last
    if last.nil?
      challenger
    else
      ((last.user_id == challenger_id) ? opponent : challenger)
    end
  end

  def current_round = (turns.count / 2) + 1

  def participant?(user) = user && [challenger_id, opponent_id].include?(user.id)

  def other(user) = (user.id == challenger_id) ? opponent : challenger

  def accept!(by:)
    return false unless pending? && by == opponent
    update!(status: :active)
    notify(challenger, :debate_your_turn)
    true
  end

  def decline!(by:)
    return false unless pending? && by == opponent
    update!(status: :declined)
    notify(challenger, :debate_declined)
    true
  end

  def post_turn(by:, body:)
    with_lock do
      return false unless active? && by == current_turn_user
      turns.create!(user: by, body: body, position: (turns.maximum(:position) || 0) + 1)
    end
    notify(other(by), :debate_your_turn)
    true
  end

  def conclude!(by:)
    return false unless active? && participant?(by)
    update!(status: :concluded)
    notify(other(by), :debate_concluded)
    true
  end

  private

  def notify_challenge = notify(opponent, :debate_challenge)

  def notify(user, category)
    Notification.create!(user:, category:, hujah_id:,
      subject_user_id: ((user == challenger) ? opponent_id : challenger_id), debate_id: id)
  end
end
