FactoryBot.define do
  factory :user_identity do
    user
    provider { "my_digital_id" }
    sequence(:uid) { |n| "sub-#{n}" }
  end
end
