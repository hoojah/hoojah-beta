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
end
