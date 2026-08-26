require "rails_helper"

# Hoojah 2026 redesign (Phase 1, Task 1.2): the feed vote widget moves from a
# per-stance 3-row layout (circular button + track + percent) to ONE segmented
# aggregate bar with a percent legend, plus three pill vote buttons. The vote
# POST itself (path/params/target) is NOT changing — only the markup around it —
# so this spec pins both halves: the new visual shape, and the untouched form.
RSpec.describe "hujahs/_vote_bars", type: :view do
  let(:hujah) { create(:hujah, agree_count: 51, neutral_count: 13, disagree_count: 36) }

  def html(**locals)
    render(partial: "hujahs/vote_bars", locals: {hujah: hujah, current_user_vote: nil}.merge(locals)).strip
  end

  def widget(**locals)
    Capybara.string(html(**locals))
  end

  describe "the wrapper" do
    it "keeps the dom_id the votes turbo_stream replaces in place" do
      expect(widget).to have_css("##{ActionView::RecordIdentifier.dom_id(hujah, :vote_bars)}")
    end
  end

  describe "the segmented aggregate bar" do
    # ONE track (`.flex.rounded-full.overflow-hidden`), not three per-stance rows —
    # this is the structural change from today's layout, so it must appear exactly
    # once and be the direct parent of all three stance segments.
    it "renders a single segmented track containing all three stance segments" do
      expect(widget).to have_css(".flex.rounded-full.overflow-hidden", count: 1)
    end

    it "widths each segment by its stance's percentage of the total" do
      w = widget
      expect(w).to have_css(".flex.rounded-full.overflow-hidden > div.bg-agree[style='width: 51%']")
      expect(w).to have_css(".flex.rounded-full.overflow-hidden > div.bg-neutral[style='width: 13%']")
      expect(w).to have_css(".flex.rounded-full.overflow-hidden > div.bg-disagree[style='width: 36%']")
    end

    # Secret ballot (2a/A7): an all-zero hoojah is below k=5, so the bar is now
    # suppressed entirely (see the suppression group below) rather than rendering three
    # 0% segments. This still exercises the "no crash on all-zero" guard — the render
    # must not raise — it just asserts the new suppressed shape.
    it "suppresses the bar for all-zero counters (below k), rendering no crash" do
      empty = create(:hujah, agree_count: 0, neutral_count: 0, disagree_count: 0)

      w = widget(hujah: empty)

      expect(w).to have_no_css(".flex.rounded-full.overflow-hidden")
      expect(w).to have_text("No votes yet")
    end
  end

  describe "the percent legend" do
    # ONE legend row holding all three stance percentages side by side, not a
    # right-aligned label trailing each per-stance row as today.
    it "renders a single legend row with all three stance percentages as siblings" do
      expect(widget).to have_css(".flex.justify-between", count: 1)
    end

    it "labels each stance's percentage in its stance colour" do
      w = widget

      expect(w).to have_css(".flex.justify-between > .text-agree", text: "51%")
      expect(w).to have_css(".flex.justify-between > .text-neutral", text: "13%")
      expect(w).to have_css(".flex.justify-between > .text-disagree", text: "36%")
    end
  end

  # Secret ballot (2a/A7): below k=5 total votes the per-stance split is a
  # de-anonymization vector, so the segmented bar + percent legend are suppressed and
  # only the total vote count is shown. The three vote buttons stay — you can still vote,
  # you just don't see the split.
  describe "secret-ballot suppression below k" do
    let(:sub_k) { create(:hujah, agree_count: 2, neutral_count: 1, disagree_count: 1) } # total 4

    it "hides the segmented bar and the percent legend below k" do
      w = widget(hujah: sub_k)

      expect(w).to have_no_css(".flex.rounded-full.overflow-hidden")
      expect(w).to have_no_css("[style*='width:']")
    end

    it "renders none of the per-stance percentages below k" do
      w = widget(hujah: sub_k)

      expect(w).to have_no_text("%")
      expect(w).to have_no_css(".text-agree", text: "%")
    end

    it "shows the compact total vote count below k" do
      expect(widget(hujah: sub_k)).to have_text("4 votes")
    end

    it "shows 'No votes yet' when there are zero votes" do
      empty = create(:hujah, agree_count: 0, neutral_count: 0, disagree_count: 0)
      expect(widget(hujah: empty)).to have_text("No votes yet")
    end

    it "still renders all three vote buttons below k" do
      w = widget(hujah: sub_k)

      expect(w).to have_css("form[action='#{hujah_votes_path(sub_k.slug)}'][method='post']", count: 3)
      expect(w).to have_css("button", text: "Agree", visible: :all)
      expect(w).to have_css("button", text: "Neutral", visible: :all)
      expect(w).to have_css("button", text: "Disagree", visible: :all)
    end

    it "preserves the viewer's own-stance highlight below k" do
      w = widget(hujah: sub_k, current_user_vote: "agree")
      expect(w).to have_css("button[aria-pressed='true'][class*='bg-agree']")
    end

    it "shows the full split at exactly k (positive control)" do
      at_k = create(:hujah, agree_count: 3, neutral_count: 1, disagree_count: 1) # total 5
      w = widget(hujah: at_k)

      expect(w).to have_css(".flex.rounded-full.overflow-hidden", count: 1)
      expect(w).to have_css(".flex.justify-between > .text-agree", text: "60%")
    end
  end

  describe "the three vote buttons" do
    it "posts to the same vote path as today, one form per stance" do
      w = widget

      expect(w).to have_css("form[action='#{hujah_votes_path(hujah.slug)}'][method='post']", count: 3)
    end

    # `_vote_bars` today sends choice 1/agree, 2/neutral, 3/disagree as `vote:` —
    # VotesController reads `params[:vote]` straight into `Hujah#cast_vote`, so this
    # mapping is the contract, not incidental — only the wrapper markup may change.
    it "sends the unchanged agree/neutral/disagree vote param on each button" do
      w = widget

      expect(w).to have_css("form input[name='vote'][value='1']", visible: :all)
      expect(w).to have_css("form input[name='vote'][value='2']", visible: :all)
      expect(w).to have_css("form input[name='vote'][value='3']", visible: :all)
    end

    it "renders as pill buttons with the stance icon, stance border/text and press feedback" do
      w = widget

      expect(w).to have_css("form button.active\\:scale-95[class*='border-agree'][class*='text-agree'] svg")
      expect(w).to have_css("form button.active\\:scale-95[class*='border-neutral'][class*='text-neutral'] svg")
      expect(w).to have_css("form button.active\\:scale-95[class*='border-disagree'][class*='text-disagree'] svg")
    end

    it "labels each button for accessibility, same as today (now via visible pill text)" do
      w = widget

      expect(w).to have_css("button", text: "Agree", visible: :all)
      expect(w).to have_css("button", text: "Neutral", visible: :all)
      expect(w).to have_css("button", text: "Disagree", visible: :all)
    end
  end
end
