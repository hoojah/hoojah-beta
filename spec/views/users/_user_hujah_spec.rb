require "rails_helper"

# Secret ballot (2a/A7): the compact profile hoojah card shows an inline per-stance
# tally (agree · neutral · disagree). Below k=3 total votes that split is suppressed to
# a total-only label.
RSpec.describe "users/_user_hujah", type: :view do
  let(:author) { create(:user, full_name: "Prof Debat", username: "debat") }

  def html(hujah)
    render(partial: "users/user_hujah", locals: {hujah: hujah}).strip
  end

  def card(hujah)
    Capybara.string(html(hujah))
  end

  # Slice B: the compact profile hoojah card is a stretched-link container, not a single
  # outer <a>. The hoojah link is an inset overlay anchor; the author avatar + name are
  # their own profile links (hovercard triggers) above it. The two must not nest.
  it "exposes a hoojah overlay link and a separate non-nested profile byline link" do
    hujah = create(:hujah, user: author, body: "a claim on my profile")
    doc = Nokogiri::HTML(html(hujah))

    expect(doc.css(%(a[href="/hoojah/#{hujah.slug}"])).size).to be >= 1
    expect(doc.css('a[href="/u/debat"][data-controller="hovercard"]').size).to be >= 1
    expect(doc.css("a a")).to be_empty
  end

  context "at or above k" do
    it "renders the per-stance footer (three stance glyphs) with counts" do
      hujah = create(:hujah, user: author, agree_count: 3, neutral_count: 1, disagree_count: 1) # total 5
      c = card(hujah)
      expect(c).to have_css("svg", count: 3)
      expect(c).to have_content("3")
    end
  end

  context "below k" do
    let(:hujah) { create(:hujah, user: author, agree_count: 1, neutral_count: 1, disagree_count: 0) } # total 2

    it "does not render the per-stance count row (no stance glyphs)" do
      expect(card(hujah)).to have_no_css("svg")
    end

    it "shows the total-only label" do
      expect(card(hujah)).to have_content("2 votes")
    end

    it "shows 'No votes yet' at zero" do
      quiet = create(:hujah, user: author, agree_count: 0, neutral_count: 0, disagree_count: 0)
      expect(card(quiet)).to have_content("No votes yet")
    end
  end
end
