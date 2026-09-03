require "rails_helper"

RSpec.describe PasskeyPolicy do
  let(:owner) { create(:user) }
  let(:credential) { create(:webauthn_credential, user: owner) }

  it "permits update/destroy only for the credential's owner" do
    expect(PasskeyPolicy.new(owner, credential).update?).to be(true)
    expect(PasskeyPolicy.new(owner, credential).destroy?).to be(true)
  end

  it "forbids update/destroy for a non-owner" do
    other = create(:user)
    expect(PasskeyPolicy.new(other, credential).update?).to be(false)
    expect(PasskeyPolicy.new(other, credential).destroy?).to be(false)
  end

  it "forbids update/destroy when there is no user" do
    expect(PasskeyPolicy.new(nil, credential).update?).to be(false)
    expect(PasskeyPolicy.new(nil, credential).destroy?).to be(false)
  end
end
