require "rails_helper"

RSpec.describe Hashtag, type: :model do
  describe "validations" do
    it "requires a name" do
      expect(Hashtag.new(display: "X")).not_to be_valid
    end

    it "requires the name to be unique" do
      Hashtag.create!(name: "transit", display: "transit")
      dup = Hashtag.new(name: "transit", display: "Transit")
      expect(dup).not_to be_valid
    end
  end

  describe ".canonical" do
    it "lower-cases the raw tag" do
      expect(Hashtag.canonical("KlangValley")).to eq "klangvalley"
    end
  end

  describe "associations + counter cache" do
    it "maintains hujahs_count through the join" do
      tag = Hashtag.create!(name: "mrt", display: "MRT")
      h1 = create(:hujah)
      h2 = create(:hujah)
      expect(tag.hujahs_count).to eq 0

      HashtagHujah.create!(hashtag: tag, hujah: h1)
      HashtagHujah.create!(hashtag: tag, hujah: h2)
      expect(tag.reload.hujahs_count).to eq 2

      tag.hashtag_hujahs.first.destroy!
      expect(tag.reload.hujahs_count).to eq 1
    end
  end

  # Phase 2.2 search scope. Hashtags carry no privacy of their own (no visible_to
  # reuse needed) — leak coverage for the surrounding search page is end-to-end in
  # spec/requests/search_spec.rb.
  describe ".search" do
    it "matches a case-insensitive substring of the name" do
      tag = Hashtag.create!(name: "klangvalley", display: "KlangValley")
      expect(Hashtag.search("KLANG")).to include(tag)
    end

    it "excludes a non-matching tag" do
      tag = Hashtag.create!(name: "nomatch", display: "NoMatch")
      expect(Hashtag.search("zzz-no-match")).not_to include(tag)
    end

    it "treats % and _ as literal characters, not SQL wildcards (sanitize_sql_like)" do
      literal = Hashtag.create!(name: "has_underscore", display: "has_underscore")
      no_underscore = Hashtag.create!(name: "hasxunderscore", display: "hasxunderscore")
      results = Hashtag.search("has_underscore")
      expect(results).to include(literal)
      expect(results).not_to include(no_underscore)
    end

    it "orders by hujahs_count descending and caps at 8" do
      9.times { |n| Hashtag.create!(name: "captag#{n}", display: "captag#{n}", hujahs_count: n) }
      results = Hashtag.search("captag")
      expect(results.size).to eq(8)
      expect(results.map(&:hujahs_count)).to eq(results.map(&:hujahs_count).sort.reverse)
    end
  end
end
