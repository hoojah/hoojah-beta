# frozen_string_literal: true

require "jwt"
require "omniauth/mydigital_id/jwks_fetcher"

module OmniAuth
  module MyDigitalId
    # Validates a Keycloak-issued ID token: RS256 signature against JWKS, plus
    # iss/aud/exp and (when supplied) nonce. Returns the decoded payload or raises
    # IdTokenError. On a genuinely unknown key id the jwt gem re-invokes the JWKS
    # loader with kid_not_found: true, which forces one refetch (key rotation).
    class IdTokenValidator
      def initialize(id_token:, jwks_uri:, issuer:, audience:, nonce:, jwks_fetcher: JwksFetcher.default)
        @id_token = id_token
        @jwks_uri = jwks_uri
        @issuer = issuer
        @audience = audience
        @nonce = nonce
        @jwks_fetcher = jwks_fetcher
      end

      def validate!
        raise IdTokenError, "missing id_token" if @id_token.nil? || @id_token.to_s.empty?

        payload = JWT.decode(
          @id_token, nil, true,
          algorithms: ["RS256"],
          # Callable JWKS loader: the jwt gem calls this with kid_not_found: true only
          # when the token's kid is genuinely absent from the cached set (i.e. real key
          # rotation), so a forced refetch happens then and NOT for expired/forged/garbage
          # tokens, which are rejected outright.
          jwks: ->(opts) { @jwks_fetcher.call(@jwks_uri, force: opts[:kid_not_found]) },
          iss: @issuer, verify_iss: true,
          aud: @audience, verify_aud: true,
          verify_expiration: true
        ).first
        verify_nonce!(payload)
        payload
      rescue JWT::DecodeError => e
        raise IdTokenError, e.message
      end

      private

      def verify_nonce!(payload)
        # Safe to skip when no nonce was supplied: OmniAuth's own state (CSRF) gate runs
        # before the callback reaches token validation, so the request is already bound.
        return if @nonce.nil?
        raise IdTokenError, "nonce mismatch" unless payload["nonce"] == @nonce
      end
    end
  end
end
