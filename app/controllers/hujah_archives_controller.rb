class HujahArchivesController < ApplicationController
  before_action :authenticate_user!

  def show
    hujah = Hujah.friendly.find(params[:slug])
    # Resolve THIS viewer's latest archive for the hoojah. Nil when they were never purged
    # into one → skip_authorization + redirect (verify_authorized satisfied on the nil
    # branch; authorize runs exactly once on the found branch).
    participant = HujahArchiveParticipant.for(current_user, hujah).first
    @archive = participant&.archive
    if @archive.nil?
      skip_authorization
      return redirect_to(root_path, alert: "No archive found.")
    end
    authorize @archive, :show?
  end
end
