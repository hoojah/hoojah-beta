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
    #
    # Task 4.2 wraps the actor handle in <strong>, and Slice B links that handle to the
    # actor's profile via ui/_user_link, so "@rival challenged you to a debate" is no
    # longer one contiguous text run — a hovercard <a> now sits between the </strong> and
    # the sentence. Assert the bolded handle and the rest of the sentence as separate
    # substrings instead of stitching HTML across the tag.
    it "renders copy for every debate category rather than a blank row" do
      rival = create(:user, username: "rival")
      debate = create(:debate, challenger: me, opponent: rival)
      %i[debate_challenge debate_declined debate_your_turn debate_concluded].each do |category|
        create(:notification, user: me, category:, debate:,
          hujah: debate.hujah, subject_user: rival)
      end
      sign_in me
      get "/notifications"
      expect(response.body).to include("<strong>@rival</strong>")
      expect(response.body).to include("challenged you to a debate")
      expect(response.body).to include("declined your debate challenge")
      # "It's" is HTML-escaped in the rendered page — assert past the apostrophe.
      expect(response.body).to include("your turn in your debate with")
      expect(response.body).to include("has concluded")
    end

    # Slice B (navbar-hovercard-follows): the notification actor handle is now a real
    # <a> to the actor's profile carrying the hovercard controller — keyboard-focusable,
    # middle-clickable, JS-off navigable. Assert the anchor, its href, and the trigger.
    it "links the actor handle to the profile with a hovercard trigger" do
      rival = create(:user, username: "rival")
      debate = create(:debate, challenger: me, opponent: rival)
      create(:notification, user: me, category: :debate_challenge, debate:,
        hujah: debate.hujah, subject_user: rival)
      sign_in me
      get "/notifications"
      expect(response.parsed_body.css('a[href="/u/rival"][data-controller="hovercard"] strong'))
        .to be_present
    end

    # Secret ballot / nil-actor categories: new_vote carries no subject_user by
    # construction, so its card must render WITHOUT raising and WITHOUT any profile link
    # for a (non-existent) actor. The generic icon-tile + "new vote" copy names no one.
    it "renders a nil-actor new_vote notification with no actor profile link" do
      hujah = create(:hujah, user: me)
      create(:notification, user: me, category: :new_vote, hujah:, subject_user: nil)
      sign_in me
      get "/notifications"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("You have a new vote on your hoojah")
      expect(response.parsed_body.css('a[data-controller="hovercard"]')).to be_empty
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

    # The two moderation notifications carry NO moderator identity (subject_user_id nil,
    # same secret-ballot shape as new_vote). moderation_removed's hoojah is removed, so
    # visible_to? is false even for its author — the body must NOT leak into the card,
    # but the row must still offer a way to clear itself. moderation_warning leaves the
    # content active, so the author still sees the body preview.
    it "renders the removal notification without leaking the removed body, keeping a mark-read affordance" do
      hujah = create(:hujah, user: me, body: "the removed claim body", moderation_status: :removed)
      create(:notification, user: me, category: :moderation_removed, hujah:, subject_user: nil)
      sign_in me
      get "/notifications"
      expect(response.body).to include("Your hoojah was removed by a moderator for violating community guidelines")
      expect(response.body).not_to include("the removed claim body")
      expect(response.body).to include("Mark as read")
    end

    it "renders the warning notification with the still-visible body preview" do
      hujah = create(:hujah, user: me, body: "the warned claim body")
      create(:notification, user: me, category: :moderation_warning, hujah:, subject_user: nil)
      sign_in me
      get "/notifications"
      expect(response.body).to include("A moderator has issued a warning about your hoojah")
      expect(response.body).to include("the warned claim body")
    end

    it "always offers a mark-read affordance, even with no visible hoojah attached" do
      create(:notification, user: me, category: :admin, hujah: nil, subject_user: nil)
      sign_in me
      get "/notifications"
      expect(response.body).to include("Mark as read")
    end

    it "renders a sticky header with a mark-all-read control and the three filter pills" do
      sign_in me
      get "/notifications"
      expect(response.body).to include("Mark all read")
      expect(response.body).to include(">All<")
      expect(response.body).to include(">Mentions<")
      expect(response.body).to include(">Debates<")
    end

    describe "?filter=" do
      it "defaults to every category with no filter param" do
        mention = create(:notification, user: me, category: :mention)
        debate = create(:debate, challenger: me)
        challenge = create(:notification, user: me, category: :debate_challenge, debate:, hujah: debate.hujah)
        sign_in me
        get "/notifications"
        expect(response.body).to include(dom_id(mention))
        expect(response.body).to include(dom_id(challenge))
      end

      it "filter=mentions scopes to the mention category only" do
        mention = create(:notification, user: me, category: :mention)
        other_category = create(:notification, user: me, category: :new_follower)
        sign_in me
        get "/notifications", params: {filter: "mentions"}
        expect(response.body).to include(dom_id(mention))
        expect(response.body).not_to include(dom_id(other_category))
      end

      it "filter=debates scopes to all four debate_* categories" do
        debate = create(:debate, challenger: me)
        debate_notifications = %i[debate_challenge debate_declined debate_your_turn debate_concluded].map do |category|
          create(:notification, user: me, category:, debate:, hujah: debate.hujah)
        end
        non_debate = create(:notification, user: me, category: :mention)
        sign_in me
        get "/notifications", params: {filter: "debates"}
        debate_notifications.each { |n| expect(response.body).to include(dom_id(n)) }
        expect(response.body).not_to include(dom_id(non_debate))
      end
    end
  end

  describe "PATCH /notifications/read_all" do
    it "marks only the current user's unread notifications read, via a Turbo Stream" do
      mine_unread = create(:notification, user: me, read: false)
      mine_already_read = create(:notification, user: me, read: true)
      sign_in me
      patch "/notifications/read_all", headers: {"Accept" => "text/vnd.turbo-stream.html"}
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(mine_unread.reload.read).to be(true)
      expect(mine_already_read.reload.read).to be(true)
    end

    # IDOR / scope-only: the action takes no id/ids param at all, so a forged one
    # in params has literally nothing to bind to — it can only ever update rows
    # already scoped to the signed-in user via policy_scope(Notification).unread.
    it "never marks another user's notification read, even if its id is forged in params" do
      theirs_unread = create(:notification, user: other, read: false)
      sign_in me
      patch "/notifications/read_all", params: {id: theirs_unread.id, ids: [theirs_unread.id]},
        headers: {"Accept" => "text/vnd.turbo-stream.html"}
      expect(theirs_unread.reload.read).to be(false)
    end

    it "requires login" do
      patch "/notifications/read_all"
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
