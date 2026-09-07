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

  # Slice 5: the subject guard. An image subject only makes sense against a visible
  # image; a missing/garbage subject must never persist a nil/unknown-subject flag.
  describe "subject validation guard" do
    def attach_image(h)
      h.image.attach(
        io: Rails.root.join("spec/fixtures/files/test_image.png").open,
        filename: "t.png", content_type: "image/png"
      )
      h
    end

    it "rejects an image subject when the hoojah has no image" do
      sign_in user

      expect {
        post "/hoojah/#{hujah.slug}/flags", params: {flag: {subject: "image_graphic"}}
      }.not_to change(Flag, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(hujah.flags).to be_empty
    end

    it "rejects a flag whose subject is omitted (nil-subject hole)" do
      sign_in user

      expect {
        post "/hoojah/#{hujah.slug}/flags", params: {flag: {ignored: "1"}}
      }.not_to change(Flag, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects a garbage subject outside the enum" do
      sign_in user

      expect {
        post "/hoojah/#{hujah.slug}/flags", params: {flag: {subject: "libellous"}}
      }.not_to change(Flag, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "still accepts a valid non-image subject on any hoojah (regression)" do
      sign_in user

      expect {
        post "/hoojah/#{hujah.slug}/flags", params: {flag: {subject: "spam"}}
      }.to change(Flag, :count).by(1)

      expect(Flag.last.spam?).to eq(true)
    end

    it "accepts an image subject when the hoojah has a visible image" do
      sign_in user
      attach_image(hujah)

      expect {
        post "/hoojah/#{hujah.slug}/flags", params: {flag: {subject: "image_graphic"}}
      }.to change(Flag, :count).by(1)

      expect(Flag.last.image_graphic?).to eq(true)
    end

    it "rejects an image subject once the image has been moderator-removed" do
      sign_in user
      attach_image(hujah)
      hujah.update!(image_removed_at: Time.current)

      expect {
        post "/hoojah/#{hujah.slug}/flags", params: {flag: {subject: "image_not_theirs"}}
      }.not_to change(Flag, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
