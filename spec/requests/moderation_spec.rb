require "rails_helper"

RSpec.describe "Moderation queue", type: :request do
  let(:moderator) { create(:user, :moderator) }
  let(:member) { create(:user) }

  describe "GET /moderation" do
    it "redirects an anonymous visitor to login" do
      get "/moderation"
      expect(response).to redirect_to(new_user_session_path)
    end

    it "denies a plain member with the Pundit alert" do
      sign_in member
      get "/moderation"
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Not allowed.")
    end

    it "lists a hujah carrying a pending flag with its report count" do
      hujah = create(:hujah, body: "Contentious claim about durian")
      create(:flag, hujah: hujah, subject: :spam)

      sign_in moderator
      get "/moderation"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Contentious claim about durian")
      expect(response.body).to include(ActionView::RecordIdentifier.dom_id(hujah, :moderation_item))
    end

    it "excludes a hujah whose flags are all resolved" do
      resolved = create(:hujah, body: "Already reviewed claim")
      flag = create(:flag, hujah: resolved)
      flag.resolve!(by: moderator, as: :dismissed)

      sign_in moderator
      get "/moderation"

      expect(response.body).not_to include("Already reviewed claim")
    end

    it "orders oldest-pending-report first" do
      newer = create(:hujah, body: "Newer flagged claim")
      older = create(:hujah, body: "Older flagged claim")
      create(:flag, hujah: older, created_at: 2.hours.ago)
      create(:flag, hujah: newer, created_at: 10.minutes.ago)

      sign_in moderator
      get "/moderation"

      expect(response.body.index("Older flagged claim")).to be < response.body.index("Newer flagged claim")
    end

    it "still lists a removed hujah while its flags are pending (queue is exempt from not_removed)" do
      removed = create(:hujah, body: "Removed but still under review")
      removed.update!(moderation_status: :removed)
      create(:flag, hujah: removed)

      sign_in moderator
      get "/moderation"

      expect(response.body).to include("Removed but still under review")
    end
  end

  # Two pending flags from different users + one already-dismissed flag. The actions
  # resolve only the pending ones and never re-touch a resolved report.
  def flagged_hujah_with_reports
    hujah = create(:hujah, body: "Under review")
    create(:flag, hujah: hujah, user: create(:user), subject: :spam)
    create(:flag, hujah: hujah, user: create(:user), subject: :abusive)
    already = create(:flag, hujah: hujah, user: create(:user), subject: :irrelevant)
    already.resolve!(by: moderator, as: :dismissed)
    [hujah, already]
  end

  describe "PATCH /moderation/:slug/dismiss" do
    it "denies a plain member" do
      hujah = create(:hujah)
      create(:flag, hujah: hujah)
      sign_in member
      patch "/moderation/#{hujah.slug}/dismiss"
      expect(response).to redirect_to(root_path)
      expect(hujah.flags.reload.first).to be_pending
    end

    it "dismisses every pending report without touching resolved ones or the content" do
      hujah, already = flagged_hujah_with_reports
      sign_in moderator

      expect {
        patch "/moderation/#{hujah.slug}/dismiss"
      }.not_to change(Notification, :count)

      pending_after = hujah.flags.reload.where(status: :dismissed).where.not(id: already.id)
      expect(pending_after.count).to eq(2)
      pending_after.each do |flag|
        expect(flag.resolved_by).to eq(moderator)
        expect(flag.resolved_at).to be_present
      end
      expect(hujah.reload).to be_moderation_active
      expect(response).to redirect_to(moderation_path)
      expect(response).to have_http_status(:see_other)
    end

    it "responds with a Turbo Stream that removes the item and refreshes the count" do
      hujah = create(:hujah)
      create(:flag, hujah: hujah)
      sign_in moderator

      patch "/moderation/#{hujah.slug}/dismiss",
        headers: {"Accept" => "text/vnd.turbo-stream.html"}

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include(ActionView::RecordIdentifier.dom_id(hujah, :moderation_item))
      expect(response.body).to include("moderation-pending-count")
    end

    it "is idempotent — a second dismiss with zero pending flags does not raise" do
      hujah = create(:hujah)
      create(:flag, hujah: hujah)
      sign_in moderator

      patch "/moderation/#{hujah.slug}/dismiss"
      patch "/moderation/#{hujah.slug}/dismiss"
      expect(response).to redirect_to(moderation_path)
    end
  end

  describe "DELETE /moderation/:slug/remove" do
    it "denies a plain member" do
      hujah = create(:hujah)
      create(:flag, hujah: hujah)
      sign_in member
      delete "/moderation/#{hujah.slug}/remove"
      expect(response).to redirect_to(root_path)
      expect(hujah.reload).to be_moderation_active
    end

    it "removes the hujah, actions its pending flags, and notifies the author anonymously" do
      hujah, already = flagged_hujah_with_reports
      sign_in moderator

      expect {
        delete "/moderation/#{hujah.slug}/remove"
      }.to change(Notification, :count).by(1)

      expect(hujah.reload).to be_moderation_removed
      expect(hujah.flags.where.not(id: already.id).map(&:status).uniq).to eq(["actioned"])

      note = Notification.last
      expect(note.category).to eq("moderation_removed")
      expect(note.user_id).to eq(hujah.user_id)
      expect(note.hujah_id).to eq(hujah.id)
      expect(note.subject_user_id).to be_nil
    end
  end

  describe "POST /moderation/:slug/warn" do
    it "denies a plain member" do
      hujah = create(:hujah)
      create(:flag, hujah: hujah)
      sign_in member
      post "/moderation/#{hujah.slug}/warn"
      expect(response).to redirect_to(root_path)
      expect(Notification.where(category: :moderation_warning)).to be_empty
      expect(hujah.flags.reload.first).to be_pending
    end

    it "keeps the content, actions its pending flags, and warns the author anonymously" do
      hujah, already = flagged_hujah_with_reports
      sign_in moderator

      expect {
        post "/moderation/#{hujah.slug}/warn"
      }.to change(Notification, :count).by(1)

      expect(hujah.reload).to be_moderation_active
      expect(hujah.flags.where.not(id: already.id).map(&:status).uniq).to eq(["actioned"])

      note = Notification.last
      expect(note.category).to eq("moderation_warning")
      expect(note.user_id).to eq(hujah.user_id)
      expect(note.hujah_id).to eq(hujah.id)
      expect(note.subject_user_id).to be_nil
    end
  end
end
