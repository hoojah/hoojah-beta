require "rails_helper"

RSpec.describe NotificationPolicy do
  let(:owner) { create(:user) }
  let(:other) { create(:user) }
  let(:notification) { Notification.create!(user: owner, category: :announcement, read: false) }

  it "permits update/destroy only for the owner" do
    expect(NotificationPolicy.new(owner, notification).update?).to be(true)
    expect(NotificationPolicy.new(other, notification).update?).to be(false)
    expect(NotificationPolicy.new(nil, notification).update?).to be(false)

    expect(NotificationPolicy.new(owner, notification).destroy?).to be(true)
    expect(NotificationPolicy.new(other, notification).destroy?).to be(false)
    expect(NotificationPolicy.new(nil, notification).destroy?).to be(false)
  end

  describe "Scope" do
    it "returns only the current user notifications" do
      mine = Notification.create!(user: owner, category: :announcement)
      Notification.create!(user: other, category: :announcement)

      resolved = NotificationPolicy::Scope.new(owner, Notification).resolve
      expect(resolved).to include(mine)
      expect(resolved.where(user: other)).to be_empty
    end

    it "returns nothing for a nil user" do
      Notification.create!(user: owner, category: :announcement)
      expect(NotificationPolicy::Scope.new(nil, Notification).resolve).to be_empty
    end
  end
end
