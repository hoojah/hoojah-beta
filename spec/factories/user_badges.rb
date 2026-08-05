FactoryBot.define do
  factory :user_badge do
    association :user
    badge_key { "first_hoojah" }
  end
end
