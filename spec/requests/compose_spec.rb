require "rails_helper"

RSpec.describe "Compose", type: :request do
  let(:user) { create(:user) }

  it "requires login to open the form" do
    get new_hujah_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "creates a top-level hoojah and redirects to it" do
    sign_in user
    expect { post "/hoojah", params: {hujah: {body: "My take"}} }
      .to change(Hujah, :count).by(1)
    expect(response).to have_http_status(:see_other)
  end

  it "creates a response with a stance + notifies the parent owner" do
    sign_in user
    parent = create(:hujah, user: create(:user))
    expect {
      post "/hoojah", params: {hujah: {body: "reply", parent_id: parent.id, vote: 1}}
    }.to change { Notification.where(category: "new_hoojah_response").count }.by(1)
    expect(Hujah.last.vote).to eq([1]).or eq(1) # matches the model's vote column shape
  end

  it "rejects a spoofed missing parent_id" do
    sign_in user
    post "/hoojah", params: {hujah: {body: "x", parent_id: 999_999}}
    expect(response).to have_http_status(:not_found).or have_http_status(:unprocessable_content)
  end
end
