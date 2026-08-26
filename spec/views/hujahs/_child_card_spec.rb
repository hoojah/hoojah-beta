require "rails_helper"

# Secret ballot (2a/A7): the threaded response card shows a per-stance tally footer
# (agree/neutral/disagree counts) for the response hoojah. Below k=3 total votes that
# split is suppressed to a total-only label.
RSpec.describe "hujahs/_child_card", type: :view do
  let(:root) { create(:hujah, visibility: :visible_public) }

  def html(child)
    render(partial: "hujahs/child_card", locals: {child: child, hujah: root}).strip
  end

  def card(child)
    Capybara.string(html(child))
  end

  before { allow(view).to receive_messages(user_signed_in?: false, current_user: nil) }

  # Slice B: the card is a stretched-link container <div>, not a single <a>. The
  # response-filter data attributes moved verbatim onto that container (the controller
  # selects by data-target, not by tag); the hoojah link is an inset overlay anchor and
  # the responder byline is its own non-nested profile link with a hovercard trigger.
  it "is a stretched-link container carrying the response-filter attrs, with non-nested anchors" do
    responder = create(:user, username: "responder")
    child = create(:hujah, parent: root, user: responder, vote: 1, body: "a threaded reply")
    doc = Nokogiri::HTML(html(child))

    item = doc.at_css('[data-response-filter-target="item"]')
    expect(item.name).to eq("div")
    expect(item["data-response-filter-vote"]).to eq("agree")

    expect(doc.css(%(a[href="/hoojah/#{child.slug}"])).size).to be >= 1
    expect(doc.css('a[href="/u/responder"][data-controller="hovercard"]').size).to be >= 1
    expect(doc.css("a a")).to be_empty
  end

  context "at or above k" do
    it "renders the per-stance footer (three stance glyphs) with the counts" do
      child = create(:hujah, parent: root, user: create(:user),
        agree_count: 4, neutral_count: 1, disagree_count: 2) # total 7
      c = card(child)
      # For an anonymous viewer the only svgs on the card are the three stance glyphs.
      expect(c).to have_css("svg", count: 3)
      expect(c).to have_content("4")
      expect(c).to have_content("2")
    end
  end

  context "below k" do
    let(:child) do
      create(:hujah, parent: root, user: create(:user),
        agree_count: 1, neutral_count: 0, disagree_count: 1) # total 2
    end

    it "does not render the per-stance count row (no stance glyphs)" do
      expect(card(child)).to have_no_css("svg")
    end

    it "shows the total-only label" do
      expect(card(child)).to have_content("2 votes")
    end

    it "shows 'No votes yet' at zero" do
      quiet = create(:hujah, parent: root, user: create(:user),
        agree_count: 0, neutral_count: 0, disagree_count: 0)
      expect(card(quiet)).to have_content("No votes yet")
    end
  end
end
