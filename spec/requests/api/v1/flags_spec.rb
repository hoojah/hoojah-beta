require "rails_helper"

RSpec.describe "Api::V1::Flags", type: :request do
  let(:user) { create(:user) }
  let(:hujah) { create(:hujah) }

  describe "POST /api/v1/flags/create" do
    it "creates a flag owned by the current user" do
      login_as(user)

      expect {
        post "/api/v1/flags/create",
          params: {flag: {hujah_id: hujah.id, subject: "spam"}}
      }.to change(Flag, :count).by(1)

      expect(Flag.last.user).to eq(user)
      expect(Flag.last.spam?).to eq(true)
    end
  end
end
