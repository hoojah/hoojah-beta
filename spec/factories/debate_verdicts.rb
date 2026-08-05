FactoryBot.define do
  factory :debate_verdict do
    association :debate
    association :user
    choice { :challenger }
  end
end
