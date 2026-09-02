FactoryBot.define do
  # HujahArchive has NO `hujah` association/column — only a FK-less integer `hujah_id`.
  # `hujah` is a transient convenience so specs can pass `hujah:` (and optionally an
  # explicit `hujah_id:`) and have the integer id resolved for them.
  factory :hujah_archive do
    transient do
      hujah { nil }
    end

    snapshot { {"body" => "Frozen body", "arguments" => []} }
    visibility_before { Hujah.visibilities[:visible_public] }
    sequence(:token) { |n| "tok_#{n}_#{SecureRandom.hex(4)}" }

    # Resolve hujah_id from an explicit value, else the transient hujah, else a fresh one.
    hujah_id { hujah&.id || create(:hujah).id }
  end

  factory :hujah_archive_participant do
    association :archive, factory: :hujah_archive
    association :user
  end
end
