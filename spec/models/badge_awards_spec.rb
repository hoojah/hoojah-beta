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

RSpec.describe "first_custom_hoojah badge (Slice 3)", type: :model do
  let(:user) { create(:user) }

  def eligible!(u)
    create_list(:hujah, 10, user: u)
  end

  it "registers the badge key" do
    expect(Badge::REGISTRY).to have_key("first_custom_hoojah")
  end

  it "awards first_custom_hoojah when an eligible author posts a top-level custom hoojah" do
    eligible!(user)
    expect {
      user.hujahs.create!(body: "a claim with custom stances", agree_label: "Yes")
    }.to change { user.user_badges.where(badge_key: "first_custom_hoojah").count }.by(1)
  end

  it "does not award it for a default top-level hoojah" do
    eligible!(user)
    expect {
      user.hujahs.create!(body: "a plain default claim body")
    }.not_to change { user.user_badges.where(badge_key: "first_custom_hoojah").count }
  end

  it "does not award it when labels are coerced away for an ineligible author" do
    # Zero prior posts → ineligible → labels nilled → not a custom post.
    expect {
      user.hujahs.create!(body: "a claim that wanted custom stances", agree_label: "Yes")
    }.not_to change { user.user_badges.where(badge_key: "first_custom_hoojah").count }
  end

  it "awards it at most once" do
    eligible!(user)
    user.hujahs.create!(body: "first custom claim body", agree_label: "Yes")
    expect {
      user.hujahs.create!(body: "second custom claim body", disagree_label: "No")
    }.not_to change { user.user_badges.where(badge_key: "first_custom_hoojah").count }
  end
end
