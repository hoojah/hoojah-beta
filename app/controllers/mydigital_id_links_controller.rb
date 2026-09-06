# Link-or-create interstitial for a MyDigital ID subject that is not yet linked to a
# hoojah account. Two paths: link to an existing account (email + password), or create
# a new account (username only; secure random password). Guarded by a short-lived
# session[:pending_mydid] carrying only the opaque `sub` and display name — never the
# NRIC. Fails closed to the login page when that value is missing or stale.
class MydigitalIdLinksController < ApplicationController
  PENDING_TTL = 15.minutes

  before_action :require_pending_mydid
  # L1 defense-in-depth: a signed-in user must NEVER reach the anonymous link/create
  # actions — those silently create-or-switch into a different account. They confirm
  # linking to their CURRENT account via #link_current instead. Runs after
  # require_pending_mydid; a halted before_action also skips verify_authorized.
  before_action :reject_signed_in, only: %i[create create_account]
  # Exposed to the interstitial view as @name so it never reaches into session
  # internals, plus the signed-in branch state (@signed_in / @already_linked). Set for
  # every action, because `create`/`create_account`/`link_current` all `render :new`
  # on failure and the greeting + branch must still render correctly.
  before_action :set_view_state

  def new
    skip_authorization
  end

  # L1: a signed-in user confirms linking the pending MyDigital ID to their CURRENT
  # account. No new account is ever created or switched into on this path.
  def link_current
    skip_authorization
    return redirect_to mydigital_id_continue_path unless user_signed_in?

    if @already_linked
      flash.now[:alert] = "Your account is already linked to a MyDigital ID."
      return render :new, status: :unprocessable_entity
    end

    current_user.identities.create!(provider: User::MYDIGITAL_ID_PROVIDER, uid: pending_sub)
    session.delete(:pending_mydid)
    redirect_to after_sign_in_path_for(current_user), status: :see_other,
      notice: "MyDigital ID linked to your account."
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # This sub was linked to another account concurrently.
    flash.now[:alert] = "This MyDigital ID is already linked to another account."
    render :new, status: :unprocessable_entity
  end

  # Link the pending MyDigital ID to an existing account after re-auth.
  def create
    skip_authorization
    user = User.find_by(email: params[:email].to_s.downcase.strip)

    unless user&.valid_password?(params[:password].to_s)
      flash.now[:alert] = "Those credentials didn't match an account."
      return render :new, status: :unprocessable_entity
    end

    if user.identities.exists?(provider: User::MYDIGITAL_ID_PROVIDER)
      flash.now[:alert] = "That account is already linked to a MyDigital ID."
      return render :new, status: :unprocessable_entity
    end

    user.identities.create!(provider: User::MYDIGITAL_ID_PROVIDER, uid: pending_sub)
    finish_linked(user)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    flash.now[:alert] = "This MyDigital ID is already linked to another account."
    render :new, status: :unprocessable_entity
  end

  # Create a fresh account for the pending MyDigital ID (the "I don't have a Hoojah
  # account yet" path). Server-side re-validates the username (client checks are UX only).
  def create_account
    skip_authorization
    user = User.create_with_my_digital_id(
      username: params[:username], sub: pending_sub, full_name: pending_name
    )

    if user.persisted?
      finish_linked(user)
    else
      flash.now[:alert] = user.errors.full_messages.to_sentence.presence ||
        "Could not create your account."
      render :new, status: :unprocessable_entity
    end
  end

  private

  # Sets the view state shared by every render :new path.
  def set_view_state
    @name = pending_name
    @signed_in = user_signed_in?
    @already_linked = @signed_in &&
      current_user.identities.exists?(provider: User::MYDIGITAL_ID_PROVIDER)
  end

  # L1: bounce a signed-in user off the anonymous link/create actions to the
  # confirmation interstitial, so they can never silently create/switch accounts.
  def reject_signed_in
    redirect_to mydigital_id_continue_path if user_signed_in?
  end

  def finish_linked(user)
    session.delete(:pending_mydid)
    sign_in(user, event: :authentication)
    redirect_to after_sign_in_path_for(user), status: :see_other, notice: "Signed in with MyDigital ID."
  end

  def require_pending_mydid
    data = session[:pending_mydid]
    if data.blank? || data["at"].to_i + PENDING_TTL.to_i < Time.current.to_i
      session.delete(:pending_mydid)
      redirect_to new_user_session_path,
        alert: "Your MyDigital ID session expired. Please sign in again."
    end
  end

  def pending_sub = session.dig(:pending_mydid, "sub")

  def pending_name = session.dig(:pending_mydid, "name")
end
