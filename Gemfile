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
gem "rack-cors"
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
gem "kamal", require: false
gem "thruster", require: false

group :development, :test do
  gem "byebug", platforms: [:mri, :mingw, :x64_mingw]
  gem "rspec-rails", "~> 7.0"
  gem "factory_bot_rails"
  gem "brakeman", require: false
  gem "bundler-audit", require: false
  gem "strong_migrations", "~> 2.5"
  gem "standard"
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
