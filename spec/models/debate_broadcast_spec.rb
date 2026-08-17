require "rails_helper"

# Slice 8 Task 3.2 — real-time broadcasts + viewer-scoped composer/actions.
#
# Broadcasts are the `_later` variants (enqueued via ActiveJob's :test adapter),
# so every action under test is wrapped in `perform_enqueued_jobs { ... }` to run
# the enqueued Turbo broadcast job synchronously. The turbo *unsigned* stream name
# is `record.to_gid_param` (composite streamables joined by ":"), which is exactly
# what rspec's `have_broadcasted_to(<String>)` treats as the raw stream name.
RSpec.describe "Debate broadcasts", type: :model do
  include ActiveJob::TestHelper

  let(:hujah) { create(:hujah) }
  let(:challenger) { create(:user) }
  let(:opponent) { create(:user) }

  def build_pending_debate
    challenger.challenged_debates.create!(hujah: hujah, opponent: opponent,
      challenger_stance: 1, opponent_stance: 3)
  end

  def build_active_debate
    d = build_pending_debate
    d.accept!(by: opponent)
    d
  end

  # Turbo's unsigned stream name (what ActionCable actually broadcasts on).
  def stream(*streamables) = streamables.map(&:to_gid_param).join(":")

  def dom_id(...) = ActionView::RecordIdentifier.dom_id(...)

  # Every payload that landed on `stream_name` while the block ran, decoded back to
  # the Turbo-Stream HTML.
  #
  # Slice 9 made post_turn put TWO payloads on the debate stream (the transcript
  # append and the status repaint) and TWO on each participant's stream (composer +
  # actions). `have_broadcasted_to(...).with { }` runs its block against EVERY payload
  # on the stream, so it can no longer express "this region was broadcast" — it now
  # asserts "every region broadcast was this one", and the sibling payload fails it.
  # Select the region under test instead, and assert its COUNT so a double-broadcast
  # is a failure rather than something a `include` would happily swallow.
  def broadcasts_on(stream_name)
    ActionCable.server.pubsub.clear
    perform_enqueued_jobs { yield }
    ActionCable.server.pubsub.broadcasts(stream_name).map { |m| ActiveSupport::JSON.decode(m) }
  end

  # The Turbo-Stream `target` attribute, not any id in the template body.
  def targeting(payloads, target) = payloads.grep(/target="#{Regexp.escape(target)}"/)

  describe "#post_turn" do
    it "appends the new turn to the debate transcript stream" do
      d = build_active_debate
      payloads = broadcasts_on(stream(d)) { d.post_turn(by: challenger, body: "opening argument") }

      appended = targeting(payloads, dom_id(d, :transcript))
      expect(appended.size).to eq(1)
      expect(appended.first).to include("opening argument")
    end

    it "replaces the composer on each participant's user-signed stream" do
      d = build_active_debate
      payloads = broadcasts_on(stream(d, challenger)) { d.post_turn(by: challenger, body: "opening argument") }
      expect(targeting(payloads, dom_id(d, :composer)).size).to eq(1)

      # Fresh participants — a second live debate for the same trio hits the
      # no_dup_live_debate constraint.
      c2 = create(:user)
      o2 = create(:user)
      d2 = c2.challenged_debates.create!(hujah: create(:hujah), opponent: o2,
        challenger_stance: 1, opponent_stance: 3)
      d2.accept!(by: o2)
      payloads2 = broadcasts_on(stream(d2, o2)) { d2.post_turn(by: c2, body: "opening argument") }
      expect(targeting(payloads2, dom_id(d2, :composer)).size).to eq(1)
    end

    # Slice 9. Every transition of "Round n of N", and every false→true flip of
    # extendable_by?, IS a post_turn — so without these the counter froze at first
    # paint and the Extend button never appeared for anyone but the mover.
    it "repaints the round counter on the debate stream for a non-capping turn" do
      d = build_active_debate
      payloads = broadcasts_on(stream(d)) { d.post_turn(by: challenger, body: "t1") }

      status = targeting(payloads, dom_id(d, :status))
      expect(status.size).to eq(1)
      expect(status.first).to include("Round 1 of 4")
    end

    it "repaints each participant's own actions region for a non-capping turn" do
      d = build_active_debate
      [challenger, opponent].each do |participant|
        d2 = Debate.find(d.id) # fresh per pass; broadcasts_on clears the pubsub
        payloads = broadcasts_on(stream(d2, participant)) { d2.post_turn(by: d2.current_turn_user, body: "t") }
        expect(targeting(payloads, dom_id(d2, :actions)).size).to eq(1)
      end
    end

    it "does not repeat the state change on the capping turn — conclude! already sent it" do
      d = build_active_debate
      7.times { |i| d.post_turn(by: i.even? ? challenger : opponent, body: "t#{i + 1}") }

      # The 8th turn hits final_position, so post_turn routes through conclude!, which
      # fires broadcast_state_change itself. Firing it again would enqueue the status
      # replace and BOTH actions replaces a second time for this one turn.
      payloads = broadcasts_on(stream(d)) { d.post_turn(by: opponent, body: "t8") }

      status = targeting(payloads, dom_id(d, :status))
      expect(status.size).to eq(1)
      expect(status.first).to include("Concluded")
      expect(status.first).not_to include("Round") # no counter on a finished debate
    end

    # Slice 9 Task 4.5. `debates/_debate_turn` renders the mover's avatar, and until
    # that call site moved onto `ui/_avatar` it was a bare `image_tag user.photo` —
    # which RAISES "Nil location provided" when `photo` is blank, a state any user can
    # reach by clearing it on their profile (`:photo` is permitted in `user_params`).
    #
    # This is the dangerous half of that defect, and the reason it gets an example here
    # as well as in spec/requests/photoless_user_spec.rb. On the request path a raise is
    # a 500 somebody sees. HERE the render happens inside the job `_later_to` enqueued,
    # so the exception never reaches a browser: the poster's own synchronous response
    # still lands, and the OTHER participant's transcript simply stops receiving turns,
    # with nothing on either screen to say why. `perform_enqueued_jobs` is what puts the
    # render in scope — without it the payload is never built and this example passes
    # against the broken partial.
    it "broadcasts a turn posted by a participant who has no photo" do
      d = build_active_debate
      challenger.update_columns(photo: nil, full_name: "Siti Nurhaliza")

      payloads = broadcasts_on(stream(d)) { d.post_turn(by: challenger, body: "photoless opening") }

      appended = targeting(payloads, dom_id(d, :transcript))
      expect(appended.size).to eq(1)
      expect(appended.first).to include("photoless opening")
      # `ui/_avatar`'s fallback: initials on primary, labelled with the full name on
      # BOTH branches. Asserting the label rather than the letters proves the fallback
      # actually rendered, not merely that the byline printed the name.
      expect(appended.first).to include('aria-label="Siti Nurhaliza"')
    end

    it "does not broadcast when it is not the poster's turn" do
      d = build_active_debate # challenger moves first
      expect {
        perform_enqueued_jobs { d.post_turn(by: opponent, body: "out of turn") }
      }.not_to have_broadcasted_to(stream(d))
    end
  end

  describe "#accept!" do
    it "broadcasts the (viewer-agnostic) status to the debate stream" do
      d = build_pending_debate
      expect {
        perform_enqueued_jobs { d.accept!(by: opponent) }
      }.to have_broadcasted_to(stream(d)).with { |html|
        expect(html).to include(dom_id(d, :status))
        expect(html).to include("Active")
      }
    end

    it "broadcasts per-participant actions to each user-signed stream" do
      d = build_pending_debate
      expect {
        perform_enqueued_jobs { d.accept!(by: opponent) }
      }.to have_broadcasted_to(stream(d, challenger)).with { |html|
        expect(html).to include(dom_id(d, :actions))
      }
    end
  end

  describe "#conclude!" do
    it "broadcasts status to the debate stream and actions per participant" do
      d = build_active_debate
      expect {
        perform_enqueued_jobs { d.conclude!(by: challenger) }
      }.to have_broadcasted_to(stream(d)).with { |html|
        expect(html).to include(dom_id(d, :status))
        expect(html).to include("Concluded")
      }
    end

    it "broadcasts the opponent's actions region on conclude" do
      d = build_active_debate
      expect {
        perform_enqueued_jobs { d.conclude!(by: challenger) }
      }.to have_broadcasted_to(stream(d, opponent)).with { |html|
        expect(html).to include(dom_id(d, :actions))
      }
    end
  end

  describe "viewer-scoped composer partial" do
    it "renders the turn form for the current-turn viewer" do
      d = build_active_debate # no turns yet → challenger's turn
      html = ApplicationController.render(partial: "debates/turn_composer",
        locals: {debate: d, viewer: challenger})
      expect(html).to include("Post turn")
    end

    it "renders a waiting note (no form) for the other viewer" do
      d = build_active_debate
      html = ApplicationController.render(partial: "debates/turn_composer",
        locals: {debate: d, viewer: opponent})
      expect(html).to include("Waiting for")
      expect(html).not_to include("Post turn")
    end
  end

  describe "viewer-scoped actions partial" do
    it "shows Conclude for a participant on an active debate" do
      d = build_active_debate
      html = ApplicationController.render(partial: "debates/debate_actions",
        locals: {debate: d, viewer: challenger})
      expect(html).to include("Conclude")
    end

    it "shows no actions for a non-participant viewer" do
      d = build_active_debate
      stranger = create(:user)
      html = ApplicationController.render(partial: "debates/debate_actions",
        locals: {debate: d, viewer: stranger})
      expect(html).not_to include("Conclude")
    end
  end
end
