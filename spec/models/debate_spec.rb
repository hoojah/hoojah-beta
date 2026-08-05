require "rails_helper"

RSpec.describe Debate, type: :model do
  let(:hujah) { create(:hujah) }
  let(:challenger) { create(:user) }
  let(:opponent) { create(:user) }

  def build_debate(cs: 1, os: 3)
    challenger.challenged_debates.create!(hujah: hujah, opponent: opponent,
      challenger_stance: cs, opponent_stance: os)
  end

  it "notifies the opponent on challenge (pending)" do
    expect { build_debate }.to change { Notification.where(user: opponent, category: "debate_challenge").count }.by(1)
  end

  it "rejects equal stances and self-challenge" do
    expect { build_debate(cs: 1, os: 1) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(challenger.challenged_debates.build(hujah: hujah, opponent: challenger, challenger_stance: 1, opponent_stance: 3)).not_to be_valid
  end

  it "accept! -> active, challenger moves first, notifies debate_your_turn to challenger" do
    d = build_debate
    expect { d.accept!(by: opponent) }.to change { Notification.where(user: challenger, category: "debate_your_turn").count }.by(1)
    expect(d).to be_active
    expect(d.current_turn_user).to eq(challenger)
  end

  it "only opponent can accept/decline, only when pending" do
    d = build_debate
    expect(d.accept!(by: challenger)).to be(false) # not the opponent
    d.accept!(by: opponent)
    expect(d.decline!(by: opponent)).to be(false) # not pending
  end

  it "post_turn enforces turn order + alternation + notifies the other" do
    d = build_debate
    d.accept!(by: opponent)
    expect(d.post_turn(by: opponent, body: "x")).to be(false) # it IS challenger's turn
    expect(d.post_turn(by: challenger, body: "c1")).to be_truthy
    expect(d.current_turn_user).to eq(opponent)
    expect(d.post_turn(by: challenger, body: "again")).to be(false) # out of turn
    expect { d.post_turn(by: opponent, body: "o1") }
      .to change { Notification.where(user: challenger, category: "debate_your_turn").count }.by(1)
    expect(d.turns.order(:position).pluck(:body)).to eq(%w[c1 o1])
  end

  it "conclude! by either participant -> concluded + notifies the other" do
    d = build_debate
    d.accept!(by: opponent)
    expect { d.conclude!(by: challenger) }.to change { Notification.where(user: opponent, category: "debate_concluded").count }.by(1)
    expect(d).to be_concluded
    expect(d.current_turn_user).to be_nil
  end
end
