require "rails_helper"

RSpec.describe WebauthnCredential do
  it "is valid with the factory defaults" do
    expect(build(:webauthn_credential)).to be_valid
  end

  it "requires an external_id, public_key, and nickname" do
    credential = build(:webauthn_credential, external_id: nil, public_key: nil, nickname: nil)
    expect(credential).not_to be_valid
    expect(credential.errors.attribute_names).to include(:external_id, :public_key, :nickname)
  end

  it "requires a globally unique external_id" do
    existing = create(:webauthn_credential)
    dup = build(:webauthn_credential, external_id: existing.external_id)
    expect(dup).not_to be_valid
    expect(dup.errors[:external_id]).to be_present
  end

  it "requires a nickname unique per user but allows reuse across users" do
    owner = create(:user)
    create(:webauthn_credential, user: owner, nickname: "Laptop")
    same_owner_dup = build(:webauthn_credential, user: owner, nickname: "Laptop")
    other_owner_ok = build(:webauthn_credential, user: create(:user), nickname: "Laptop")
    expect(same_owner_dup).not_to be_valid
    expect(other_owner_ok).to be_valid
  end

  it "rejects a negative sign_count (clone-detection guard)" do
    credential = build(:webauthn_credential, sign_count: -1)
    expect(credential).not_to be_valid
    expect(credential.errors[:sign_count]).to be_present
  end

  it "is destroyed when its user is destroyed" do
    credential = create(:webauthn_credential)
    expect { credential.user.destroy }.to change(described_class, :count).by(-1)
  end
end
