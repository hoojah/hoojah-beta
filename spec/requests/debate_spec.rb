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

  describe "views (Phase 4)" do
    def dom_id(*args) = ActionView::RecordIdentifier.dom_id(*args)

    it "hoojah show renders the Debates lens container and a visible debate card" do
      d = challenge!
      d.accept!(by: opponent)
      d.conclude!(by: challenger) # concluded → visible to anyone via the lens Scope
      get "/hoojah/#{hujah.slug}"
      expect(response.body).to include("id=\"#{dom_id(hujah, :debates)}\"")
      expect(response.body).to include("id=\"#{dom_id(d, :card)}\"")
    end

    it "argument card shows a Challenge action + dialog for a signed-in non-author" do
      sign_in challenger # challenger is not the argument's author (opponent is)
      get "/hoojah/#{hujah.slug}"
      expect(response.body).to include("Challenge to debate")
      expect(response.body).to include("id=\"#{dom_id(argument, :challenge_dialog)}\"")
    end

    it "argument card hides the Challenge action from its own author" do
      sign_in opponent # opponent authored the argument
      get "/hoojah/#{hujah.slug}"
      expect(response.body).not_to include("id=\"#{dom_id(argument, :challenge_dialog)}\"")
    end

    it "argument card hides the Challenge action from anonymous visitors" do
      get "/hoojah/#{hujah.slug}"
      expect(response.body).not_to include("Challenge to debate")
    end

    it "debate show renders the pinned transcript + composer for the current-turn user" do
      d = challenge!
      d.accept!(by: opponent) # challenger's turn
      sign_in challenger
      get "/debates/#{d.slug}"
      expect(response.body).to include("id=\"#{dom_id(d, :transcript)}\"")
      expect(response.body).to include("id=\"#{dom_id(d, :composer)}\"")
      expect(response.body).to include("Post turn") # composer form shown to the mover
    end
  end

  # The accept/decline/conclude affordances live in `_debate_actions` (:actions),
  # split out of `_debate_status` (:status). The synchronous turbo_stream RESPONSE
  # must still replace the actor's OWN buttons in place — otherwise, with no job
  # worker running (dev) the buttons stay stale until reload. These lock that in.
  describe "synchronous actions replace (Task 3.2)" do
    it "accept replaces both :status and :actions, and clears the opponent's Accept/Decline" do
      d = challenge!
      sign_in opponent
      patch "/debates/#{d.slug}/accept", headers: {"Accept" => "text/vnd.turbo-stream.html"}
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("action=\"replace\" target=\"#{dom_id(d, :status)}\"")
      expect(response.body).to include("action=\"replace\" target=\"#{dom_id(d, :actions)}\"")
      # Now active → the actor (a participant) sees Conclude, no longer Accept/Decline.
      expect(response.body).to include("Conclude")
      expect(response.body).not_to include(">Accept<")
      expect(response.body).not_to include(">Decline<")
    end

    it "decline replaces :actions and leaves no accept/decline/conclude affordance" do
      d = challenge!
      sign_in opponent
      patch "/debates/#{d.slug}/decline", headers: {"Accept" => "text/vnd.turbo-stream.html"}
      expect(response.body).to include("action=\"replace\" target=\"#{dom_id(d, :actions)}\"")
      expect(response.body).not_to include(">Accept<")
      expect(response.body).not_to include(">Decline<")
      expect(response.body).not_to include(">Conclude<")
    end

    it "conclude replaces :actions and clears the actor's Conclude button" do
      d = challenge!
      d.accept!(by: opponent) # active, challenger's turn
      sign_in challenger
      patch "/debates/#{d.slug}/conclude", headers: {"Accept" => "text/vnd.turbo-stream.html"}
      expect(response.body).to include("action=\"replace\" target=\"#{dom_id(d, :actions)}\"")
      expect(response.body).not_to include(">Conclude<")
    end
  end
end
