source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '2.7.8'

gem 'rails', '~> 7.0.8'
# Pin: concurrent-ruby 1.3.5 dropped its transitive `require "logger"`, which
# Rails 6.0 relies on (ActiveSupport::LoggerThreadSafeLevel). Remove once on Rails >= 7.1.
gem 'concurrent-ruby', '1.3.4'
# Pin: ffi 1.13.1 (via sassc) can't resolve size_t on arm64; 1.17+ needs Ruby >= 3.0.
# 1.16.x is the newest arm64-capable line still supporting Ruby 2.7. Relax as Ruby bumps.
gem 'ffi', '~> 1.16.3'
gem 'pg', '>= 0.18', '< 2.0'
gem 'puma', '~> 4.1'
gem 'sass-rails', '>= 6'
# shakapacker v6: maintained webpacker successor that keeps the Webpacker constant,
# webpacker.yml filename, and pack helpers -> minimal churn. The React/webpack JS
# build itself is deferred to Project 2 (Hotwire), which deletes this whole layer.
gem 'shakapacker', '~> 6.6'
gem 'jbuilder', '~> 2.7'
gem 'bcrypt', '~> 3.1.7'
gem 'rack-cors'
gem 'fast_jsonapi'
gem 'slug'
gem 'bootsnap', '>= 1.4.2', require: false

group :development, :test do
  gem 'byebug', platforms: [:mri, :mingw, :x64_mingw]
  gem 'rspec-rails', '~> 5.1'
  gem 'factory_bot_rails'
end

group :development do
  gem 'web-console', '>= 3.3.0'
  gem 'listen', '~> 3.3'
  # Spring removed: Rails 7 dropped it; spring 2.1 / spring-watcher-listen are incompatible.
end

group :test do
  gem "json-schema"
end

gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw, :jruby]
