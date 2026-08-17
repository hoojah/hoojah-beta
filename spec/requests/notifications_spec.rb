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

    # All four fire on every real debate, and each used to render as a bare row with
    # no icon and no "what happened" line at all.
    it "renders copy for every debate category rather than a blank row" do
      rival = create(:user, username: "rival")
      debate = create(:debate, challenger: me, opponent: rival)
      %i[debate_challenge debate_declined debate_your_turn debate_concluded].each do |category|
        create(:notification, user: me, category:, debate:,
          hujah: debate.hujah, subject_user: rival)
      end
      sign_in me
      get "/notifications"
      expect(response.body).to include("@rival challenged you to a debate")
      expect(response.body).to include("@rival declined your debate challenge")
      # "It's" is HTML-escaped in the rendered page — assert past the apostrophe.
      expect(response.body).to include("your turn in your debate with @rival")
      expect(response.body).to include("Your debate with @rival has concluded")
    end

    # Nothing creates these two — they are enum values inherited from the retired
    # React SPA, and this DB was migrated in place, so rows may still exist.
    it "renders copy for the legacy admin and flag categories" do
      create(:notification, user: me, category: :admin)
      create(:notification, user: me, category: :flag)
      sign_in me
      get "/notifications"
      expect(response.body).to include("You have a message from the Hoojah team")
      expect(response.body).to include("Your hoojah was flagged for review")
    end

    it "always offers a mark-read affordance, even with no visible hoojah attached" do
      create(:notification, user: me, category: :admin, hujah: nil, subject_user: nil)
      sign_in me
      get "/notifications"
      expect(response.body).to include("Mark as read")
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

    # The debate wins over the hoojah: `debate_*` notifications carry both ids, and
    # the example above (no debate) now pins the second branch of that precedence.
    it "redirects to the debate when the notification carries one" do
      debate = create(:debate, challenger: me)
      notification = create(:notification, user: me, read: false,
        category: :debate_your_turn, debate:, hujah: debate.hujah)
      sign_in me
      patch "/notifications/#{notification.id}"
      expect(notification.reload.read).to be(true)
      expect(response).to redirect_to(debate_path(debate.slug))
    end

    it "falls back to the notifications list when neither a debate nor a hoojah is attached" do
      notification = create(:notification, user: me, category: :announcement, hujah: nil)
      sign_in me
      patch "/notifications/#{notification.id}"
      expect(response).to redirect_to(notifications_path)
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
