# Link-or-create interstitial for a MyDigital ID subject that is not yet linked to a
# hoojah account. Two paths: link to an existing account (email + password), or create
# a new account (username only; secure random password). Guarded by a short-lived
# session[:pending_mydid] carrying only the opaque `sub` and display name — never the
# NRIC. Fails closed to the login page when that value is missing or stale.
class MydigitalIdLinksController < ApplicationController
  PENDING_TTL = 15.minutes

  before_action :require_pending_mydid

  def new
    skip_authorization
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

  def finish_linked(user)
    session.delete(:pending_mydid)
    sign_in(user, event: :authentication)
    redirect_to after_sign_in_path_for(user), notice: "Signed in with MyDigital ID."
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
