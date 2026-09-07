class FlagsController < ApplicationController
  before_action :authenticate_user!

  # Flag a hoojah from the native <dialog> on the show page. The flag always
  # records under `current_user` (the posted params never carry a user_id), and
  # `subject` is the Flag enum (spam/abusive/irrelevant). Responds as a Turbo
  # Stream that closes the dialog + renders a confirmation.
  def create
    authorize Flag
    @hujah = Hujah.friendly.find(params[:slug])

    # Validate the submitted subject before persisting. Two holes this closes:
    # (a) a POST that omits or garbles flag[subject] would otherwise persist a
    #     nil/unknown-subject flag (a nil subject is a crash vector downstream); and
    # (b) an image-subject flag only makes sense when a visible image exists — reject it
    #     when the hujah has no attached image or the image was moderator-removed.
    # `authorize Flag` already ran, so verify_authorized is satisfied on this early return.
    return head :unprocessable_content unless valid_flag_subject?

    # Idempotent under the [user, hujah] unique index (2026 moderation): a re-flag
    # updates the reason instead of raising RecordInvalid. Deliberately does NOT touch
    # `status` — re-flagging already-reviewed content must not re-open a resolved report.
    @flag = current_user.flags.find_or_initialize_by(hujah: @hujah)
    @flag.update!(subject: flag_params[:subject])

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to hujah_path(@hujah.slug), notice: "Thanks — this hoojah has been flagged." }
    end
  end

  private

  # A submitted subject is acceptable only if it is a real Flag subject, and — for the
  # two image subjects — only if the hujah still has a visible (attached, un-removed)
  # image to be reporting about.
  def valid_flag_subject?
    subject = flag_params[:subject]
    return false unless Flag.subjects.key?(subject)

    if Hujah::IMAGE_FLAG_SUBJECTS.map(&:to_s).include?(subject)
      return @hujah.image.attached? && @hujah.image_removed_at.nil?
    end

    true
  end

  def flag_params
    params.require(:flag).permit(:subject)
  end
end
