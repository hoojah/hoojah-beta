require "rails_helper"

# Hoojah 2026 redesign (Phase 3, Task 3.4): `_debate_turn`'s chat-bubble variant.
RSpec.describe "debates/_debate_turn", type: :view do
  let(:challenger) { create(:user, username: "limteik") }
  let(:opponent) { create(:user, username: "sitir") }
  let(:debate) { create(:debate, challenger: challenger, opponent: opponent, status: :active) }

  def html(turn)
    render(partial: "debates/debate_turn", locals: {debate_turn: turn, debate: debate}).strip
  end

  def bubble(turn)
    Capybara.string(html(turn))
  end

  it "keeps the load-bearing dom_id wrapper" do
    turn = create(:debate_turn, debate: debate, user: challenger, position: 1)
    expect(bubble(turn)).to have_css("##{ActionView::RecordIdentifier.dom_id(turn)}")
  end

  it "aligns the challenger's turn to the start, agree-coloured" do
    turn = create(:debate_turn, debate: debate, user: challenger, position: 1)
    b = bubble(turn)
    expect(b).to have_css(".self-start")
    expect(b).to have_css(".text-agree", text: "@limteik")
  end

  it "aligns the opponent's turn to the end, disagree-coloured" do
    create(:debate_turn, debate: debate, user: challenger, position: 1)
    turn = create(:debate_turn, debate: debate, user: opponent, position: 2)
    b = bubble(turn)
    expect(b).to have_css(".self-end")
    expect(b).to have_css(".text-disagree", text: "@sitir")
  end

  # Anchored exact match — spec/system/debate_phases_spec.rb depends on this class
  # containing ONLY the phase word, never "Phase · @handle" as a whole.
  it "scopes .debate-turn-phase to the phase word alone" do
    turn = create(:debate_turn, debate: debate, user: challenger, position: 1)
    b = bubble(turn)
    expect(b.find(".debate-turn-phase").text).to eq("Opening statement")
    expect(b).to have_content(/Opening statement\s*·\s*@limteik/)
  end

  it "still renders the speaker's avatar (the no-photo broadcast-safety fallback lives here)" do
    challenger.update_columns(photo: nil, full_name: "Siti Nurhaliza")
    turn = create(:debate_turn, debate: debate, user: challenger, position: 1)
    expect(html(turn)).to include('aria-label="Siti Nurhaliza"')
  end

  it "renders the turn body" do
    turn = create(:debate_turn, debate: debate, user: challenger, position: 1, body: "Tabs are one keystroke.")
    expect(bubble(turn)).to have_content("Tabs are one keystroke.")
  end
end
