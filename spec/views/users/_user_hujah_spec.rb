require "rails_helper"

# Secret ballot (2a/A7): the compact profile hoojah card shows an inline per-stance
# tally (agree · neutral · disagree). Below k=5 total votes that split is suppressed to
# a total-only label.
RSpec.describe "users/_user_hujah", type: :view do
  let(:author) { create(:user, full_name: "Prof Debat", username: "debat") }

  def html(hujah)
    render(partial: "users/user_hujah", locals: {hujah: hujah}).strip
  end

  def card(hujah)
    Capybara.string(html(hujah))
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
    let(:hujah) { create(:hujah, user: author, agree_count: 2, neutral_count: 1, disagree_count: 0) } # total 3

    it "does not render the per-stance count row (no stance glyphs)" do
      expect(card(hujah)).to have_no_css("svg")
    end

    it "shows the total-only label" do
      expect(card(hujah)).to have_content("3 votes")
    end

    it "shows 'No votes yet' at zero" do
      quiet = create(:hujah, user: author, agree_count: 0, neutral_count: 0, disagree_count: 0)
      expect(card(quiet)).to have_content("No votes yet")
    end
  end
end
