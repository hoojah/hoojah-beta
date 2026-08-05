FactoryBot.define do
  factory :debate do
    association :hujah
    association :challenger, factory: :user
    association :opponent, factory: :user
    challenger_stance { 1 }
    opponent_stance { 3 }
    status { :pending }
  end
end
