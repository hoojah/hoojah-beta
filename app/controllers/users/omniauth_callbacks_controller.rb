class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  # Devise controller → ApplicationController's verify_authorized is auto-skipped.
  def google_oauth2
    @user = User.from_omniauth(request.env["omniauth.auth"])

    if @user&.persisted?
      sign_in_and_redirect @user, event: :authentication
      set_flash_message(:notice, :success, kind: "Google") if is_navigational_format?
    else
      messages = @user&.errors&.full_messages&.join("\n").presence || "Could not sign you in with Google."
      redirect_to new_user_session_path, alert: messages
    end
  end

  def failure
    redirect_to new_user_session_path, alert: "Could not sign you in with Google."
  end
end
