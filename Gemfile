source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '3.3.12'

gem 'rails', '~> 8.0.0'
gem 'pg', '>= 0.18', '< 2.0'
gem 'puma', '~> 6.4'
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
  gem 'rspec-rails', '~> 7.0'
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
