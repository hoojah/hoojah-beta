require "rails_helper"

# Slice B (hovercard): the search hoojah result row was a single outer <a> to the
# hoojah. It is now a stretched-link container — an inset overlay anchor carries the
# whole-row click to the hoojah, and the "Hoojah by @handle" byline is its own profile
# link (hovercard trigger) lifted above the overlay. The two anchors are siblings, never
# nested (an <a> inside an <a> is invalid HTML).
RSpec.describe "search/_result_hujah", type: :view do
  before { assign(:query, "claim") }

  def doc(hujah)
    Nokogiri::HTML(render(partial: "search/result_hujah", locals: {hujah: hujah}))
  end

  it "exposes the hoojah overlay link and a separate, non-nested profile byline link" do
    author = create(:user, username: "resultauthor")
    hujah = create(:hujah, user: author, body: "a search-matchable claim body")
    d = doc(hujah)

    expect(d.css(%(a[href="/hoojah/#{hujah.slug}"])).size).to be >= 1
    profile = d.at_css('a[href="/u/resultauthor"]')
    expect(profile).to be_present
    expect(profile["data-controller"]).to eq("hovercard")
    expect(d.css("a a")).to be_empty
  end

  it "keeps the literal @handle substring intact for the visibility-leak checks" do
    author = create(:user, username: "resultauthor")
    hujah = create(:hujah, user: author, body: "another claim body")
    expect(render(partial: "search/result_hujah", locals: {hujah: hujah})).to include("@resultauthor")
  end
end
