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
    it "renders at text-lg and links to the hujah" do
      c = card
      expect(c).to have_css("a[href='#{hujah_path(hujah.slug)}'] .text-lg", text: hujah.body)
    end
  end

  describe "the vote widget" do
    it "renders the existing _vote_bars partial" do
      c = card
      expect(c).to have_css("##{ActionView::RecordIdentifier.dom_id(hujah, :vote_bars)}")
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

    context "when the hujah has no active debate" do
      it "renders neither a swords indicator nor a Jump-in pill" do
        allow(hujah).to receive(:active_debate).and_return(nil)
        c = card

        expect(html).not_to include(glyph("swords", class: "w-4 h-4"))
        expect(c).to have_no_content("Jump in")
      end
    end

    context "when the hujah has an active debate" do
      it "shows a swords debate indicator and a Jump in pill linking to the hujah" do
        debate = build_stubbed(:debate, hujah: hujah)
        allow(hujah).to receive(:active_debate).and_return(debate)
        c = card

        expect(html).to include(glyph("swords", class: "w-4 h-4"))
        expect(c).to have_link("Jump in", href: hujah_path(hujah.slug))
      end
    end
  end
end
