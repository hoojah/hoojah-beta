FactoryBot.define do
  factory :short_link do
    code { SecureRandom.alphanumeric(7) }
    target_path { "/hoojah/some-slug" }
  end
end
