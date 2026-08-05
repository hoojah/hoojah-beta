require "rails_helper"

RSpec.describe IconsHelper, type: :helper do
  it "renders the mapped Lucide svg for a stance" do
    expect(helper.stance_icon("agree")).to include("<svg")
  end
end
