require "rails_helper"

# Secret ballot (2a/A7): the tall single-hoojah vote hero renders per-stance
# pct/count rows + a segmented bar. Below k=3 total votes both are a
# de-anonymization vector and are suppressed down to a total-only label; the vote
# buttons, the viewer's own-stance highlight, and the (non-breakdown)
# conviction_count aggregate all stay.
RSpec.describe "hujahs/_vote_hero", type: :view do
  def html(**locals)
    render(partial: "hujahs/vote_hero",
      locals: {hujah: hujah, current_user_vote: nil, current_vote_locked: false}.merge(locals)).strip
  end

  def widget(**locals)
    Capybara.string(html(**locals))
  end

  context "at or above k (full split)" do
    let(:hujah) { create(:hujah, agree_count: 60, neutral_count: 20, disagree_count: 20) } # total 100

    it "renders the per-stance percentages and the segmented bar" do
      w = widget
      expect(w).to have_text("60%")
      expect(w).to have_css(".rounded-full.overflow-hidden > div.bg-agree[style*='width: 60%']")
    end

    it "renders the three vote buttons" do
      expect(widget).to have_css("form[action='#{hujah_votes_path(hujah.slug)}'][method='post']", count: 3)
    end
  end

  context "below k (suppressed)" do
    let(:hujah) { create(:hujah, agree_count: 1, neutral_count: 1, disagree_count: 0) } # total 2

    it "renders no per-stance percentages" do
      expect(widget).to have_no_text("%")
    end

    it "renders no segmented distribution bar" do
      expect(widget).to have_no_css(".rounded-full.overflow-hidden > div.bg-agree")
    end

    it "shows the compact total-vote label" do
      expect(widget).to have_text("2 votes")
    end

    it "shows 'No votes yet' at zero votes" do
      empty = create(:hujah, agree_count: 0, neutral_count: 0, disagree_count: 0)
      expect(widget(hujah: empty)).to have_text("No votes yet")
    end

    it "still renders the three vote buttons" do
      expect(widget).to have_css("form[action='#{hujah_votes_path(hujah.slug)}'][method='post']", count: 3)
    end

    it "preserves the viewer's own-stance highlight" do
      expect(widget(current_user_vote: "agree")).to have_css("button[aria-label='Agree'] .text-white")
    end

    it "still shows the conviction_count aggregate (not a per-stance breakdown)" do
      hujah.update!(conviction_count: 3)
      expect(widget).to have_text("3 conviction")
    end
  end
end
