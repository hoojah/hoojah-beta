class Users::SessionsController < Devise::SessionsController
  # Devise controller → exempt from Pundit's verify_authorized.

  # Passkey login step 1: hand the browser an authentication challenge. Usernameless
  # / discoverable — no `allow` list, so no email is typed and email enumeration
  # stays impossible (matches config.paranoid = true). Challenge saved to session.
  def passkey_options
    get_options = WebAuthn::Credential.options_for_get(user_verification: "required")
    session[PasskeyStrategy::CHALLENGE_KEY] = get_options.challenge
    render json: get_options
  end

  # Step 2: verify the assertion through the Warden :passkey strategy. On success
  # respond with a redirect target for the JS to navigate to; the flash is set here
  # and shows on that next GET. On failure, a single generic 401 (paranoid).
  def passkey
    user = warden.authenticate(:passkey, scope: :user)
    if user
      sign_in(:user, user)
      flash[:notice] = "Signed in with your passkey."
      render json: {redirect: after_sign_in_path_for(user)}
    else
      render json: {error: "We couldn't verify that passkey."}, status: :unauthorized
    end
  end
end
