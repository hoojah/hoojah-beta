require "rails_helper"

RSpec.describe IconsHelper, type: :helper do
  it "renders the mapped Lucide svg for a stance" do
    expect(helper.stance_icon("agree")).to include("<svg")
  end

  describe "#stance_color" do
    it "names the design-system colour token for each stance" do
      expect(%w[agree neutral disagree].map { |s| helper.stance_color(s) })
        .to eq(%w[agree neutral disagree])
    end

    it "accepts a symbol, as the vote enum hands one back" do
      expect(helper.stance_color(:disagree)).to eq("disagree")
    end

    it "falls back to brand primary when the viewer has no stance" do
      expect(helper.stance_color(nil)).to eq("primary")
    end

    it "returns a tone `ds_button_classes` actually accepts" do
      %w[agree neutral disagree].push(nil).each do |stance|
        expect(DesignSystemHelper::TONES).to include(helper.stance_color(stance))
      end
    end
  end

  describe "#visibility_icon" do
    it "returns nil for a public hoojah — public is the feed default, an icon here means restricted" do
      expect(helper.visibility_icon(build(:hujah, visibility: :visible_public))).to be_nil
    end

    it "renders the users glyph for a followers-only hoojah" do
      svg = helper.visibility_icon(build(:hujah, visibility: :followers_only))
      expect(svg).to include("<svg")
      # The lucide `users` glyph — the head circle distinguishes it from `lock`.
      expect(svg).to include(%(<circle cx="9" cy="7"))
    end

    it "renders the lock glyph for a private hoojah" do
      svg = helper.visibility_icon(build(:hujah, visibility: :private_only))
      expect(svg).to include("<svg")
      # The lucide `lock` glyph — the shackle rect distinguishes it from `users`.
      expect(svg).to include(%(<rect width="18" height="11"))
    end
  end

  describe "#visibility_title" do
    let(:author) { build(:user, username: "debat") }

    it "is nil for a public hoojah" do
      expect(helper.visibility_title(build(:hujah, user: author, visibility: :visible_public))).to be_nil
    end

    it "names the follower audience for a followers-only hoojah" do
      expect(helper.visibility_title(build(:hujah, user: author, visibility: :followers_only)))
        .to eq("Only people following @debat can see this")
    end

    it "names the author for a private hoojah" do
      expect(helper.visibility_title(build(:hujah, user: author, visibility: :private_only)))
        .to eq("Only @debat can see this")
    end
  end
end
