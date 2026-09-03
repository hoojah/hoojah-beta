class PasskeysController < ApplicationController
  before_action :authenticate_user!

  # Owner-only by construction: everything is scoped through current_user, so
  # index/options/create carry no authorizable record → skip_authorization. The
  # per-record mutations (update/destroy) call authorize with PasskeyPolicy.
  def index
    skip_authorization
    @credentials = current_user.webauthn_credentials.order(created_at: :desc)
  end

  # Registration step 1: hand the browser creation options and remember the
  # challenge. Mint the stable user handle on first enrollment.
  def options
    skip_authorization
    # update_column, not update!: the handle is a random opaque id needing no
    # validation/callbacks, and validating the whole User would 500 the options
    # endpoint for any legacy-invalid record.
    current_user.update_column(:webauthn_id, WebAuthn.generate_user_id) if current_user.webauthn_id.blank?

    create_options = WebAuthn::Credential.options_for_create(
      user: {
        id: current_user.webauthn_id,
        name: current_user.email,
        display_name: current_user.full_name
      },
      exclude: current_user.webauthn_credentials.pluck(:external_id),
      authenticator_selection: {resident_key: "required", user_verification: "required"},
      attestation: "none"
    )
    session[:passkey_registration_challenge] = create_options.challenge
    render json: create_options
  end

  # Registration step 2: verify the attestation, persist the credential. This is an
  # ordinary Rails controller, so a JSON body IS parsed into params (unlike the
  # Warden strategy). Read-and-delete the challenge for single use.
  def create
    skip_authorization
    challenge = session.delete(:passkey_registration_challenge)

    # Parse + verify the UNTRUSTED attestation inside a broad rescue: adversarial
    # input reaches from_create/verify and can raise far more than WebAuthn::Error —
    # NoMethodError ("{}"), TypeError ("[]"), ArgumentError (bad base64),
    # CBOR::MalformedFormatError (garbage attestationObject), etc. Fail closed on all
    # of them, logging the class so real bugs stay visible. user_verification: true
    # enforces the biometric/PIN factor the options endpoint requested.
    begin
      webauthn_credential = WebAuthn::Credential.from_create(credential_param)
      webauthn_credential.verify(challenge, user_verification: true)
    rescue => e
      Rails.logger.warn("[passkey] registration verify failed: #{e.class}")
      return redirect_to passkeys_path, alert: "We couldn't add that passkey. Please try again."
    end

    @credential = current_user.webauthn_credentials.create!(
      external_id: webauthn_credential.id,
      public_key: webauthn_credential.public_key,
      sign_count: webauthn_credential.sign_count,
      nickname: nickname_param
    )

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to passkeys_path, notice: "Passkey added." }
    end
    # RecordNotUnique guards a nickname (or external_id) collision that races past the
    # model validation from a second browser tab — same graceful path rather than a
    # 500. (blocks_controller sets the precedent.)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    redirect_to passkeys_path, alert: "We couldn't add that passkey. Please try again."
  end

  def update
    @credential = current_user.webauthn_credentials.find(params[:id])
    # The record class is WebauthnCredential, so name the policy explicitly —
    # Pundit would otherwise look for a WebauthnCredentialPolicy that doesn't exist.
    authorize @credential, policy_class: PasskeyPolicy
    @credential.update!(nickname: nickname_param)
    redirect_to passkeys_path, notice: "Passkey renamed."
    # A duplicate nickname trips the per-user uniqueness rule; a concurrent tab can
    # slip past the validation into the DB index (RecordNotUnique). Either way,
    # redirect back with an alert instead of 500-ing.
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    redirect_to passkeys_path, alert: "That name is already in use. Please pick another."
  end

  def destroy
    @credential = current_user.webauthn_credentials.find(params[:id])
    authorize @credential, policy_class: PasskeyPolicy
    @credential.destroy!
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to passkeys_path, notice: "Passkey removed.", status: :see_other }
    end
  end

  private

  def credential_param
    params.require(:passkey).require(:credential)
  end

  def nickname_param
    params.require(:passkey).fetch(:nickname, "").to_s.strip.presence || "Passkey"
  end
end
