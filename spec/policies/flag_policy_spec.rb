require "rails_helper"

RSpec.describe FlagPolicy do
  let(:user) { create(:user) }

  it "permits create for any logged-in user" do
    expect(FlagPolicy.new(user, Flag).create?).to be(true)
    expect(FlagPolicy.new(nil, Flag).create?).to be(false)
  end
end
