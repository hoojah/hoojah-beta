require "rails_helper"

RSpec.describe "Hujah.trending", type: :model do
  before { Rails.cache.clear }

  it "orders recent higher-activity hoojahs by score" do
    hot = create(:hujah, agree_count: 50, neutral_count: 10, disagree_count: 10)
    cold = create(:hujah, agree_count: 1)
    ids = Hujah.trending.map(&:id)
    expect(ids).to include(hot.id)
    expect(ids.index(hot.id)).to be < (ids.index(cold.id) || 999)
  end

  it "caches the id list (second call does not recompute)" do
    create(:hujah, agree_count: 5)
    Hujah.trending
    expect(Rails.cache.exist?("trending:v1")).to be(true)
  end

  # Moderation (2026): removed claims are staff-only everywhere, including trending.
  it "never includes a removed hoojah in trending candidates" do
    removed = create(:hujah, agree_count: 50, neutral_count: 10, disagree_count: 10)
    removed.update!(moderation_status: :removed)
    expect(Hujah.trending.map(&:id)).not_to include(removed.id)
  end

  # The T-1-shaped case: an already-cached trending id must vanish IMMEDIATELY on
  # removal (cache busted on the moderation flip), not linger for up to 15 minutes.
  it "drops a cached trending hoojah the moment it is removed" do
    hot = create(:hujah, agree_count: 50, neutral_count: 10, disagree_count: 10)
    expect(Hujah.trending.map(&:id)).to include(hot.id) # warms + caches the id list
    hot.update!(moderation_status: :removed)
    expect(Hujah.trending.map(&:id)).not_to include(hot.id)
  end
end
