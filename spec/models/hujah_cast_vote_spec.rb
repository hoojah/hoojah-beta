require "rails_helper"

RSpec.describe "Hujah#cast_vote", type: :model do
  let(:owner) { create(:user) }
  let(:voter) { create(:user) }
  let(:hujah) { create(:hujah, user: owner, agree_count: 0, neutral_count: 0, disagree_count: 0) }

  it "records a first vote, bumps the counter, notifies the owner" do
    expect { hujah.cast_vote(by: voter, choice: 1) }
      .to change { hujah.reload.agree_count }.by(1)
      .and change { Notification.where(user: owner, category: "new_vote").count }.by(1)
    expect(Vote.find_by(user: voter, hujah: hujah).vote.last).to eq(1)
  end

  it "switches a vote: increments new stance, decrements old, no double count" do
    hujah.cast_vote(by: voter, choice: 1)
    expect { hujah.cast_vote(by: voter, choice: 3) }
      .to change { hujah.reload.disagree_count }.by(1)
      .and change { hujah.reload.agree_count }.by(-1)
    expect(Vote.find_by(user: voter, hujah: hujah).vote).to eq([1, 3])
  end

  it "re-casting the same stance is a no-op on counters" do
    hujah.cast_vote(by: voter, choice: 2)
    expect { hujah.cast_vote(by: voter, choice: 2) }.not_to change { hujah.reload.neutral_count }
  end

  it "does not record the voter identity on the new_vote notification (privacy)" do
    owner = create(:user)
    voter = create(:user)
    h = create(:hujah, user: owner)
    h.cast_vote(by: voter, choice: 1)
    n = Notification.where(user: owner, category: "new_vote").last
    expect(n.subject_user_id).to be_nil
  end
end
