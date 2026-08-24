class TagsController < ApplicationController
  # Public hashtag feed. Read-only, no owner — skip_authorization satisfies
  # ApplicationController's verify_authorized. The card scope mirrors HujahsController#index's
  # global/anonymous branch EXACTLY (top-level, public author, per-post visible_public,
  # minus hidden authors for signed-in viewers) so a non-public claim can never leak here.
  def show
    skip_authorization
    @tag = Hashtag.find_by!(name: Hashtag.canonical(params[:name]))
    base = @tag.hujahs.where(parent_id: nil).where(visibility: :visible_public)
      .joins(:user).where(users: {private: false}).includes(:user).order(updated_at: :desc)
    base = base.where.not(user_id: current_user.hidden_user_ids) if user_signed_in?
    @pagy, @hujahs = pagy(:countless, base)
    respond_to do |format|
      format.html
      format.turbo_stream # show.turbo_stream.erb (load-more append)
    end
  rescue ActiveRecord::RecordNotFound
    # The tag lookup raised before anything authorized — satisfy verify_authorized.
    skip_authorization
    head :not_found
  end
end
