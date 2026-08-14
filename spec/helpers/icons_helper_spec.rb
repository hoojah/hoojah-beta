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
end
