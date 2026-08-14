require "rails_helper"
require Rails.root.join("db/migrate/20260814120000_add_rounds_limit_to_debates")

RSpec.describe "debate rounds and phases", type: :model do
  def debate_with_turns(status, count)
    create(:debate, status: status).tap do |debate|
      count.times do |i|
        create(:debate_turn, debate: debate, user: (i.even? ? debate.challenger : debate.opponent))
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

    # The whole point of the backfill: no active debate may be left at or below
    # the round it is currently on, or Task 3.2's cap would retroactively
    # conclude a debate that is mid-flight. Covers odd turn counts, where
    # Postgres integer division must truncate exactly as Ruby's Integer#/ does.
    it "leaves every active debate strictly above its current round" do
      debates = (0..9).map { |count| debate_with_turns(:active, count) }

      replay_backfill!

      debates.each do |debate|
        debate.reload
        expect(debate.rounds_limit).to be > debate.current_round
      end
    end
  end
end
