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

    it "renders the empty state when nothing is pending" do
      sign_in moderator
      get "/moderation"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nothing to review.")
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

  # Slice 6 (image attachments): the "Remove image only" button surfaces in the queue row
  # ONLY when the hujah still has a live image AND a pending image-subject report.
  describe "the Remove image only affordance in the queue" do
    it "appears only for a hujah with a pending image flag, not a text-only report" do
      imaged = create(:hujah, body: "Claim with a flagged image")
      imaged.image.attach(
        io: file_fixture("test_image.png").open, filename: "photo.png", content_type: "image/png"
      )
      create(:flag, hujah: imaged, subject: :image_graphic)

      text_only = create(:hujah, body: "Claim with only a text report")
      create(:flag, hujah: text_only, subject: :spam)

      sign_in moderator
      get "/moderation"

      expect(response.body).to include("Remove image only")
      expect(response.body).to include(remove_image_moderation_path(imaged.slug))
      # exactly one row carries the button — the text-only report does not
      expect(response.body.scan("Remove image only").size).to eq(1)
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

  # Slice 6 (image attachments): the "Remove image only" outcome. Only the image is taken
  # down; the claim stays active/votable, and a non-image report keeps the row in the queue.
  describe "DELETE /moderation/:slug/image" do
    def imaged_flagged_hujah
      hujah = create(:hujah, body: "Claim carrying a flagged image")
      hujah.image.attach(
        io: file_fixture("test_image.png").open, filename: "photo.png", content_type: "image/png"
      )
      create(:flag, hujah: hujah, user: create(:user), subject: :image_graphic)
      hujah
    end

    it "denies a plain member and leaves the image in place" do
      hujah = imaged_flagged_hujah
      sign_in member
      delete "/moderation/#{hujah.slug}/image"
      expect(response).to redirect_to(root_path)
      expect(hujah.reload.image_removed_at).to be_nil
    end

    it "removes only the image, keeps the claim active, and notifies the author anonymously" do
      hujah = imaged_flagged_hujah
      sign_in moderator

      expect {
        delete "/moderation/#{hujah.slug}/image"
      }.to change { Notification.where(category: :image_removed).count }.by(1)

      hujah.reload
      expect(hujah.image_removed_at).to be_present
      expect(hujah.moderation_status).to eq("active")
      expect(hujah.flags.where(subject: Hujah::IMAGE_FLAG_SUBJECTS).map(&:status).uniq).to eq(["actioned"])

      note = Notification.where(category: :image_removed).last
      expect(note.user_id).to eq(hujah.user_id)
      expect(note.hujah_id).to eq(hujah.id)
      expect(note.subject_user_id).to be_nil
    end

    it "responds with a Turbo Stream that refreshes the count and drops the image-only row" do
      hujah = imaged_flagged_hujah
      sign_in moderator

      delete "/moderation/#{hujah.slug}/image",
        headers: {"Accept" => "text/vnd.turbo-stream.html"}

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include(ActionView::RecordIdentifier.dom_id(hujah, :moderation_item))
      expect(response.body).to include("moderation-pending-count")
    end

    it "keeps the row (replace) when a non-image report is still pending" do
      hujah = imaged_flagged_hujah
      create(:flag, hujah: hujah, user: create(:user), subject: :spam)
      sign_in moderator

      delete "/moderation/#{hujah.slug}/image",
        headers: {"Accept" => "text/vnd.turbo-stream.html"}

      expect(response.body).to include("turbo-stream action=\"replace\"")
      expect(response.body).to include(ActionView::RecordIdentifier.dom_id(hujah, :moderation_item))
    end

    # B4: a legacy nil-subject pending flag (subject is nullable pre-Slice-5) is a remaining
    # non-image report — NOT IN excludes NULLs, so the OR(subject: nil) branch must keep the
    # row rather than dropping it while the count chip still counts the nil row.
    it "keeps the row (replace) when the only other pending flag is a legacy nil-subject one" do
      hujah = imaged_flagged_hujah
      legacy = build(:flag, hujah: hujah, user: create(:user), subject: nil)
      legacy.save!(validate: false)
      sign_in moderator

      delete "/moderation/#{hujah.slug}/image",
        headers: {"Accept" => "text/vnd.turbo-stream.html"}

      expect(response.body).to include("turbo-stream action=\"replace\"")
      expect(response.body).to include(ActionView::RecordIdentifier.dom_id(hujah, :moderation_item))
    end

    it "is idempotent — a second image removal does not re-notify" do
      hujah = imaged_flagged_hujah
      sign_in moderator

      delete "/moderation/#{hujah.slug}/image"
      expect {
        delete "/moderation/#{hujah.slug}/image"
      }.not_to change(Notification, :count)
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

  # M-1: set_hujah must not run before authorization, or a non-staff member gets a
  # "Not allowed." redirect for an existing slug vs a 404 for a missing one — an
  # existence oracle. Both cases must produce the SAME non-committal outcome.
  describe "existence oracle (M-1)" do
    it "gives a plain member the same outcome for an existing and a nonexistent slug" do
      hujah = create(:hujah)
      create(:flag, hujah: hujah)
      sign_in member

      patch "/moderation/#{hujah.slug}/dismiss"
      existing_status = response.status
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Not allowed.")

      patch "/moderation/no-such-slug/dismiss"
      expect(response.status).to eq(existing_status)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Not allowed.")
    end
  end

  # L-1: a second removal is a no-op — Hujah#remove! early-returns on an
  # already-removed record, so the author is never re-notified.
  describe "remove idempotency (L-1)" do
    it "creates exactly one moderation_removed notification when remove is called twice" do
      hujah = create(:hujah)
      create(:flag, hujah: hujah)
      sign_in moderator

      delete "/moderation/#{hujah.slug}/remove"
      expect {
        delete "/moderation/#{hujah.slug}/remove"
      }.not_to change(Notification, :count)

      expect(Notification.where(category: :moderation_removed, hujah_id: hujah.id).count).to eq(1)
    end
  end
end
