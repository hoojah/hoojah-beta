class FlagsController < ApplicationController
  before_action :authenticate_user!

  # Flag a hoojah from the native <dialog> on the show page. The flag always
  # records under `current_user` (the posted params never carry a user_id), and
  # `subject` is the Flag enum (spam/abusive/irrelevant). Responds as a Turbo
  # Stream that closes the dialog + renders a confirmation.
  def create
    authorize Flag
    @hujah = Hujah.friendly.find(params[:slug])
    current_user.flags.create!(hujah: @hujah, subject: flag_params[:subject])

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to hujah_path(@hujah.slug), notice: "Thanks — this hoojah has been flagged." }
    end
  end

  private

  def flag_params
    params.require(:flag).permit(:subject)
  end
end
