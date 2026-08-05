require "rails_helper"

RSpec.describe UserBadge, type: :model do
  let(:u) { create(:user) }

  it "awards once + notifies once, idempotent" do
    expect { UserBadge.award(u, "first_hoojah") }
      .to change { u.user_badges.count }.by(1)
      .and change { Notification.where(user: u, category: "badge_earned").count }.by(1)
    expect { UserBadge.award(u, "first_hoojah") }.not_to change { u.user_badges.count }
  end

  it "rejects an unknown badge_key" do
    expect(UserBadge.new(user: u, badge_key: "nope")).not_to be_valid
  end

  it "User#badges is nil-safe on a stale registry key" do
    u.user_badges.create!(badge_key: "first_hoojah")
    UserBadge.where(user: u).update_all(badge_key: "removed_badge") # simulate a renamed/removed key
    expect { u.badges }.not_to raise_error
    expect(u.badges).to eq([])
  end
end
