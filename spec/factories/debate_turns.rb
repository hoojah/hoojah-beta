FactoryBot.define do
  factory :debate_turn do
    association :debate
    association :user
    body { "A turn in the debate." }
    # Per-debate and 1-based, mirroring Debate#post_turn. A FactoryBot `sequence`
    # here would be process-global ACROSS FILES, so a debate built after any other
    # turn had ever been created would start at position 11, 12, … — and
    # DebateTurn#round is derived FROM position. That corruption would be
    # order-dependent, so it would surface only when spec files happened to run in
    # a particular order.
    position { debate.turns.maximum(:position).to_i + 1 }
  end
end
