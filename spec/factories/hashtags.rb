FactoryBot.define do
  factory :hashtag do
    sequence(:display) { |n| "tag#{n}" }
    name { Hashtag.canonical(display) }
  end
end
