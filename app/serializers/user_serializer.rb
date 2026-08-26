class UserSerializer
  include JSONAPI::Serializer

  attributes :username, :full_name, :photo, :location, :headline, :link

  # Slice 11 (A1): only the top-level hoojahs this viewer may see (per-post visibility),
  # via User#visible_hujahs_for — shared with the HTML profile "Hoojahs" tab. Count
  # follows the same filter so it can't reveal that hidden claims exist.
  attribute :hujah_count do |user, params|
    user.visible_hujahs_for(params[:current_user]).size
  end

  attribute :vote_count do |user|
    user.votes.length
  end

  attributes :hujahs, if: proc { |user, params| user.visible_hujahs_for(params[:current_user]).any? } do |user, params|
    all_hujah = []

    user.visible_hujahs_for(params[:current_user]).each do |child_hujah|
      temp_child_hujah = {
        id: child_hujah.id,
        type: "hujah",
        attributes: {
          body: child_hujah.body,
          vote: child_hujah.vote,
          # Secret ballot (2a/A7): this is the same per-stance split gated in
          # HujahSerializer, reachable via GET /api/v1/:username — gate it identically
          # (nil below k=5, always expose total_count).
          total_count: child_hujah.total_votes,
          agree_count: child_hujah.breakdown_visible? ? child_hujah.agree_count : nil,
          neutral_count: child_hujah.breakdown_visible? ? child_hujah.neutral_count : nil,
          disagree_count: child_hujah.breakdown_visible? ? child_hujah.disagree_count : nil,
          slug: child_hujah.slug,
          user: {
            attributes: {
              username: child_hujah.user.username,
              full_name: child_hujah.user.full_name,
              photo: child_hujah.user.photo
            }
          }
        }
      }
      all_hujah << temp_child_hujah
    end

    all_hujah
  end
end
