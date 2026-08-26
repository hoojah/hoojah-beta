require "rails_helper"

# Slice B (hovercard): the minimal trending sidebar row (used by the feed's lazy frame)
# was a single outer <a> to the hoojah. It is now a stretched-link container — an inset
# overlay anchor carries the row click to the hoojah (its aria-label is the body so
# `click_link "<body>"` still resolves it), and the compact @handle is its own profile
# link (hovercard trigger) above the overlay. The two anchors never nest.
RSpec.describe "trending/_trending", type: :view do
  def doc(hujahs)
    Nokogiri::HTML(render(partial: "trending/trending", locals: {hujahs: hujahs}))
  end

  it "exposes the hoojah overlay link and a separate, non-nested profile byline link" do
    author = create(:user, username: "trendauthor")
    hujah = create(:hujah, user: author, body: "a hot trending take")
    d = doc([hujah])

    expect(d.css(%(a[href="/hoojah/#{hujah.slug}"])).size).to be >= 1
    profile = d.at_css('a[href="/u/trendauthor"]')
    expect(profile).to be_present
    expect(profile["data-controller"]).to eq("hovercard")
    expect(d.css("a a")).to be_empty
  end

  it "gives the overlay hoojah link an aria-label carrying the body so click-by-text still works" do
    hujah = create(:hujah, body: "a hot trending take about durian")
    overlay = doc([hujah]).at_css(%(a[href="/hoojah/#{hujah.slug}"]))
    expect(overlay["aria-label"]).to include("a hot trending take about durian")
  end

  it "still renders the empty state when nothing is trending" do
    expect(render(partial: "trending/trending", locals: {hujahs: []})).to include("Nothing trending yet.")
  end
end
