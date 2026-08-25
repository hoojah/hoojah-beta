require "rails_helper"

# Hoojah 2026 redesign (Phase 1, Task 1.4): the live-debate strip that hangs off the
# bottom of a feed card when its hujah has an active debate (mockup ~248-252).
RSpec.describe "hujahs/_live_debate_strip", type: :view do
  let(:challenger) { create(:user, username: "limteik") }
  let(:opponent) { create(:user, username: "sitir") }
  let(:hujah) { create(:hujah) }

  def html(**locals)
    render(partial: "hujahs/live_debate_strip", locals: {hujah: hujah}.merge(locals)).strip
  end

  def strip(**locals)
    Capybara.string(html(**locals))
  end

  context "when the hujah has an active debate" do
    let(:debate) { create(:debate, hujah: hujah, challenger: challenger, opponent: opponent, status: :active) }

    before do
      create(:debate_turn, debate: debate, user: challenger)
      create(:debate_turn, debate: debate, user: opponent)
      create(:debate_turn, debate: debate, user: challenger)
      allow(hujah).to receive(:active_debate).and_return(debate)
    end

    it "renders a bottom-rounded bg-disagree-soft accent surface" do
      expect(strip).to have_css(".rounded-b-2xl.bg-disagree-soft")
    end

    it "shows the two participants and the current round" do
      expect(debate.current_round).to eq(2)
      expect(strip).to have_content("@limteik vs @sitir · Round 2")
    end

    it "shows a Live pill with a pulsing dot (no watcher count)" do
      s = strip
      expect(s).to have_content("Live")
      expect(s).to have_css("[style*='hbreathe']")
      expect(s).to have_no_content("watching")
    end

    it "links to the debate" do
      expect(strip).to have_link(href: debate_path(debate.slug))
    end

    it "renders a chevron-right glyph" do
      glyph = ApplicationController.helpers.lucide_icon("chevron-right", class: "w-5 h-5 text-faint shrink-0")
      expect(html).to include(glyph)
    end
  end

  context "when the hujah has no active debate" do
    before { allow(hujah).to receive(:active_debate).and_return(nil) }

    it "renders nothing" do
      expect(html).to eq("")
    end
  end
end
