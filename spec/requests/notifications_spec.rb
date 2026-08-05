require "rails_helper"

RSpec.describe "Notifications", type: :request do
  include ActionView::RecordIdentifier

  let(:me) { create(:user) }
  let(:other) { create(:user) }

  describe "GET /notifications" do
    it "lists only the current user's notifications" do
      mine = create(:notification, user: me)
      theirs = create(:notification, user: other)
      sign_in me
      get "/notifications"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(dom_id(mine))
      expect(response.body).not_to include(dom_id(theirs))
    end

    it "requires login" do
      get "/notifications"
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "PATCH /notifications/:id" do
    it "marks the notification read and redirects to the hoojah" do
      notification = create(:notification, user: me, read: false)
      sign_in me
      patch "/notifications/#{notification.id}"
      expect(notification.reload.read).to be(true)
      expect(response).to redirect_to(hujah_path(notification.hujah.slug))
    end
  end

  describe "DELETE /notifications/:id" do
    it "removes the card via a Turbo Stream" do
      notification = create(:notification, user: me)
      sign_in me
      delete "/notifications/#{notification.id}",
        headers: {"Accept" => "text/vnd.turbo-stream.html"}
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("turbo-stream")
      expect(response.body).to include(dom_id(notification))
      expect(Notification.exists?(notification.id)).to be(false)
    end

    it "forbids deleting another user's notification" do
      theirs = create(:notification, user: other)
      sign_in me
      delete "/notifications/#{theirs.id}",
        headers: {"Accept" => "text/vnd.turbo-stream.html"}
      expect(response).to have_http_status(:forbidden)
      expect(Notification.exists?(theirs.id)).to be(true)
    end
  end
end
