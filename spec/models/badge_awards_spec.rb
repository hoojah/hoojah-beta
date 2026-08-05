require "rails_helper"

RSpec.describe "Badge awards", type: :model do
  it "first_hoojah on a top-level create; first_argument on a child" do
    u = create(:user)
    top = create(:hujah, user: u)
    expect(u.user_badges.pluck(:badge_key)).to include("first_hoojah")
    child_author = create(:user)
    create(:hujah, user: child_author, parent: top)
    expect(child_author.user_badges.pluck(:badge_key)).to include("first_argument")
  end

  it "first_follower on follow; first_debate on conclude (both participants)" do
    a = create(:user)
    b = create(:user)
    a.active_follows.create!(followed: b, status: :accepted)
    expect(b.user_badges.pluck(:badge_key)).to include("first_follower")
    hujah = create(:hujah)
    create(:hujah, parent: hujah, user: b, vote: 3)
    d = a.challenged_debates.create!(hujah: hujah, opponent: b, challenger_stance: 1, opponent_stance: 3)
    d.accept!(by: b)
    d.conclude!(by: a)
    expect(a.user_badges.pluck(:badge_key)).to include("first_debate")
    expect(b.user_badges.pluck(:badge_key)).to include("first_debate")
  end

  it "casting a vote still commits the vote (no milestone check poisons the tx)" do
    owner = create(:user)
    voter = create(:user)
    h = create(:hujah, user: owner)
    expect { h.cast_vote(by: voter, choice: 1) }.to change { h.reload.agree_count }.by(1)
  end
end
