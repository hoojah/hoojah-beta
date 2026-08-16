require "rails_helper"

RSpec.describe "Debate extend", type: :request do
  def dom_id(*args) = ActionView::RecordIdentifier.dom_id(*args)

  let(:challenger) { create(:user) }
  let(:opponent) { create(:user) }

  # The extension window is the closing-round BOUNDARY: (rounds_limit - 1) * 2
  # turns are on the record and the closing round holds none. At the default
  # rounds_limit of 4 that is exactly 6 turns. The challenger always opens, so
  # even indices are theirs.
  def debate_with_turns(count, status: :active)
    create(:debate, challenger: challenger, opponent: opponent, status: status).tap do |d|
      count.times do |i|
        create(:debate_turn, debate: d, position: i + 1, user: (i.even? ? challenger : opponent))
      end
    end
  end

  it "lets a participant at the boundary extend (turbo_stream replaces status AND actions)" do
    d = debate_with_turns(6)
    sign_in challenger

    post "/debates/#{d.slug}/extend", headers: {"Accept" => "text/vnd.turbo-stream.html"}

    expect(response).to have_http_status(:ok)
    # Both regions synchronously — the async broadcast renders in a job that never
    # runs in dev, so the actor's own affordances must update from this response.
    expect(response.body).to include(dom_id(d, :status))
    expect(response.body).to include(dom_id(d, :actions))
    expect(d.reload.rounds_limit).to eq(5)
  end

  it "lets the OTHER participant extend too (the window is unilateral, not owner-only)" do
    d = debate_with_turns(6)
    sign_in opponent

    post "/debates/#{d.slug}/extend", headers: {"Accept" => "text/vnd.turbo-stream.html"}

    expect(response).to have_http_status(:ok)
    expect(d.reload.rounds_limit).to eq(5)
  end

  it "redirects an HTML extend back to the debate with 303 (Turbo needs See Other on a POST)" do
    d = debate_with_turns(6)
    sign_in challenger

    post "/debates/#{d.slug}/extend"

    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to(debate_path(d.slug))
    expect(d.reload.rounds_limit).to eq(5)
  end

  it "forbids a non-participant (403)" do
    d = debate_with_turns(6)
    sign_in create(:user)

    post "/debates/#{d.slug}/extend"

    expect(response).to have_http_status(:forbidden)
    expect(d.reload.rounds_limit).to eq(4)
  end

  # Authorization and applicability are DIFFERENT answers: a participant on an
  # active debate is allowed to ask, so a mistimed ask is 422, never 403.
  it "rejects a participant mid-closing-round with 422, not 403" do
    d = debate_with_turns(7) # the closing turn is already down

    sign_in challenger
    post "/debates/#{d.slug}/extend"

    expect(response).to have_http_status(:unprocessable_content)
    expect(d.reload.rounds_limit).to eq(4)
  end

  it "rejects a participant before the closing round has been reached (422)" do
    d = debate_with_turns(4)

    sign_in challenger
    post "/debates/#{d.slug}/extend"

    expect(response).to have_http_status(:unprocessable_content)
    expect(d.reload.rounds_limit).to eq(4)
  end

  it "rejects a participant sitting at the MAX_ROUNDS ceiling (422)" do
    d = debate_with_turns(18) # (10 - 1) * 2 — the boundary for rounds_limit 10
    d.update!(rounds_limit: Debate::MAX_ROUNDS)

    sign_in challenger
    post "/debates/#{d.slug}/extend"

    expect(response).to have_http_status(:unprocessable_content)
    expect(d.reload.rounds_limit).to eq(Debate::MAX_ROUNDS)
  end

  it "rejects a participant on a non-active debate (403 — the policy gate)" do
    d = debate_with_turns(6, status: :concluded)

    sign_in challenger
    post "/debates/#{d.slug}/extend"

    expect(response).to have_http_status(:forbidden)
    expect(d.reload.rounds_limit).to eq(4)
  end

  # update! revalidates the whole row, not just rounds_limit — a row that went
  # invalid by some other route must 422, never 500.
  it "422s instead of 500ing when the row itself is invalid" do
    d = debate_with_turns(6)
    d.update_column(:opponent_stance, d.challenger_stance) # bypasses validation

    sign_in challenger
    post "/debates/#{d.slug}/extend"

    expect(response).to have_http_status(:unprocessable_content)
    expect(d.reload.rounds_limit).to eq(4)
  end

  it "redirects an unauthenticated visitor to login" do
    d = debate_with_turns(6)

    post "/debates/#{d.slug}/extend"

    expect(response).to redirect_to(new_user_session_path)
    expect(d.reload.rounds_limit).to eq(4)
  end

  it "404s an unknown slug without tripping verify_authorized" do
    sign_in challenger

    expect { post "/debates/no-such-debate/extend" }
      .to raise_error(ActiveRecord::RecordNotFound)
  end
end
