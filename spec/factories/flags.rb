FactoryBot.define do
  factory :flag do
    association :user
    association :hujah
    subject { :spam }
  end
end
