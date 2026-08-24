require "rails_helper"

RSpec.describe Debate, type: :model do
  let(:hujah) { create(:hujah) }
  let(:challenger) { create(:user) }
  let(:opponent) { create(:user) }

  def build_debate(cs: 1, os: 3, opening_argument: nil)
    challenger.challenged_debates.create!(hujah: hujah, opponent: opponent,
      challenger_stance: cs, opponent_stance: os, opening_argument: opening_argument)
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

  it "accept! with an opening_argument posts it as the challenger's position-1 turn, so the opponent moves next" do
    d = build_debate(opening_argument: "My opening case")

    d.accept!(by: opponent)

    expect(d.turns.count).to eq(1)
    turn = d.turns.order(:position).first
    expect(turn.position).to eq(1)
    expect(turn.user).to eq(challenger)
    expect(turn.body).to eq("My opening case")
    expect(d.current_turn_user).to eq(opponent)
    expect(d.current_round).to eq(1)
    expect(d.current_phase).to eq(:opening)
  end

  it "accept! without an opening_argument behaves exactly as today: no auto turn, challenger moves first" do
    d = build_debate(opening_argument: nil)

    d.accept!(by: opponent)

    expect(d.turns.count).to eq(0)
    expect(d.current_turn_user).to eq(challenger)
    expect(d.current_round).to eq(1)
    expect(d.current_phase).to eq(:opening)
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

  it "conclude!(by: nil) (system/timeout) concludes + notifies BOTH participants without crashing" do
    d = build_debate
    d.accept!(by: opponent)
    expect { expect(d.conclude!(by: nil)).to be(true) }
      .to change { Notification.where(category: "debate_concluded").count }.by(2)
    expect(d).to be_concluded
    expect(Notification.where(user: challenger, category: "debate_concluded").count).to eq(1)
    expect(Notification.where(user: opponent, category: "debate_concluded").count).to eq(1)
  end

  it "conclude!(by: a non-participant) is still refused" do
    d = build_debate
    d.accept!(by: opponent)
    stranger = create(:user)
    expect(d.conclude!(by: stranger)).to be(false)
    expect(d).to be_active
  end

  it "posting a turn bumps debate.updated_at (touch: true)" do
    d = build_debate
    d.accept!(by: opponent)
    d.update_column(:updated_at, 10.days.ago)
    expect { d.post_turn(by: challenger, body: "c1") }.to change { d.reload.updated_at }
  end
end
