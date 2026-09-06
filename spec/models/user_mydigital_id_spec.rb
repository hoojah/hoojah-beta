require "rails_helper"

RSpec.describe "User MyDigital ID linking", type: :model do
  def mydid_auth(sub:, name: "Ali bin Abu")
    OmniAuth::AuthHash.new(provider: "my_digital_id", uid: sub, info: {name: name})
  end

  describe ".from_my_digital_id" do
    it "returns the user owning the matching identity" do
      user = create(:user)
      user.identities.create!(provider: "my_digital_id", uid: "sub-known")
      expect(User.from_my_digital_id(mydid_auth(sub: "sub-known"))).to eq(user)
    end

    it "returns nil for an unknown sub (never auto-creates, never matches email)" do
      create(:user, email: "someone@hoojah.com")
      expect(User.from_my_digital_id(mydid_auth(sub: "sub-unknown"))).to be_nil
    end
  end

  describe ".create_with_my_digital_id" do
    it "creates a usable account + identity, no NRIC anywhere" do
      user = User.create_with_my_digital_id(username: "newperson", sub: "sub-new", full_name: "Ali bin Abu")
      expect(user).to be_persisted
      expect(user.full_name).to eq("Ali bin Abu")
      expect(user.encrypted_password).to be_present
      expect(user.identities.pluck(:provider, :uid)).to eq([["my_digital_id", "sub-new"]])
    end

    it "returns an unsaved user with errors on a taken username" do
      create(:user, username: "taken")
      user = User.create_with_my_digital_id(username: "taken", sub: "sub-x", full_name: "X")
      expect(user).not_to be_persisted
      expect(user.errors[:username]).to be_present
    end

    it "enforces one hoojah account per MyDigital ID under a race" do
      User.create_with_my_digital_id(username: "firstperson", sub: "sub-race", full_name: "A")
      again = User.create_with_my_digital_id(username: "secondperson", sub: "sub-race", full_name: "B")
      expect(UserIdentity.where(provider: "my_digital_id", uid: "sub-race").count).to eq(1)
      expect(again.identities).to be_empty.or eq(User.find_by(username: "firstperson").identities)
    end

    it "is idempotent when the sub is already linked — returns the existing account, no orphan user" do
      first = User.create_with_my_digital_id(username: "firstperson", sub: "sub-idem", full_name: "A")
      expect {
        again = User.create_with_my_digital_id(username: "secondperson", sub: "sub-idem", full_name: "B")
        expect(again).to eq(first)
      }.not_to change(User, :count)
      expect(UserIdentity.where(provider: "my_digital_id", uid: "sub-idem").count).to eq(1)
    end
  end
end
