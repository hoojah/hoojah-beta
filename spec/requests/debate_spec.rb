require "rails_helper"

RSpec.describe "Debates", type: :request do
  let(:hujah) { create(:hujah) }
  let(:challenger) { create(:user) }
  let(:opponent) { create(:user) }
  let!(:argument) { create(:hujah, parent: hujah, user: opponent, vote: 3) }

  def challenge!
    sign_in challenger
    post "/hoojah/#{hujah.slug}/debates", params: {argument_id: argument.id, challenger_stance: 1}
    Debate.last
  end

  it "creates a pending debate from an argument" do
    expect { challenge! }.to change(Debate, :count).by(1)
    expect(Debate.last.opponent).to eq(opponent)
  end

  it "rejects a forged argument from another hoojah (422)" do
    other = create(:hujah)
    foreign = create(:hujah, parent: other, user: opponent, vote: 3)
    sign_in challenger
    post "/hoojah/#{hujah.slug}/debates", params: {argument_id: foreign.id, challenger_stance: 1}
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "a non-current-turn participant cannot post a turn (403) — the C1 test" do
    d = challenge!
    d.accept!(by: opponent) # challenger's turn now
    sign_in opponent
    post "/debates/#{d.slug}/turns", params: {body: "not my turn"}
    expect(response).to have_http_status(:forbidden)
    expect(d.turns.count).to eq(0)
  end

  it "the current-turn participant can post; the other then can" do
    d = challenge!
    d.accept!(by: opponent)
    sign_in challenger
    post "/debates/#{d.slug}/turns", params: {body: "c1"}, headers: {"Accept" => "text/vnd.turbo-stream.html"}
    expect(d.reload.turns.count).to eq(1)
  end

  it "active debate hidden from non-participant; concluded public" do
    d = challenge!
    d.accept!(by: opponent)
    sign_in create(:user)
    get "/debates/#{d.slug}"
    expect(response).to have_http_status(:forbidden)
    d.conclude!(by: challenger)
    get "/debates/#{d.slug}"
    expect(response).to have_http_status(:ok)
  end
end
