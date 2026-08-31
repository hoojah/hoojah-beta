class ShortLinksController < ApplicationController
  # Public + unauthenticated. skip_authorization is correct here: the redirect
  # TARGET enforces its own policy/visibility on arrival (hujahs#show / debates#show
  # run their Pundit checks), and an opaque code reveals nothing about the resource.
  # There is nothing to authorize at the /s/:code hop itself.
  def show
    skip_authorization
    link = ShortLink.find_by!(code: params[:code]) # RecordNotFound → branded 404
    # 301 to the stored INTERNAL path only. `allow_other_host: false` is
    # belt-and-braces atop ShortLink's target_path format validation — even a
    # somehow-malformed stored value cannot redirect off-host.
    redirect_to link.target_path, status: :moved_permanently, allow_other_host: false
  end
end
