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

  # 2026 (Task 3.5): the spectator view reads a LIVE transcript, so a visible
  # non-participant may now watch an active debate too, not only a concluded one —
  # DebatePolicy#show? extends the exact same visibility clause (both participants +
  # the claim) from concluded to active, so this introduces no new leak surface (see
  # that policy's own comment). A PENDING debate is still participants-only: it has no
  # spectator layout (`_debate_pending` is Phase 3.3's accept/decline screen).
  it "an active debate is visible to a spectator when both participants and the claim are public; still true once concluded" do
    d = challenge!
    d.accept!(by: opponent)
    sign_in create(:user)
    get "/debates/#{d.slug}"
    expect(response).to have_http_status(:ok)
    d.conclude!(by: challenger)
    get "/debates/#{d.slug}"
    expect(response).to have_http_status(:ok)
  end

  it "hides an active debate from a spectator when a participant is private" do
    d = challenge!
    d.accept!(by: opponent)
    challenger.update!(private: true)
    sign_in create(:user)
    get "/debates/#{d.slug}"
    expect(response).to have_http_status(:forbidden)
  end

  it "still hides a pending debate from a non-participant" do
    d = challenge!
    sign_in create(:user)
    get "/debates/#{d.slug}"
    expect(response).to have_http_status(:forbidden)
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

    it "argument card shows a Challenge link to the create page for a signed-in non-author (Phase 3.2)" do
      sign_in challenger # challenger is not the argument's author (opponent is)
      get "/hoojah/#{hujah.slug}"
      expect(response.body).to include("Challenge to debate")
      expect(response.body).to include(new_hujah_debate_path(hujah, argument_id: argument.id))
    end

    it "argument card hides the Challenge link from its own author" do
      sign_in opponent # opponent authored the argument
      get "/hoojah/#{hujah.slug}"
      expect(response.body).not_to include(new_hujah_debate_path(hujah, argument_id: argument.id))
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
  # Phase 3.2 (2026 redesign): the create page replaces the stance-only dialog.
  # `GET .../debates/new` renders the picker; `POST` gains :rounds_limit and
  # :opening_argument on the SAME flat permit — argument_id/challenger_stance
  # behaviour (the 422 paths, the instance-authorize, RecordNotUnique) is
  # unchanged and covered above.
  describe "create page (Phase 3.2)" do
    it "renders the opponent card, the motion, a 2/3/5 rounds picker, and the opening-argument field" do
      sign_in challenger
      get "/hoojah/#{hujah.slug}/debates/new", params: {argument_id: argument.id}
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("@#{argument.user.username}")
      expect(response.body).to include(hujah.body)
      expect(response.body).to include(argument.body)
      # The rounds picker offers 2/3/5, defaulting to 3 (model default is 4 —
      # the picker's default must not silently ride on that).
      %w[2 3 5].each do |n|
        expect(response.body).to include(%(value="#{n}"))
      end
      expect(response.body).to match(/name="rounds_limit" id="rounds_limit_3" value="3"[^>]*checked/)
      expect(response.body).to include(%(name="opening_argument"))
      # Static, informational only (deferred) — no input that persists either.
      expect(response.body).to include("Spectators decide")
      expect(response.body).to include("Turn timer")
    end

    it "POSTs rounds_limit + opening_argument and creates a pending debate with them" do
      sign_in challenger
      post "/hoojah/#{hujah.slug}/debates",
        params: {argument_id: argument.id, challenger_stance: 1, rounds_limit: 5, opening_argument: "Free transit shifts costs unfairly."}
      d = Debate.last
      expect(d.rounds_limit).to eq(5)
      expect(d.opening_argument).to eq("Free transit shifts costs unfairly.")
      expect(d).to be_pending
    end

    # Debate::MAX_ROUNDS is 10 and the model validates 2..10 inclusive — the task
    # brief's "1 or 6" example is inconsistent with that (6 is a legal, if
    # un-offered, value), so the boundary cases exercised here are 1 (below the
    # floor) and 11 (above Debate::MAX_ROUNDS), matching the model's own comment
    # ("validated 2..10 — so 1 is INVALID").
    it "rejects a server-side-invalid rounds_limit even though the UI never offers one (422)" do
      sign_in challenger
      post "/hoojah/#{hujah.slug}/debates", params: {argument_id: argument.id, challenger_stance: 1, rounds_limit: 1}
      expect(response).to have_http_status(:unprocessable_content)

      post "/hoojah/#{hujah.slug}/debates", params: {argument_id: argument.id, challenger_stance: 1, rounds_limit: 11}
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "still 422s a forged argument_id not belonging to the URL hoojah, from the new page's own params" do
      other = create(:hujah)
      foreign = create(:hujah, parent: other, user: opponent, vote: 3)
      sign_in challenger
      post "/hoojah/#{hujah.slug}/debates",
        params: {argument_id: foreign.id, challenger_stance: 1, rounds_limit: 5, opening_argument: "x"}
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "GET new 422s on a forged argument_id too (skip_authorization before the guarded return)" do
      other = create(:hujah)
      foreign = create(:hujah, parent: other, user: opponent, vote: 3)
      sign_in challenger
      get "/hoojah/#{hujah.slug}/debates/new", params: {argument_id: foreign.id}
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "the argument's own author cannot challenge themselves (existing rule, 422)" do
      sign_in opponent # opponent authored `argument`
      post "/hoojah/#{hujah.slug}/debates",
        params: {argument_id: argument.id, challenger_stance: 1, rounds_limit: 3, opening_argument: "x"}
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "authorizes the built @debate INSTANCE, not the class, on GET new" do
      sign_in challenger
      # DebatePolicy#create? (new? defaults to it) checks record.hujah.allow_debates? —
      # an instance-only predicate. Flipping the claim's toggle off and getting a 403
      # proves the policy ran against the CONCRETE built debate, not `DebatePolicy`
      # applied to the class/nil.
      hujah.update!(allow_debates: false)
      get "/hoojah/#{hujah.slug}/debates/new", params: {argument_id: argument.id}
      expect(response).to have_http_status(:forbidden)
    end
  end

  # Phase 3.3 (2026 redesign): a PENDING debate gets a dedicated accept/decline screen
  # (`debates/_debate_pending`) instead of the plain inline status row. It composes the
  # EXISTING `_debate_status` / `_debate_actions` partials for their pinned dom_ids —
  # this only asserts the new content around them, not a change to accept!/decline!
  # or their Turbo Stream responses (that is `describe "synchronous actions replace"`).
  describe "pending screen (Phase 3.3)" do
    def dom_id(*args) = ActionView::RecordIdentifier.dom_id(*args)

    it "renders the opponent's accept/decline screen: Pending pill, avatar trio, headline, motion, rules card, no timer row, buttons at the pinned :actions dom_id" do
      d = challenge!
      sign_in opponent
      get "/debates/#{d.slug}"

      # The state label stays at its pinned dom_id (Turbo/Cable target — unchanged).
      expect(response.body).to include("id=\"#{dom_id(d, :status)}\"")
      expect(response.body).to match(%r{<span[^>]*>Pending</span>})

      # Avatar trio: both participants render (factory users carry no photo, so
      # `ui/_avatar` falls back to the initials tile — `aria-label` names each one).
      expect(response.body).to include(%(aria-label="#{challenger.full_name}"))
      expect(response.body).to include(%(aria-label="#{opponent.full_name}"))

      # Headline names the challenger.
      expect(response.body).to include("@#{challenger.username}")
      expect(response.body).to include("challenged")

      # The motion (claim) blockquote.
      expect(response.body).to include(hujah.body)

      # Rules card: the real rounds count + a static spectators-decide row.
      expect(response.body).to include("#{d.rounds_limit} rounds")
      expect(response.body).to include("Spectators")
      expect(response.body).to include("decide the winner")

      # No timer row — deferred, there is no per-turn time-limit column to show.
      expect(response.body).not_to include("per turn")
      expect(response.body).not_to include("minutes")

      # Accept/Decline via the EXISTING `_debate_actions` partial, at the pinned
      # :actions dom_id — still posting to the real accept/decline routes.
      expect(response.body).to include("id=\"#{dom_id(d, :actions)}\"")
      expect(response.body).to include(">Accept<")
      expect(response.body).to include(">Decline<")
      expect(response.body).to include(accept_debate_path(d.slug))
      expect(response.body).to include(decline_debate_path(d.slug))
    end

    # Slice B (navbar-hovercard-follows): the pending screen's participant handles are now
    # real profile links carrying the hovercard controller. Assert the challenger handle is
    # an <a href="/u/<username>"> with the hovercard trigger, stance colour preserved.
    it "links the participant handles to their profiles with a hovercard trigger" do
      d = challenge!
      sign_in opponent
      get "/debates/#{d.slug}"

      # Two links point at the challenger — the avatar wrapper and the stance-coloured
      # handle. Assert the handle one specifically (its @username text + text-agree class).
      links = response.parsed_body.css(%(a[href="/u/#{challenger.username}"][data-controller="hovercard"]))
      expect(links).to be_present
      handle = links.find { |a| a["class"].to_s.include?("text-agree") }
      expect(handle).to be_present
      expect(handle.text).to include("@#{challenger.username}")
    end

    it "does not show Accept/Decline to a non-opponent participant (the challenger, existing rule)" do
      d = challenge!
      sign_in challenger
      get "/debates/#{d.slug}"

      expect(response.body).not_to include(">Accept<")
      expect(response.body).not_to include(">Decline<")
      expect(response.body).to include("Waiting for @#{opponent.username}")
      # Still their own pending screen — the motion and rules card still render.
      expect(response.body).to include(hujah.body)
      expect(response.body).to include("#{d.rounds_limit} rounds")
    end
  end

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

  # Moderation (2026): the transcript header quotes the claim body per-record via
  # visible_to?. A concluded (publicly readable) debate whose claim is then removed
  # must not leak that body through the header — not even to a participant (the claim
  # author IS a participant, and removed content is hidden from its author too).
  describe "transcript quote gate (Moderation)" do
    it "hides a removed claim's body from a member participant but shows it to staff" do
      d = challenge!
      d.accept!(by: opponent)
      d.conclude!(by: challenger)
      hujah.update!(body: "DEBATEMOTIONXYZ distinctive claim", moderation_status: :removed)

      sign_in challenger # a participant, but a plain member — must not read removed content
      get "/debates/#{d.slug}"
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("DEBATEMOTIONXYZ")
      expect(response.body).to include("a removed hoojah")

      sign_in create(:user, :moderator) # non-participant staff; both participants public
      get "/debates/#{d.slug}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("DEBATEMOTIONXYZ")
    end
  end

  # H-1: the pending-debate screen (`_debate_pending`) re-quotes the claim body with no
  # gate. A pending debate is participants-only (DebatePolicy#show?), but a participant
  # who is a plain member must still not read a REMOVED claim — removed content is
  # staff-only everywhere, including from the claim author who is a participant.
  describe "pending debate claim quote gate (Moderation, H-1)" do
    it "hides a removed claim's body from a member participant but shows it to a moderator participant" do
      mod = create(:user, :moderator)
      plain = create(:user)
      motion = create(:hujah, body: "PENDINGMOTIONXYZ distinctive claim")
      d = create(:debate, hujah: motion, challenger: mod, opponent: plain, status: :pending)
      motion.update!(moderation_status: :removed)

      sign_in plain # a participant, but a plain member — must not read removed content
      get "/debates/#{d.slug}"
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("PENDINGMOTIONXYZ")
      expect(response.body).to include("a removed hoojah")

      sign_in mod # a participant AND staff
      get "/debates/#{d.slug}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("PENDINGMOTIONXYZ")
    end
  end
end
