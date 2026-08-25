require "rails_helper"

# Hoojah 2026 redesign (Phase 2.5) — the rich, ranked cards on the standalone
# /trending page (mockup ~lines 816-878). This partial is used ONLY there; the
# feed's lazy sidebar frame keeps rendering the untouched, minimal
# `trending/_trending` partial (see spec/requests/trending_spec.rb for that split).
#
# No period toggle, no %-delta, no category-vote data here — those are deferred,
# not part of Hujah.trending's data. Vote count is the plain denormalized counter
# sum, same convention as hujahs/show.html.erb's `total_votes`.
RSpec.describe "trending/_trending_rich", type: :view do
  def html(hujahs:)
    render(partial: "trending/trending_rich", locals: {hujahs: hujahs}).strip
  end

  def rendered_page(hujahs:)
    Capybara.string(html(hujahs: hujahs))
  end

  describe "with hujahs" do
    let(:top) do
      create(:hujah, body: "Malaysia should adopt a 4-day work week nationwide.",
        agree_count: 8000, neutral_count: 100, disagree_count: 104)
    end
    let(:second) do
      create(:hujah, body: "Public transport should be completely free by 2030.",
        agree_count: 200, neutral_count: 30, disagree_count: 27)
    end
    let(:third) do
      create(:hujah, body: "University should be free for all Malaysians.",
        agree_count: 90, neutral_count: 5, disagree_count: 5)
    end

    it "renders the header" do
      expect(rendered_page(hujahs: [top])).to have_content("Trending")
    end

    it "renders rank 1 as a rounded-3xl gradient hero carrying the numeral, claim and vote total" do
      page = rendered_page(hujahs: [top, second, third])
      expect(page).to have_css("div.rounded-3xl[data-testid='trending-hero']", text: "1")
      expect(page).to have_css("div.rounded-3xl", text: "Malaysia should adopt a 4-day work week nationwide.")
      expect(page).to have_css("div.rounded-3xl", text: "8204 votes")
    end

    it "renders the remaining ranks as rounded-2xl cards with a faint numeral, claim and vote count" do
      page = rendered_page(hujahs: [top, second, third])
      expect(page).to have_css("div.rounded-2xl[data-testid='trending-rank-card']", text: "2")
      expect(page).to have_css("div.rounded-2xl[data-testid='trending-rank-card']", text: "3")
      expect(page).to have_css("div.rounded-2xl", text: "Public transport should be completely free by 2030.")
      expect(page).to have_css("div.rounded-2xl", text: "257 votes")
      expect(page).to have_css("div.rounded-2xl", text: "100 votes")
    end

    it "preserves the given order (the caller's — Hujah.trending's — ranking) rather than re-sorting" do
      page = html(hujahs: [top, second, third])
      expect(page.index(top.body)).to be < page.index(second.body)
      expect(page.index(second.body)).to be < page.index(third.body)
    end

    it "invents no period toggle, %-delta, or category-vote chrome" do
      page = rendered_page(hujahs: [top, second, third])
      expect(page).to have_no_css("[data-testid='trending-delta']")
      expect(page).to have_no_css("[data-testid='period-toggle']")
      expect(page).to have_no_content("Today")
      expect(page).to have_no_content("Week")
    end
  end

  describe "with no hujahs" do
    it "renders the same empty-state copy as the minimal list" do
      expect(rendered_page(hujahs: [])).to have_content("Nothing trending yet.")
    end
  end
end
