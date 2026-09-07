require "rails_helper"

# B8: the composer direct-uploads through an AUTHENTICATED subclass of
# ActiveStorage::DirectUploadsController. The stock endpoint has no auth; this route gates
# it behind authenticate_user! so an anonymous client can't mint orphan blobs at storage.
RSpec.describe "Authenticated direct uploads", type: :request do
  let(:blob_params) do
    {blob: {filename: "photo.png", byte_size: 4, checksum: Digest::MD5.base64digest("test"), content_type: "image/png"}}
  end

  it "rejects an unauthenticated direct-upload request" do
    post authenticated_direct_uploads_path, params: blob_params, as: :json
    expect(response).to have_http_status(:unauthorized)
      .or have_http_status(:found)
      .or have_http_status(:redirect)
  end

  it "mints a direct-upload for a signed-in user" do
    sign_in create(:user)
    post authenticated_direct_uploads_path, params: blob_params, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to have_key("signed_id")
  end

  # The engine's stock unauthenticated endpoint is SHADOWED in config/routes.rb to the
  # authenticated DirectUploadsController, so the well-known /rails/active_storage path can
  # no longer mint anonymous orphan blobs either (SECURITY-FINDINGS.md IMG1).
  describe "the shadowed stock endpoint POST /rails/active_storage/direct_uploads" do
    it "rejects an unauthenticated request" do
      post "/rails/active_storage/direct_uploads", params: blob_params, as: :json
      expect(response).to have_http_status(:unauthorized)
        .or have_http_status(:found)
        .or have_http_status(:redirect)
    end

    it "mints a direct-upload for a signed-in user" do
      sign_in create(:user)
      post "/rails/active_storage/direct_uploads", params: blob_params, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to have_key("signed_id")
    end
  end
end
