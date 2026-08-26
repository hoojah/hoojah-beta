require "rails_helper"

RSpec.describe UserAnalytics do
  let(:user) { create(:user) }
  subject(:a) { described_class.new(user) }

  it "totals votes + arguments received over own hoojahs (denormalized counts, no votes scan)" do
    h = create(:hujah, user: user, agree_count: 3, neutral_count: 1, disagree_count: 1)
    create(:hujah, user: create(:user), parent: h) # an argument received
    expect(a.total_votes_received).to eq(5)
    expect(a.total_arguments_received).to eq(1)
  end

  it "suppresses a per-hoojah split below k=3" do
    low = create(:hujah, user: user, agree_count: 1, neutral_count: 0, disagree_count: 0)
    hi = create(:hujah, user: user, agree_count: 3, neutral_count: 1, disagree_count: 1)
    d = a.distributions.index_by(&:id)
    expect(d[low.id].suppressed?).to be(true)
    expect(d[hi.id].suppressed?).to be(false)
  end

  # Moderation (2026): removed content is hidden from its author, so the author's own
  # dashboard must not count it either — every aggregate excludes the removed hoojah.
  it "excludes removed content from votes, arguments, and distributions" do
    active = create(:hujah, user: user, agree_count: 3, neutral_count: 1, disagree_count: 1)
    removed = create(:hujah, user: user, agree_count: 10, neutral_count: 10, disagree_count: 10)
    create(:hujah, user: create(:user), parent: active)  # argument on the active claim
    create(:hujah, user: create(:user), parent: removed) # argument on the removed claim
    removed.update!(moderation_status: :removed)

    expect(a.total_votes_received).to eq(5)             # 3+1+1 from active only (30 excluded)
    expect(a.total_arguments_received).to eq(1)         # only the active claim's argument
    expect(a.distributions.map(&:id)).to eq([active.id])
  end

  it "reads only the hujahs table (never joins votes or users)" do
    create(:hujah, user: user, agree_count: 3, neutral_count: 1, disagree_count: 1)
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
      queries << ActiveSupport::Notifications::Event.new(*args).payload[:sql]
    end
    a.total_votes_received
    a.total_arguments_received
    a.distributions.each(&:suppressed?)
    ActiveSupport::Notifications.unsubscribe(subscriber)

    selects = queries.select { |q| q =~ /\ASELECT/i }
    expect(selects).not_to be_empty
    selects.each do |q|
      expect(q).not_to match(/\bvotes\b/i)
      expect(q).not_to match(/\busers\b/i)
      expect(q).not_to match(/\bJOIN\b/i)
    end
  end
end
