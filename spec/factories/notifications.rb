FactoryBot.define do
  factory :notification do
    association :user
    association :hujah
    association :subject_user, factory: :user
    body { "MyString" }
    category { :new_hoojah_response }
    read { false }
  end
end
