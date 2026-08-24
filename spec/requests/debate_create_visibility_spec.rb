require "rails_helper"

# Phase 3.2 leak (caught by the Phase 3 Fable audit): the standalone debates/new page
# renders @hujah.body + the @argument author card, and is authorized by DebatePolicy#create?
# (Pundit falls new? -> create?). Before Phase 3.7-fix, create? had NO visibility clause, so
# GET /hoojah/:slug/debates/new?argument_id=N (an enumerable id) let any signed-in stranger
# read a followers_only/private_only claim and a private argument author's card — content
# DebatePolicy#show? / HujahPolicy#show? both deny. create? now mirrors show?'s visibility gate.
RSpec.describe "Debate create-page visibility", type: :request do
  let(:author) { create(:user) }

  def new_debate_get(claim, argument, as:)
    sign_in(User.find(as.id))
    get "/hoojah/#{claim.slug}/debates/new", params: {argument_id: argument.id}
  end

  def create_post(claim, argument, as:)
    sign_in(User.find(as.id))
    post "/hoojah/#{claim.slug}/debates", params: {argument_id: argument.id, challenger_stance: 1}
  end

  describe "a followers_only claim" do
    let!(:claim) { create(:hujah, user: author, visibility: :followers_only, body: "Secret followers-only motion") }
    let!(:argument) { create(:hujah, parent: claim, user: create(:user), vote: 3) }
    let(:stranger) { create(:user) }

    it "denies GET new to a non-follower and does not render the claim body" do
      new_debate_get(claim, argument, as: stranger)
      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to include("Secret followers-only motion")
    end

    it "denies POST create to a non-follower (no debate created)" do
      expect { create_post(claim, argument, as: stranger) }.not_to change(Debate, :count)
      expect(response).to have_http_status(:forbidden)
    end

    it "allows GET new to an accepted follower who can see the claim" do
      follower = create(:user)
      Follow.create!(follower: follower, followed: author, status: :accepted)
      new_debate_get(claim, argument, as: follower)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Secret followers-only motion")
    end
  end

  describe "a private_only claim" do
    let!(:claim) { create(:hujah, user: author, visibility: :private_only, body: "Private-only motion") }
    let!(:argument) { create(:hujah, parent: claim, user: create(:user), vote: 3) }

    it "denies GET new to everyone but the owner" do
      new_debate_get(claim, argument, as: create(:user))
      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to include("Private-only motion")
    end
  end

  describe "a public claim whose argument author (opponent) is a private account" do
    let!(:claim) { create(:hujah, user: author, visibility: :visible_public, body: "Public motion") }
    let!(:private_opponent) { create(:user, private: true) }
    let!(:argument) { create(:hujah, parent: claim, user: private_opponent, vote: 3) }

    it "denies GET new to a non-follower of the private opponent" do
      new_debate_get(claim, argument, as: create(:user))
      expect(response).to have_http_status(:forbidden)
    end
  end
end
