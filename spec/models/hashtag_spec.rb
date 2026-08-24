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
end
