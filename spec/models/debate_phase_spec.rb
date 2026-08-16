require "rails_helper"
require Rails.root.join("db/migrate/20260814120000_add_rounds_limit_to_debates")

RSpec.describe "debate rounds and phases", type: :model do
  # `position` is stated literally even though the factory now derives the same
  # value: this file's entire subject is position-derived round math, so its
  # fixtures should not be reading the answer out of the thing under test. The
  # challenger always opens, so even indices are theirs.
  def debate_with_turns(status, count)
    create(:debate, status: status).tap do |debate|
      count.times do |i|
        create(:debate_turn, debate: debate, position: i + 1,
          user: (i.even? ? debate.challenger : debate.opponent))
      end
    end
  end

  # Every `SELECT ... FOR UPDATE` issued against `debates` while the block runs.
  def locking_statements
    seen = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      sql = payload[:sql].to_s
      seen << sql if sql.include?("FOR UPDATE") && sql.include?('"debates"')
    end
    yield
    seen
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  describe "rounds_limit" do
    it "defaults to 4 on a fresh debate" do
      expect(create(:debate).rounds_limit).to eq(4)
    end
  end

  # The migration has already run by the time these specs execute, so a fresh
  # record only ever demonstrates the column DEFAULT — never the backfill. To
  # exercise the backfill we replay the migration's own UPDATE (the exact
  # constant the migration executes, not a hand-copied paraphrase) against rows
  # created inside this example's transaction. Those rows carry the column
  # default, which is precisely the state of the table immediately after
  # add_column and before the backfill ran.
  #
  # (Settled, do not re-open: nothing here needs to prove `up` ran add_column
  # BEFORE the backfill. BACKFILL_SQL names `rounds_limit`, so the reverse order
  # would have raised PG::UndefinedColumn and aborted the migration — and
  # db/schema.rb carries the new column at the migration's version, which only
  # happens if `up` completed.)
  describe "AddRoundsLimitToDebates backfill" do
    def replay_backfill!
      ActiveRecord::Base.connection.execute(AddRoundsLimitToDebates::BACKFILL_SQL)
    end

    it "raises an active debate to current_round + 1" do
      debate = debate_with_turns(:active, 10)
      expect(debate.current_round).to eq(6) # (10 / 2) + 1

      replay_backfill!

      expect(debate.reload.rounds_limit).to eq(7)
    end

    it "leaves non-active debates at the default" do
      concluded = debate_with_turns(:concluded, 10)
      pending_debate = debate_with_turns(:pending, 10)

      replay_backfill!

      expect(concluded.reload.rounds_limit).to eq(4)
      expect(pending_debate.reload.rounds_limit).to eq(4)
    end

    it "floors short active debates at the product default of 4" do
      debates = (0..3).map { |count| debate_with_turns(:active, count) }

      replay_backfill!

      expect(debates.map { |d| d.reload.rounds_limit }).to all(eq(4))
    end

    # The whole point of the backfill: no active debate may be left at or past
    # the turn cap, or posting the next turn would immediately conclude a debate
    # that is mid-flight. Asserted against the cap itself (`turns.count <
    # rounds_limit * 2`, the exact invariant post_turn enforces) rather than the
    # one-step-removed `rounds_limit > current_round`. Covers odd turn counts,
    # where Postgres integer division must truncate exactly as Ruby's Integer#/
    # does.
    it "leaves every active debate strictly below the turn cap" do
      debates = (0..9).map { |count| debate_with_turns(:active, count) }

      replay_backfill!

      debates.each do |debate|
        debate.reload
        expect(debate.turns.count).to be < (debate.rounds_limit * 2)
      end
    end
  end

  describe "DebateTurn#round" do
    it "pairs positions into rounds — 1,2 => 1; 3,4 => 2; 5,6 => 3; 7,8 => 4" do
      debate = debate_with_turns(:active, 8)

      expect(debate.turns.order(:position).map { |t| [t.position, t.round] })
        .to eq([[1, 1], [2, 1], [3, 2], [4, 2], [5, 3], [6, 3], [7, 4], [8, 4]])
    end
  end

  describe "#phase_for" do
    it "labels rounds opening / counter / response / closing at rounds_limit 4" do
      debate = create(:debate)

      expect(debate.rounds_limit).to eq(4)
      expect((1..4).map { |r| debate.phase_for(r) }).to eq(%i[opening counter response closing])
    end

    it "pushes closing out to round 5 at rounds_limit 5, demoting round 4 to counter" do
      debate = create(:debate, rounds_limit: 5)

      expect((1..5).map { |r| debate.phase_for(r) }).to eq(%i[opening counter response counter closing])
    end

    it "exposes a human label for every phase via DebateTurn#phase_label" do
      debate = debate_with_turns(:active, 8)

      expect(debate.turns.order(:position).map(&:phase_label).uniq)
        .to eq(["Opening statement", "Counter-argument", "Response", "Closing statement"])
    end
  end

  describe "#current_phase" do
    it "tracks the round in flight on an active debate" do
      expect(debate_with_turns(:active, 0).current_phase).to eq(:opening)  # round 1
      expect(debate_with_turns(:active, 2).current_phase).to eq(:counter)  # round 2
      expect(debate_with_turns(:active, 4).current_phase).to eq(:response) # round 3
      expect(debate_with_turns(:active, 6).current_phase).to eq(:closing)  # round 4
    end

    # The trap this method exists to close: current_round on a full debate is 5,
    # one PAST rounds_limit, and phase_for(5) is :response. Views must never see
    # "Response" on a concluded transcript.
    it "is nil once the debate is over, rather than reporting a phantom round" do
      debate = debate_with_turns(:active, 7)
      debate.post_turn(by: debate.opponent, body: "closing")
      debate.reload

      expect(debate).to be_concluded
      expect(debate.current_round).to eq(5)
      expect(debate.phase_for(debate.current_round)).to eq(:response) # the trap
      expect(debate.current_phase).to be_nil # the clamp
    end

    it "is nil on a pending debate" do
      expect(create(:debate).current_phase).to be_nil
    end
  end

  describe "rounds_limit validation" do
    # Associations are passed explicitly: a bare `build(:debate)` leaves both
    # challenger_id and opponent_id nil, which trips the "must differ" validation
    # and would make every one of these examples pass for the wrong reason.
    def debate_with_limit(limit)
      build(:debate, challenger: create(:user), opponent: create(:user), rounds_limit: limit)
    end

    it "rejects a limit below 2, where no round could ever be :closing" do
      debate = debate_with_limit(1)

      expect(debate).not_to be_valid
      expect(debate.errors[:rounds_limit]).to be_present
    end

    it "rejects a limit above MAX_ROUNDS" do
      debate = debate_with_limit(Debate::MAX_ROUNDS + 1)

      expect(debate).not_to be_valid
      expect(debate.errors[:rounds_limit]).to be_present
    end

    it "accepts the whole supported range" do
      (2..Debate::MAX_ROUNDS).each do |limit|
        expect(debate_with_limit(limit)).to be_valid
      end
    end
  end

  describe "the turn cap" do
    it "concludes the debate when the final turn is posted" do
      debate = debate_with_turns(:active, 7)

      expect(debate.post_turn(by: debate.opponent, body: "closing")).to be(true)

      expect(debate.reload).to be_concluded
      expect(debate.turns.count).to eq(8)
    end

    it "creates exactly one debate_your_turn notification for each of turns 1..7" do
      debate = create(:debate, status: :active)
      movers = [debate.challenger, debate.opponent]

      7.times do |i|
        expect { debate.post_turn(by: movers[i % 2], body: "turn #{i + 1}") }
          .to change { Notification.where(category: "debate_your_turn").count }.by(1)
      end

      expect(debate.reload).to be_active
    end

    it "creates NO debate_your_turn notification for the capping turn" do
      debate = debate_with_turns(:active, 7)

      expect { debate.post_turn(by: debate.opponent, body: "closing") }
        .not_to change { Notification.where(category: "debate_your_turn").count }
    end

    it "concludes via the system path — notifies BOTH participants and awards first_debate" do
      debate = debate_with_turns(:active, 7)

      expect { debate.post_turn(by: debate.opponent, body: "closing") }
        .to change { Notification.where(category: "debate_concluded").count }.by(2)

      expect(Notification.where(user: debate.challenger, category: "debate_concluded").count).to eq(1)
      expect(Notification.where(user: debate.opponent, category: "debate_concluded").count).to eq(1)
      expect(UserBadge.where(user: [debate.challenger, debate.opponent], badge_key: "first_debate").count).to eq(2)
    end

    it "refuses a turn once the debate has been capped and concluded" do
      debate = debate_with_turns(:active, 7)
      debate.post_turn(by: debate.opponent, body: "closing")

      expect(debate.post_turn(by: debate.challenger, body: "one more")).to be(false)
      expect(debate.turns.count).to eq(8)
    end

    describe "broadcast ordering" do
      include ActiveJob::TestHelper

      def stream(*streamables) = streamables.map(&:to_gid_param).join(":")

      # PINS the ordering: conclude! is enqueued BEFORE the composer broadcast.
      # Every *_later_to renders inside a job, from a GlobalID-reloaded record, at
      # EXECUTION time — not from the state at enqueue time. Move conclude! back
      # below the broadcasts and the composer job renders while the debate is
      # still `active`, painting the turn form for the opponent; conclude!'s
      # broadcast_state_change only replaces :status and :actions, so nothing
      # would ever correct it. The whole suite stays green without this example.
      it "leaves BOTH participants' composers reading as concluded, never the turn form" do
        debate = debate_with_turns(:active, 7)

        perform_enqueued_jobs { debate.post_turn(by: debate.opponent, body: "closing") }

        [debate.challenger, debate.opponent].each do |participant|
          html = ActionCable.server.pubsub.broadcasts(stream(debate, participant)).join
          expect(html).to include(ActionView::RecordIdentifier.dom_id(debate, :composer))
          expect(html).to include("This debate has concluded")
          expect(html).not_to include("Post turn")
        end
      end
    end
  end

  describe "#extend_rounds!" do
    # The extension window is the closing-round BOUNDARY: round rounds_limit - 1
    # is complete (6 turns at rounds_limit 4) and the closing round holds no turn.
    it "refuses a non-participant" do
      debate = debate_with_turns(:active, 6)

      expect(debate.extend_rounds!(by: create(:user))).to be(false)
      expect(debate.reload.rounds_limit).to eq(4)
    end

    it "refuses a non-active debate" do
      %i[pending concluded declined].each do |status|
        debate = debate_with_turns(status, 6)

        expect(debate.extend_rounds!(by: debate.challenger)).to be(false)
        expect(debate.reload.rounds_limit).to eq(4)
      end
    end

    it "refuses before the closing round has been reached" do
      (0..5).each do |count|
        debate = debate_with_turns(:active, count)

        expect(debate.extend_rounds!(by: debate.challenger)).to be(false)
        expect(debate.reload.rounds_limit).to eq(4)
      end
    end

    it "refuses at the MAX_ROUNDS ceiling even when sitting on the boundary" do
      debate = debate_with_turns(:active, 18) # (10 - 1) * 2 — the boundary for rounds_limit 10
      debate.update!(rounds_limit: Debate::MAX_ROUNDS)

      expect(debate.extendable_by?(debate.challenger)).to be(false)
      expect(debate.extend_rounds!(by: debate.challenger)).to be(false)
      expect(debate.reload.rounds_limit).to eq(Debate::MAX_ROUNDS)
    end

    # extendable_by? collapses every refusal into one `false`. A view needs to
    # tell "at the ceiling" (say "maximum rounds reached") from "wrong moment"
    # (stay silent), so the ceiling is exposed on its own.
    it "reports the ceiling separately from the extension window" do
      at_ceiling = debate_with_turns(:active, 18)
      at_ceiling.update!(rounds_limit: Debate::MAX_ROUNDS)
      wrong_moment = debate_with_turns(:active, 3)

      expect(at_ceiling.at_round_ceiling?).to be(true)
      expect(wrong_moment.at_round_ceiling?).to be(false)
      expect([at_ceiling, wrong_moment].map { |d| d.extendable_by?(d.challenger) }).to eq([false, false])
    end

    # The guard's whole purpose, asserted on the SUCCESS path — the refusal case
    # below only shows the guard fires, not that a label survives an extension
    # that actually happens. Walks to the ceiling, extending at every boundary.
    it "never changes an already-posted turn's label across a successful extend" do
      debate = debate_with_turns(:active, 6)
      movers = [debate.challenger, debate.opponent]
      labels = ->(d) { DebateTurn.where(debate: d).order(:position).map { |t| [t.position, t.phase_label] } }

      while debate.reload.rounds_limit < Debate::MAX_ROUNDS
        before = labels.call(debate)

        expect(debate.extend_rounds!(by: debate.challenger)).to be(true)

        expect(labels.call(debate)).to eq(before)

        # Play out the round the extension opened, re-reaching the boundary.
        movers.each { |mover| debate.post_turn(by: mover, body: "turn") }
      end

      expect(debate.reload.rounds_limit).to eq(Debate::MAX_ROUNDS)
      expect(debate.turns.count).to eq(18)
    end

    # A concurrent post_turn committing position 7 while an extend reads a count
    # of 6 would bump the limit and flip that turn :closing -> :counter. Both
    # methods take the SAME debates-row FOR UPDATE, so Postgres serialises them
    # and the loser re-reads a count of 7. Asserted as an identical lock
    # statement rather than by racing two connections.
    it "serialises against post_turn on the same debates-row lock" do
      debate = debate_with_turns(:active, 6)

      extend_locks = locking_statements { debate.extend_rounds!(by: debate.challenger) }
      post_locks = locking_statements { debate.post_turn(by: debate.challenger, body: "t7") }

      expect(extend_locks.size).to eq(1)
      expect(post_locks.size).to eq(1)
      expect(extend_locks).to eq(post_locks) # same table, same row, same lock mode
    end

    # The reason the guard is the boundary and not merely "before the cap":
    # phase is derived at render time, so extending once a closing turn EXISTS
    # would silently relabel it from "Closing statement" to "Counter-argument"
    # in every viewer's transcript.
    it "refuses once a turn already sits in the closing round, leaving that turn :closing" do
      debate = debate_with_turns(:active, 7)
      closing_turn = debate.turns.order(:position).last
      expect(closing_turn.phase).to eq(:closing)

      expect(debate.extend_rounds!(by: debate.challenger)).to be(false)

      expect(debate.reload.rounds_limit).to eq(4)
      expect(DebateTurn.find(closing_turn.id).phase).to eq(:closing)
    end

    it "bumps rounds_limit by one and moves the cap with it" do
      debate = debate_with_turns(:active, 6)

      expect(debate.extend_rounds!(by: debate.opponent)).to be(true)

      expect(debate.reload.rounds_limit).to eq(5)
      expect(debate.final_position).to eq(10)

      # What used to be the capping turn no longer concludes.
      debate.post_turn(by: debate.challenger, body: "t7")
      debate.post_turn(by: debate.opponent, body: "t8")
      expect(debate.reload).to be_active

      debate.post_turn(by: debate.challenger, body: "t9")
      expect { debate.post_turn(by: debate.opponent, body: "t10") }
        .to change { debate.reload.status }.from("active").to("concluded")
    end

    it "re-opens the window one round later, so it can be used again" do
      debate = debate_with_turns(:active, 6)
      debate.extend_rounds!(by: debate.challenger)

      expect(debate.extendable_by?(debate.challenger)).to be(false) # window closed

      debate.post_turn(by: debate.challenger, body: "t7")
      debate.post_turn(by: debate.opponent, body: "t8")

      expect(debate.reload.extendable_by?(debate.challenger)).to be(true) # boundary again
      expect(debate.extend_rounds!(by: debate.challenger)).to be(true)
      expect(debate.reload.rounds_limit).to eq(6)
    end
  end
end
