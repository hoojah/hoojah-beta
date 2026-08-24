require "rails_helper"

RSpec.describe Hujah, type: :model do
  describe "new-record defaults" do
    it "defaults to visible_public, allow_debates true, conviction_count 0" do
      h = Hujah.new
      expect(h.visibility_visible_public?).to be true
      expect(h.allow_debates).to be true
      expect(h.conviction_count).to eq 0
    end
  end

  describe "#current_user_vote" do
    let!(:user) { create(:user) }
    let!(:hujah) { create(:hujah) }
    context "if logged in without voting" do
      it "will return nil" do
        result = hujah.current_user_vote(logged_in: true, current_user_id: user.id)
        expect(result).to eq(nil)
      end
    end

    context "if logged in and has voted" do
      let!(:vote) { create(:vote, :agree, user: user, hujah: hujah) }
      it "will return vote value" do
        result = hujah.current_user_vote(logged_in: true, current_user_id: user.id)
        expect(result).to eq("agree")
      end
    end

    context "if not logged in" do
      it "will return nil" do
        result = hujah.current_user_vote(logged_in: false, current_user_id: nil)
        expect(result).to eq(nil)
      end
    end
  end
end
