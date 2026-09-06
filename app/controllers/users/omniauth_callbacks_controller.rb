class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  # Devise controller → ApplicationController's verify_authorized is auto-skipped.
  def google_oauth2
    @user = User.from_omniauth(request.env["omniauth.auth"])

    if @user&.persisted? && @user.errors.blank?
      sign_in_and_redirect @user, event: :authentication
      set_flash_message(:notice, :success, kind: "Google") if is_navigational_format?
    else
      messages = @user&.errors&.full_messages&.join("\n").presence || "Could not sign you in with Google."
      redirect_to new_user_session_path, alert: messages
    end
  end

  # MyDigital ID has no email, so we cannot auto-link. A known subject signs in only
  # when the visitor is signed OUT, or is already that same account — never a silent
  # switch of a signed-in user into a DIFFERENT account (that must be confirmed). An
  # unknown subject, or a known one belonging to another account while signed in, is
  # stashed (opaque `sub` + display name, never the NRIC) and sent to the interstitial
  # to confirm link / switch / create.
  def my_digital_id
    auth = request.env["omniauth.auth"]
    linked_user = User.from_my_digital_id(auth)

    if linked_user && (!user_signed_in? || current_user == linked_user)
      session.delete(:pending_mydid)
      sign_in_and_redirect linked_user, event: :authentication
      set_flash_message(:notice, :success, kind: "MyDigital ID") if is_navigational_format?
    else
      session[:pending_mydid] = {
        "sub" => auth.uid,
        "name" => auth.info.name.to_s,
        "at" => Time.current.to_i
      }
      redirect_to mydigital_id_continue_path
    end
  end

  def failure
    redirect_to new_user_session_path, alert: "Could not sign you in. Please try again."
  end
end
