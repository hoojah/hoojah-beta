# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "openssl"
require "timeout"
require "socket"

module OmniAuth
  module MyDigitalId
    class IdTokenError < StandardError; end

    # Fetches a Keycloak JWKS document and caches it in-process by URI with a TTL.
    # Thread-safe. `force: true` bypasses the cache (used on a genuine kid cache-miss).
    class JwksFetcher
      # Shared process-wide instance. OmniAuth `dup`s the strategy per request, and the
      # validator defaults to this instance, so the cache/mutex/TTL are actually shared
      # across logins instead of being rebuilt (and thrown away) on every request.
      def self.default
        @default ||= new
      end

      def initialize(ttl: 3600, http: Net::HTTP)
        @ttl = ttl
        @http = http
        @cache = {}
        @mutex = Mutex.new
      end

      def call(uri, force: false)
        # The mutex is deliberately held across the HTTP fetch: on a cold cache a burst
        # of concurrent logins would otherwise stampede the JWKS endpoint (thundering
        # herd). Serializing means the first request fetches and the rest read the cache.
        @mutex.synchronize do
          entry = @cache[uri]
          return entry[:jwks] if !force && entry && entry[:at] + @ttl > monotonic

          jwks = fetch(uri)
          @cache[uri] = {jwks: jwks, at: monotonic}
          jwks
        end
      end

      private

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def fetch(uri)
        res = @http.get_response(URI(uri))
        unless res.is_a?(Net::HTTPSuccess)
          raise IdTokenError, "JWKS fetch failed (#{res.code})"
        end
        JSON.parse(res.body, symbolize_names: true)
      rescue JSON::ParserError => e
        raise IdTokenError, "JWKS parse failed: #{e.message}"
      rescue SystemCallError, SocketError, OpenSSL::SSL::SSLError, IOError, Timeout::Error => e
        # Transport failures (connection refused, DNS, TLS, timeout) must stay inside the
        # IdTokenError contract so the strategy can fail! cleanly instead of 500ing.
        raise IdTokenError, "JWKS fetch failed: #{e.message}"
      end
    end
  end
end
