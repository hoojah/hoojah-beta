class HashtagHujah < ApplicationRecord
  belongs_to :hashtag, counter_cache: :hujahs_count
  belongs_to :hujah
end
