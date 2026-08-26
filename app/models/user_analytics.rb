# Owner-only analytics for a single user, computed on read with zero new tables.
#
# Every aggregate reads the DENORMALIZED agree/neutral/disagree counters on
# `hujahs` — the query object never touches `votes` or `users`, so it can never
# re-open the vote-privacy leak Part A closed. k=3 suppression lives here (a
# per-hoojah split below K renders "fewer than 3 votes" instead of the numbers).
class UserAnalytics
  K = 3

  # One read-only value object per top-level hoojah. No AR, no callbacks.
  Distribution = Struct.new(:id, :slug, :body, :agree, :neutral, :disagree) do
    def total = agree + neutral + disagree

    def suppressed? = total < K

    def agree_pct = pct(agree)

    def neutral_pct = pct(neutral)

    def disagree_pct = pct(disagree)

    private

    def pct(count)
      return 0 if total.zero?
      (count * 100.0 / total).round
    end
  end

  def initialize(user)
    @user = user
  end

  # SUM(agree + neutral + disagree) over the user's own hoojahs — one grouped
  # scalar query off the denormalized counters, no per-hoojah query, no votes scan.
  def total_votes_received
    own_hoojahs.sum("agree_count + neutral_count + disagree_count")
  end

  # Count of child hoojahs (arguments) whose parent is one of the user's hoojahs.
  # Sub-select keeps it a single query over `hujahs` only.
  def total_arguments_received
    # Moderation: E10 — count only non-removed arguments under the user's non-removed
    # claims (own_hoojahs is already swept below).
    Hujah.not_removed.where(parent_id: own_hoojahs.select(:id)).count
  end

  # The user's top-level hoojahs as read-only Distribution value objects, built
  # from ONE query over `hujahs` (no per-hoojah query, no votes/users join).
  def distributions
    @distributions ||= own_hoojahs.where(parent_id: nil)
      .order(created_at: :desc)
      .pluck(:id, :slug, :body, :agree_count, :neutral_count, :disagree_count)
      .map do |id, slug, body, agree, neutral, disagree|
        Distribution.new(id:, slug:, body:, agree:, neutral:, disagree:)
      end
  end

  private

  attr_reader :user

  def own_hoojahs
    # Moderation: E10 — removed content is hidden from its author, so the author's
    # own dashboard aggregates must exclude it too.
    Hujah.not_removed.where(user_id: user.id)
  end
end
