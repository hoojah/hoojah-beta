require "rails_helper"
require Rails.root.join("db/migrate/20260814120000_add_rounds_limit_to_debates")

RSpec.describe "debate rounds and phases", type: :model do
  # `position` is assigned explicitly: the factory's `sequence(:position)` is
  # global to the process, so consecutive helper calls would hand a debate
  # positions like 11..20. Turn counts survive that, but DebateTurn#round is
  # derived FROM position, so the round/phase math needs a 1-based run. The
  # challenger always opens, so even indices are theirs.
  def debate_with_turns(status, count)
    create(:debate, status: status).tap do |debate|
      count.times do |i|
        create(:debate_turn, debate: debate, position: i + 1,
          user: (i.even? ? debate.challenger : debate.opponent))
      end
    end
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
