# The test environment is used exclusively to run your application's
# test suite. You never need to work with it otherwise. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  config.cache_classes = false

  # Do not eager load code on boot. This avoids loading your whole application
  # just for the purpose of running a single test. If you are using a tool that
  # preloads Rails for running tests, you may have to set it to true.
  config.eager_load = false

  # Configure public file server for tests with Cache-Control for performance.
  #
  # Task 8 (2026): OFF by default here, mirroring production.rb's own
  # `ENV["RAILS_SERVE_STATIC_FILES"].present?` gate. ActionDispatch::Static sits
  # ahead of routing in the middleware stack (`bin/rails middleware`) and matches
  # ANY GET/HEAD path against `public/<path>.html` before the request ever reaches
  # a controller. With this hardcoded true, `get "/404"` in spec/requests/errors_spec.rb
  # was being answered by the (now-rebranded) static public/404.html with a bare 200 —
  # never reaching config.exceptions_app's ErrorsController, and never exercising the
  # actual 404/422/500 status codes the branded page exists to serve. Nothing else in
  # the suite reads a literal public/ file, so turning this off costs nothing and lets
  # /404, /422, /500 resolve to the real route instead of being shadowed.
  config.public_file_server.enabled = ENV["RAILS_SERVE_STATIC_FILES"].present?
  config.public_file_server.headers = {
    "Cache-Control" => "public, max-age=#{1.hour.to_i}"
  }

  # Show full error reports and disable controller/fragment caching.
  config.consider_all_requests_local = true
  config.action_controller.perform_caching = false
  # A real in-memory store (not :null_store) so low-level Rails.cache reads/writes
  # behave as in production — Hujah.trending caches its ordered ids via
  # Rails.cache.fetch and its spec asserts the entry exists. Specs that depend on
  # cache state clear it in a `before` hook.
  config.cache_store = :memory_store

  # Raise exceptions instead of rendering exception templates.
  config.action_dispatch.show_exceptions = :none

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Store uploaded files on the local file system in a temporary directory.
  config.active_storage.service = :test

  config.action_mailer.perform_caching = false

  # Tell Action Mailer not to deliver emails to the real world.
  # The :test delivery method accumulates sent emails in the
  # ActionMailer::Base.deliveries array.
  config.action_mailer.delivery_method = :test
  config.action_mailer.default_url_options = {host: "localhost", port: 3000}

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr

  # Raises error for missing translations.
  # config.action_view.raise_on_missing_translations = true
end
