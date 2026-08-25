FactoryBot.define do
  factory :user do
    sequence :username do |n|
      "username#{n}"
    end
    sequence :email do |n|
      "user_#{n}@hoojah.com"
    end

    full_name { "FullName" }
    password { "hoojah88" }
    password_confirmation { "hoojah88" }

    trait(:moderator) { role { :moderator } }
    trait(:admin) { role { :admin } }
  end
end
