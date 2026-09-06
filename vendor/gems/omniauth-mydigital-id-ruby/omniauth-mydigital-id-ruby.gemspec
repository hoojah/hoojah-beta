# frozen_string_literal: true

require_relative "lib/omniauth/mydigital_id/version"

Gem::Specification.new do |spec|
  spec.name = "omniauth-mydigital-id-ruby"
  spec.version = OmniAuth::MyDigitalId::VERSION
  spec.authors = ["Rudzainy Rahman"]
  spec.email = ["rudzainy@gmail.com"]
  spec.summary = "OmniAuth strategy for Malaysia's MyDigital ID SSO (Keycloak OIDC)."
  spec.description = "Authorization Code + OIDC strategy for MyDigital ID, with ID-token JWKS validation."
  spec.homepage = "https://github.com/rudzainy/omniauth-mydigital-id-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir["lib/**/*", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "omniauth", "~> 2.0"
  spec.add_dependency "omniauth-oauth2", "~> 1.8"
  spec.add_dependency "jwt", "~> 2.7"

  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "webmock", "~> 3.23"
  spec.add_development_dependency "rack-test", "~> 2.1"
  spec.add_development_dependency "rack-session", "~> 2.0"
  spec.add_development_dependency "standard", "~> 1.35"
end
