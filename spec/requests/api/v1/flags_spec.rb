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

    it "requires authentication (401 for a guest)" do
      expect {
        post "/api/v1/flags/create",
          params: {flag: {hujah_id: hujah.id, subject: "spam"}}, as: :json
      }.not_to change(Flag, :count)

      expect(response).to have_http_status(:unauthorized)
    end

    # Regression for SECURITY-FINDINGS L1: `.create` + `if flag` was always truthy, so
    # an unsaveable flag rendered 200 and reported success. `belongs_to :hujah` is
    # required by default, so a nonexistent hujah_id fails validation before the DB.
    it "rejects a flag against a nonexistent hoojah instead of reporting success" do
      login_as(user)

      expect {
        post "/api/v1/flags/create",
          params: {flag: {hujah_id: 0, subject: "spam"}}
      }.not_to change(Flag, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response).not_to have_http_status(:ok)
      expect(response.parsed_body).to have_key("hujah")
    end

    it "ignores a spoofed user_id and records the flag under the current user" do
      other = create(:user)
      login_as(user)

      post "/api/v1/flags/create",
        params: {flag: {hujah_id: hujah.id, subject: "abusive", user_id: other.id}}

      expect(Flag.last.user).to eq(user)
      expect(Flag.last.user).not_to eq(other)
      expect(Flag.last.abusive?).to eq(true)
    end
  end
end
