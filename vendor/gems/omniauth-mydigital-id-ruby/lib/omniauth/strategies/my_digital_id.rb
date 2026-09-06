# frozen_string_literal: true

require "securerandom"
require "omniauth-oauth2"
require "omniauth/mydigital_id/id_token_validator"

module OmniAuth
  module Strategies
    # OmniAuth strategy for Malaysia's MyDigital ID SSO. MyDigital ID is a Keycloak
    # cluster (realm "mydid") speaking standard OIDC Authorization Code. This strategy
    # builds the realm endpoints, adds a nonce, and validates the returned ID token
    # against JWKS before the auth hash is trusted. Userinfo returns `nric` (Malaysian
    # IC number) and `nama` (full name) — no email.
    class MyDigitalId < OmniAuth::Strategies::OAuth2
      option :name, "my_digital_id"
      option :base_url, nil
      option :realm, "mydid"
      # Keycloak realm-path prefix (e.g. "/auth" for the legacy layout). Deliberately a
      # dedicated option — NOT OmniAuth's reserved `path_prefix`, which controls
      # request/callback routing. nil interpolates to an empty string in the realm-path
      # builders below (no /auth prefix by default).
      option :realm_path_prefix, nil
      option :scope, "openid profile email"
      option :pkce, true
      option :client_options, {}

      # `sub` — the opaque, stable Keycloak subject, taken from the VALIDATED ID token
      # (not raw userinfo). The relying party keys on this; it is NOT the NRIC. Because
      # uid is always evaluated when the auth hash is built, this makes ID-token
      # validation structural: no auth hash is produced without a validated token.
      uid { id_token_claims["sub"] }

      info do
        {name: raw_info["nama"]} # deliberately no :email — MyDigital ID supplies none
      end

      extra do
        {raw_info: raw_info, id_token_claims: id_token_claims}
      end

      def client
        options.client_options[:site] = base_url
        options.client_options[:authorize_url] = realm_path("auth")
        options.client_options[:token_url] = realm_path("token")
        super
      end

      def authorize_params
        super.tap do |params|
          params[:scope] ||= options.scope
          params[:nonce] = SecureRandom.hex(16)
          session["omniauth.nonce"] = params[:nonce]
          params[:prompt] = request.params["prompt"] if request.params["prompt"]
        end
      end

      def raw_info
        @raw_info ||= access_token.get(realm_path("userinfo")).parsed
      end

      # Validate the ID token (raises IdTokenError → OmniAuth failure via callback_phase),
      # then enforce the OIDC 5.3.2 userinfo/ID-token subject match.
      def id_token_claims
        @id_token_claims ||= begin
          claims = OmniAuth::MyDigitalId::IdTokenValidator.new(
            id_token: access_token["id_token"],
            jwks_uri: realm_url("certs"),
            issuer: issuer,
            audience: options.client_id,
            nonce: session.delete("omniauth.nonce")
          ).validate!
          verify_sub_match!(claims)
          claims
        end
      end

      def callback_phase
        super
      rescue OmniAuth::MyDigitalId::IdTokenError => e
        fail!(:invalid_id_token, e)
      end

      private

      # OIDC 5.3.2: the userinfo `sub` MUST match the ID-token `sub`. When userinfo
      # carries a sub, a mismatch means the two responses describe different subjects —
      # reject rather than trust the userinfo.
      def verify_sub_match!(claims)
        info_sub = raw_info["sub"]
        return if info_sub.nil?
        unless info_sub == claims["sub"]
          raise OmniAuth::MyDigitalId::IdTokenError, "userinfo sub does not match id_token sub"
        end
      end

      def base_url
        options.base_url or raise ArgumentError, "omniauth my_digital_id requires :base_url"
      end

      def issuer
        "#{base_url}#{options.realm_path_prefix}/realms/#{options.realm}"
      end

      def realm_path(action)
        "#{options.realm_path_prefix}/realms/#{options.realm}/protocol/openid-connect/#{action}"
      end

      def realm_url(action)
        "#{base_url}#{realm_path(action)}"
      end
    end
  end
end
