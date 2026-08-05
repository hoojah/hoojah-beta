require "rails_helper"

RSpec.describe "DebateVerdicts", type: :request do
  def dom_id(*args) = ActionView::RecordIdentifier.dom_id(*args)

  let(:challenger) { create(:user) }
  let(:opponent) { create(:user) }
  let(:spectator) { create(:user) }

  def debate(status:)
    create(:debate, challenger: challenger, opponent: opponent, status: status)
  end

  it "lets a visible spectator vote on a concluded debate (turbo_stream replaces the verdict block)" do
    d = debate(status: :concluded)
    sign_in spectator
    post "/debates/#{d.slug}/verdicts", params: {choice: "challenger"},
      headers: {"Accept" => "text/vnd.turbo-stream.html"}
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(dom_id(d, :verdict))
    expect(d.debate_verdicts.count).to eq(1)
    expect(d.debate_verdicts.first.choice).to eq("challenger")
  end

  it "forbids a participant (403)" do
    d = debate(status: :concluded)
    sign_in challenger
    post "/debates/#{d.slug}/verdicts", params: {choice: "opponent"}
    expect(response).to have_http_status(:forbidden)
    expect(d.debate_verdicts.count).to eq(0)
  end

  it "forbids voting on an active debate (403)" do
    d = debate(status: :active)
    sign_in spectator
    post "/debates/#{d.slug}/verdicts", params: {choice: "challenger"}
    expect(response).to have_http_status(:forbidden)
    expect(d.debate_verdicts.count).to eq(0)
  end

  it "rejects an invalid choice (422)" do
    d = debate(status: :concluded)
    sign_in spectator
    post "/debates/#{d.slug}/verdicts", params: {choice: "nonsense"}
    expect(response).to have_http_status(:unprocessable_content)
    expect(d.debate_verdicts.count).to eq(0)
  end

  it "redirects an unauthenticated visitor to login" do
    d = debate(status: :concluded)
    post "/debates/#{d.slug}/verdicts", params: {choice: "challenger"}
    expect(response).to redirect_to(new_user_session_path)
  end
end
