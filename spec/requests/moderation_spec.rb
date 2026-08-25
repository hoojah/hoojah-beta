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
end
