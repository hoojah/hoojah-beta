source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.4.9"

gem "rails", "~> 8.1"
gem "pg", ">= 0.18", "< 2.0"
gem "puma", "~> 7.0", ">= 7.2.1"
gem "jbuilder", "~> 2.7"

# Asset pipeline + Hotwire (Project 2)
gem "propshaft"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "tailwindcss-rails"
gem "bcrypt", "~> 3.1.7"
gem "devise", "~> 5.0"
# Cloudinary storage service for ActiveStorage (profile photos)
gem "cloudinary", "~> 2.2"
# S3-compatible storage (self-hosted Garage) for ActiveStorage in production
gem "aws-sdk-s3", require: false
# Google OAuth2 sign-in via Devise/OmniAuth
gem "omniauth-google-oauth2", "~> 1.1"
gem "omniauth-rails_csrf_protection", "~> 1.0"
# WebAuthn / passkeys — server-side Relying Party for passwordless login.
gem "webauthn", "~> 3.4"
gem "jsonapi-serializer"
gem "friendly_id", "~> 5.7"
gem "rails_autolink"
gem "lucide-rails"
gem "pagy", "~> 43.6"
gem "pundit", "~> 2.5"
gem "rack-attack", "~> 6.8"
gem "invisible_captcha", "~> 0.8"
gem "bootsnap", ">= 1.4.2", require: false

# Rails 8 default infrastructure (adopted in Phase 8 modernization).
gem "solid_queue"
gem "solid_cache"
gem "solid_cable"
# Kamal was removed in Slice 10b: the deploy target is Coolify, which builds from the
# Dockerfile in this repo and fronts the container with its own TLS-terminating proxy.
# config/deploy.yml and .kamal/ went with it — they were never filled in past the
# generated placeholders, so nothing was ever deployed through them.
#
# Thruster STAYS, and is not vestigial Kamal tooling: the Dockerfile's CMD runs Puma
# inside it for gzip, HTTP caching of digest-stamped assets, and X-Sendfile. Its TLS
# half is unused (TLS_DOMAIN unset) because Coolify terminates TLS.
gem "thruster", require: false

group :development, :test do
  gem "byebug", platforms: [:mri, :mingw, :x64_mingw]
  gem "rspec-rails", "~> 7.0"
  gem "factory_bot_rails"
  gem "brakeman", require: false
  gem "bundler-audit", require: false
  gem "strong_migrations", "~> 2.5"
  gem "standard"
  # N+1 detection. Configured in config/initializers/prosopite.rb to LOG ONLY,
  # never raise — see Slice 10. The Slice 2 N+1 audit was deferred; this makes it
  # ambient observation rather than a slice of its own, and must never fail CI.
  gem "prosopite"
  # Required BY prosopite, not optional: on Postgres, Prosopite#fingerprint does
  # `require "pg_query"` the first time it actually finds an N+1 — and LoadError is
  # not a StandardError, so its internal `rescue` does not catch it. Without this gem
  # prosopite is harmless until the moment it detects something, then it explodes.
  gem "pg_query"
end

group :development do
  gem "web-console", ">= 3.3.0"
  gem "listen", "~> 3.3"
  gem "letter_opener"
  # Spring removed: Rails 7 dropped it; spring 2.1 / spring-watcher-listen are incompatible.
end

group :test do
  gem "json-schema"
  gem "capybara"
  gem "cuprite"
end

gem "tzinfo-data", platforms: [:mingw, :mswin, :x64_mingw, :jruby]
