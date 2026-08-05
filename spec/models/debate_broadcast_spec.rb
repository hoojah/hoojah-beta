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

  describe "#post_turn" do
    it "appends the new turn to the debate transcript stream" do
      d = build_active_debate
      expect {
        perform_enqueued_jobs { d.post_turn(by: challenger, body: "opening argument") }
      }.to have_broadcasted_to(stream(d)).with { |html|
        expect(html).to include(dom_id(d, :transcript))
        expect(html).to include("opening argument")
      }
    end

    it "replaces the composer on each participant's user-signed stream" do
      d = build_active_debate
      expect {
        perform_enqueued_jobs { d.post_turn(by: challenger, body: "opening argument") }
      }.to have_broadcasted_to(stream(d, challenger)).with { |html|
        expect(html).to include(dom_id(d, :composer))
      }

      # Fresh participants — a second live debate for the same trio hits the
      # no_dup_live_debate constraint.
      c2 = create(:user)
      o2 = create(:user)
      d2 = c2.challenged_debates.create!(hujah: create(:hujah), opponent: o2,
        challenger_stance: 1, opponent_stance: 3)
      d2.accept!(by: o2)
      expect {
        perform_enqueued_jobs { d2.post_turn(by: c2, body: "opening argument") }
      }.to have_broadcasted_to(stream(d2, o2)).with { |html|
        expect(html).to include(dom_id(d2, :composer))
      }
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
