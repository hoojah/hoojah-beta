require "rails_helper"

RSpec.describe UserPolicy do
  let(:user) { create(:user) }
  let(:other) { create(:user) }

  it "permits update only for oneself" do
    expect(UserPolicy.new(user, user).update?).to be(true)
    expect(UserPolicy.new(other, user).update?).to be(false)
    expect(UserPolicy.new(nil, user).update?).to be(false)
  end
end
