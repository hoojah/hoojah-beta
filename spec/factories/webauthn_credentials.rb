FactoryBot.define do
  factory :webauthn_credential do
    association :user
    sequence(:external_id) { |n| "credential-external-id-#{n}" }
    public_key { "cose-public-key-bytes" }
    sequence(:nickname) { |n| "Passkey #{n}" }
    sign_count { 0 }
  end
end
