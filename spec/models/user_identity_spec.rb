require "rails_helper"

RSpec.describe UserIdentity, type: :model do
  it "requires provider and uid" do
    identity = UserIdentity.new(user: create(:user))
    expect(identity).not_to be_valid
    expect(identity.errors.attribute_names).to include(:provider, :uid)
  end

  it "enforces uniqueness of uid within a provider" do
    create(:user_identity, provider: "my_digital_id", uid: "dup")
    dupe = build(:user_identity, provider: "my_digital_id", uid: "dup")
    expect(dupe).not_to be_valid
  end

  it "allows the same uid under a different provider" do
    create(:user_identity, provider: "my_digital_id", uid: "shared")
    other = build(:user_identity, provider: "google_oauth2", uid: "shared")
    expect(other).to be_valid
  end
end
