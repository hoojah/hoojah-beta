require "rails_helper"

RSpec.describe "Search empty states", type: :request do
  it "renders the design-system empty state for a zero-result query" do
    get search_path(q: "zzz-nothing-matches-zzz")
    expect(response.body).to include("No results for")
    expect(Nokogiri::HTML.parse(response.body).css("svg")).not_to be_empty
  end

  it "renders an empty state when there are no hashtags to browse" do
    get search_path
    expect(response.body).to include("No hashtags yet")
  end
end
