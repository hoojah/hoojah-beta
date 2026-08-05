FactoryBot.define do
  factory :debate_turn do
    association :debate
    association :user
    body { "A turn in the debate." }
    sequence(:position) { |n| n }
  end
end
