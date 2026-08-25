require "rails_helper"

RSpec.describe "Flag (HTML)", type: :request do
  let(:user) { create(:user) }
  let(:hujah) { create(:hujah) }

  it "requires login to flag a hoojah" do
    expect {
      post "/hoojah/#{hujah.slug}/flags", params: {flag: {subject: "spam"}}
    }.not_to change(Flag, :count)

    expect(response).to redirect_to(new_user_session_path)
  end

  it "creates a flag under the current user and closes the dialog via Turbo Stream" do
    sign_in user

    expect {
      post "/hoojah/#{hujah.slug}/flags",
        params: {flag: {subject: "abusive"}},
        headers: {"Accept" => "text/vnd.turbo-stream.html"}
    }.to change(Flag, :count).by(1)

    expect(response).to have_http_status(:ok)
    flag = Flag.last
    expect(flag.user).to eq(user)
    expect(flag.hujah).to eq(hujah)
    expect(flag.abusive?).to eq(true)

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include("close_dialog")
    expect(response.body).to include(ActionView::RecordIdentifier.dom_id(hujah, :flag_dialog))
  end

  it "is idempotent per user and hoojah — a re-flag updates the reason, not the count" do
    sign_in user

    post "/hoojah/#{hujah.slug}/flags", params: {flag: {subject: "spam"}}
    expect(Flag.count).to eq(1)

    expect {
      post "/hoojah/#{hujah.slug}/flags", params: {flag: {subject: "abusive"}}
    }.not_to change(Flag, :count)

    expect(response).not_to have_http_status(:error)
    flag = user.flags.find_by(hujah: hujah)
    expect(flag.abusive?).to eq(true)
  end
end
