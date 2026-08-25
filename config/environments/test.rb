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
  # MUST stay enabled: system specs drive real Chrome, which auto-requests
  # /favicon.ico (and assets). ActionDispatch::Static answers those before routing;
  # with it off they fall through to the router, raise ActionController::RoutingError
  # under show_exceptions=:none, and Capybara re-raises — killing every system spec.
  # errors_spec.rb therefore exercises ErrorsController via POST (Static ignores
  # non-GET/HEAD), which also mirrors how config.exceptions_app reaches it in prod.
  config.public_file_server.enabled = true
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
