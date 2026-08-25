class HujahSerializer
  include JSONAPI::Serializer

  attributes :body, :agree_count, :neutral_count, :disagree_count, :vote, :slug

  # Slice 11 (A1): children_count reflects only the replies this viewer may see —
  # returning the raw count alongside a filtered `children` array would itself leak
  # that hidden replies exist. Shares Hujah#visible_children_for with `children`.
  attribute :children_count do |hujah, params|
    hujah.visible_children_for(params[:current_user]).size
  end

  # this is the owner of the hujah, not the current user
  attribute :user do |hujah|
    {
      id: hujah.user.id,
      type: "user",
      attributes: {
        username: hujah.user.username,
        full_name: hujah.user.full_name,
        photo: hujah.user.photo
      }
    }
  end

  # Slice 11 (A1): only expose the parent block when the parent is visible to the
  # viewer (privacy via #visible_to?) AND not authored by someone the viewer blocked —
  # a private/blocked parent author must not leak through a public reply's `parent`.
  attribute :parent, if: proc { |hujah, params|
    hujah.parent_id &&
      hujah.parent.visible_to?(params[:current_user]) &&
      !params[:current_user]&.hidden_user_ids&.include?(hujah.parent.user_id)
  } do |hujah|
    {
      id: hujah.parent.id,
      type: "hujah",
      attributes: {
        body: hujah.parent.body,
        slug: hujah.parent.slug,
        user: {
          attributes: {
            username: hujah.parent.user.username,
            full_name: hujah.parent.user.full_name,
            photo: hujah.parent.user.photo
          }
        }
      }
    }
  end

  # Slice 11 (A1): iterate ONLY the viewer-visible children (private-account + block
  # filtered in SQL via Hujah#visible_children_for) — the previous `hujah.children.each`
  # leaked private/blocked authors' reply bodies + usernames to any API caller.
  attribute :children, if: proc { |hujah, params| hujah.visible_children_for(params[:current_user]).any? } do |hujah, params|
    hujah.visible_children_for(params[:current_user]).map do |child|
      {
        id: child.id,
        type: "hujah",
        attributes: {
          body: child.body,
          vote: child.vote,
          agree_count: child.agree_count,
          neutral_count: child.neutral_count,
          disagree_count: child.disagree_count,
          slug: child.slug,
          user: {
            attributes: {
              username: child.user.username,
              full_name: child.user.full_name,
              photo: child.user.photo
            }
          }
        }
      }
    end
  end

  attribute :current_user_vote do |hujah, params|
    hujah.current_user_vote(logged_in: params[:logged_in], current_user_id: params[:current_user_id])
  end
end
