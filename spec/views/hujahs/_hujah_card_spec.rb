require "rails_helper"

# Hoojah 2026 redesign (Phase 1, Task 1.3): the feed card's surface, header and
# footer restyle. `_vote_bars` (Task 1.2) is untouched by this spec — it is
# rendered as-is and only its presence is checked here.
RSpec.describe "hujahs/_hujah_card", type: :view do
  let(:author) { create(:user, full_name: "Maya Zaharudin", username: "maya") }
  let(:hujah) do
    create(:hujah, user: author, body: "Free public transport by 2030.",
      agree_count: 51, neutral_count: 13, disagree_count: 36)
  end

  before do
    3.times { create(:hujah, parent_id: hujah.id, user: create(:user)) }
    allow(view).to receive_messages(user_signed_in?: false, current_user: nil)
  end

  def html(**locals)
    render(partial: "hujahs/hujah_card", locals: {hujah: hujah}.merge(locals)).strip
  end

  def card(**locals)
    Capybara.string(html(**locals))
  end

  # `lucide-rails` emits a bare <svg> with no name in any attribute (see
  # spec/views/ui/empty_state_spec.rb's own note), so the only way to prove *which*
  # glyph rendered is to compare markup against the helper's own output.
  def glyph(name, **opts)
    ApplicationController.helpers.lucide_icon(name, **opts)
  end

  describe "the card surface" do
    it "renders a rounded-2xl bg-card shadow article carrying the frozen testid" do
      c = card
      expect(c).to have_css("article.rounded-2xl.bg-card.shadow[data-testid='hujah-card']")
    end
  end

  describe "the header" do
    it "renders a tile avatar" do
      c = card
      expect(c).to have_css("span[role='img'].avatar-tile", text: "MZ")
    end

    it "shows the author's full name" do
      c = card
      expect(c).to have_content("Maya Zaharudin")
    end

    it "shows @handle · compact date underneath" do
      c = card
      expect(c).to have_content("@maya")
      expect(c).to have_content(hujah.created_at.strftime("%b %-d"))
    end

    it "renders a more-vertical menu trigger" do
      expect(html).to include(glyph("more-vertical", class: "w-5 h-5"))
    end

    it "does not render a verified badge — there is no verified concept" do
      expect(html.downcase).not_to include("verified")
    end
  end

  describe "the claim body" do
    # 2026 polish: the body is deliberately NOT a link (tapping the claim selects,
    # it does not navigate; wrapping it also nested the tag/mention anchors
    # format_body injects, which is invalid HTML). The thread is reached via the
    # Jump-in pill / response count instead.
    it "renders at text-lg and is NOT wrapped in a link to the hujah" do
      c = card
      expect(c).to have_css(".hujah-body.text-lg", text: hujah.body)
      expect(c).to have_no_css("a[href='#{hujah_path(hujah.slug)}'] .hujah-body")
    end
  end

  describe "the vote widget" do
    it "renders the existing _vote_bars partial" do
      c = card
      expect(c).to have_css("##{ActionView::RecordIdentifier.dom_id(hujah, :vote_bars)}")
    end
  end

  # Secret ballot (2a/A7): a below-k card suppresses the per-stance split inside the
  # embedded vote widget while the footer total (never a per-stance breakdown) stays.
  describe "the embedded vote widget below k" do
    let(:author) { create(:user, full_name: "Quiet Poster", username: "quiet") }
    let(:hujah) do
      create(:hujah, user: author, body: "A brand new low-vote claim.",
        agree_count: 1, neutral_count: 1, disagree_count: 0) # total 2
    end

    before { allow(view).to receive_messages(user_signed_in?: false, current_user: nil) }

    it "suppresses the percentage legend for every stance but keeps the three vote buttons" do
      widget = "##{ActionView::RecordIdentifier.dom_id(hujah, :vote_bars)}"
      c = card
      # The per-stance numbers only ever render inside the percent legend (`N% stance`);
      # below k none of the three may appear — this is the raw per-stance leak vector.
      expect(c).to have_no_css("#{widget} .text-agree", text: "%")
      expect(c).to have_no_css("#{widget} .text-neutral", text: "%")
      expect(c).to have_no_css("#{widget} .text-disagree", text: "%")
      expect(c).to have_css("#{widget} form", count: 3)
    end

    it "shows only the total-vote label inside the widget, no per-stance breakdown" do
      widget = card.find("##{ActionView::RecordIdentifier.dom_id(hujah, :vote_bars)}")
      expect(widget).to have_text("2 votes")
      # the segmented percentage bar (the only place a per-stance figure surfaces) is gone
      expect(widget).to have_no_css("[style*='width']")
    end

    # Scope the total to the footer aggregate node (the first count span behind the
    # bar-chart-3 glyph) rather than a bare "2" anywhere on the card — the loose match
    # would pass on any stray "2" and can't distinguish the total from a leaked count.
    it "shows the aggregate footer total behind the bar-chart-3 glyph, not a per-stance count" do
      footer_link = card.find("a.text-ink-2.no-underline")
      expect(footer_link.find("span.ml-1", match: :first)).to have_text("2", exact: true)
    end
  end

  describe "the counts footer" do
    it "shows total votes behind a bar-chart-3 glyph" do
      c = card
      expect(html).to include(glyph("bar-chart-3", class: "w-4 h-4"))
      expect(c).to have_content("100")
    end

    it "shows the response count behind a message-circle glyph" do
      c = card
      expect(html).to include(glyph("message-circle", class: "w-4 h-4"))
      expect(c).to have_content("3")
    end

    # 2026 polish: the Jump-in pill is now PERSISTENT on every card (the primary
    # way into the thread now the body is un-linked). Its target is smart —
    # the thread when there is no active debate, the debate room when there is.
    # The swords indicator stays additive (active debate only).
    context "when the hujah has no active debate" do
      it "renders no swords indicator, and a Jump-in pill linking to the thread" do
        allow(hujah).to receive(:active_debate).and_return(nil)
        c = card

        expect(html).not_to include(glyph("swords", class: "w-4 h-4"))
        expect(c).to have_link("Jump in", href: hujah_path(hujah.slug))
      end
    end

    context "when the hujah has an active debate" do
      it "shows a swords debate indicator and a Jump in pill linking to the debate" do
        debate = create(:debate, hujah: hujah, status: :active)
        allow(hujah).to receive(:active_debate).and_return(debate)
        c = card

        expect(html).to include(glyph("swords", class: "w-4 h-4"))
        expect(c).to have_link("Jump in", href: debate_path(debate.slug))
      end
    end

    context "when the hujah has conviction votes" do
      it "shows a heart glyph and the conviction count" do
        allow(hujah).to receive(:conviction_count).and_return(2)
        c = card

        expect(html).to include(glyph("heart", class: "w-4 h-4"))
        expect(c).to have_css("span[aria-label='Conviction votes']", text: "2")
      end
    end
  end
end
