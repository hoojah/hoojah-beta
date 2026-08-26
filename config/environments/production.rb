Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.cache_classes = true

  # Eager load code on boot. This eager loads most of Rails and
  # your application in memory, allowing both threaded web servers
  # and those relying on copy on write to perform better.
  # Rake tasks automatically ignore this option for performance.
  config.eager_load = true

  # Full error reports are disabled and caching is turned on.
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true

  # Render unhandled exceptions through the app's own branded ErrorsController
  # (config/routes.rb: /404, /422, /500) instead of the static public/*.html.
  config.exceptions_app = routes

  # Ensures that a master key has been made available in either ENV["RAILS_MASTER_KEY"]
  # or in config/master.key. This key is used to decrypt credentials (and other encrypted files).
  # config.require_master_key = true

  # Serve /public (and therefore /assets) from this process when RAILS_SERVE_STATIC_FILES
  # is set. The Dockerfile bakes it in, because nothing else in the Coolify deployment
  # can serve these files: the platform's proxy has no access to the container's
  # filesystem, and Thruster proxies-then-caches rather than serving public/ itself — so
  # with this off, every stylesheet 404s and the app renders unstyled.
  config.public_file_server.enabled = ENV["RAILS_SERVE_STATIC_FILES"].present?
  # Propshaft digests every asset filename, so a given URL's contents can never change:
  # cache it for a year. Without this header Rails sends no Cache-Control for static
  # files at all, which means browsers revalidate on every page view AND Thruster's HTTP
  # cache refuses to store them (measured: `X-Cache: miss` on every repeat request).
  config.public_file_server.headers = {"cache-control" => "public, max-age=#{1.year.to_i}"}

  # Compress CSS using a preprocessor.
  # config.assets.css_compressor = :sass

  # Do not fallback to assets pipeline if a precompiled asset is missed.
  config.assets.compile = true

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.action_controller.asset_host = 'http://assets.example.com'

  # Specifies the header that your server uses for sending files.
  # config.action_dispatch.x_sendfile_header = 'X-Sendfile' # for Apache
  # config.action_dispatch.x_sendfile_header = 'X-Accel-Redirect' # for NGINX

  # Store uploaded files on the local file system (see config/storage.yml for options).
  # Garage (self-hosted S3) wins when GARAGE_ACCESS_KEY_ID is set; otherwise Cloudinary.
  config.active_storage.service = ENV["GARAGE_ACCESS_KEY_ID"].present? ? :garage : :cloudinary

  # Mount Action Cable outside main process or domain.
  # config.action_cable.mount_path = nil
  # config.action_cable.url = 'wss://example.com/cable'
  # config.action_cable.allowed_request_origins = [ 'http://example.com', /http:\/\/example.*/ ]

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true
  # TLS is terminated at Coolify's reverse proxy, which then talks plain HTTP to this
  # container; trust the forwarded scheme. `assume_ssl` inserts ActionDispatch::AssumeSSL
  # at the bottom of the stack, which marks EVERY request as HTTPS unconditionally — so
  # force_ssl never issues a redirect in this deployment, including for the plain-HTTP
  # health probe on the internal Docker network. That is why there is no `ssl_options`
  # `:exclude` for /up here: it would be dead config. If `assume_ssl` is ever turned off,
  # /up starts 301-ing and the health check breaks — add the exclude then.
  config.assume_ssl = true

  # Use the lowest log level to ensure availability of diagnostic information
  # when problems arise.
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Only accept requests for the configured host(s) (set APP_HOST at deploy).
  # NOTE: `config.hosts` is empty by default in production, so host authorization is
  # OFF until APP_HOST is set — and every request is blocked with 403 the moment it is
  # set to the wrong value.
  config.hosts << ENV["APP_HOST"] if ENV["APP_HOST"].present?
  # ...but the health probe is the one request that legitimately arrives with the WRONG
  # Host. Coolify polls the container over the internal Docker network by container IP
  # or internal hostname, never by APP_HOST, so host authorization answers it with 403
  # and the deploy never goes healthy. Excluding the path (not a host) keeps the
  # allowlist strict for everything that can actually leak data: /up renders a fixed
  # "green" page with no request-derived content, so it cannot be used for a DNS-rebind
  # or cache-poisoning attack the way an absolute-URL-generating page could.
  config.host_authorization = {exclude: ->(request) { request.path == "/up" }}

  # Prepend all log lines with the following tags.
  config.log_tags = [:request_id]

  # Use a different cache store in production.
  config.cache_store = :solid_cache_store

  # Use a real queuing backend for Active Job (and separate queues per environment).
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = {database: {writing: :queue}}
  # config.active_job.queue_name_prefix = "hoojah_production"

  config.action_mailer.perform_caching = false

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Send deprecation notices to registered listeners.
  config.active_support.deprecation = :notify

  # Use default logging formatter so that PID and timestamp are not suppressed.
  config.log_formatter = ::Logger::Formatter.new

  # Use a different logger for distributed setups.
  # require 'syslog/logger'
  # config.logger = ActiveSupport::TaggedLogging.new(Syslog::Logger.new 'app-name')

  if ENV["RAILS_LOG_TO_STDOUT"].present?
    logger = ActiveSupport::Logger.new($stdout)
    logger.formatter = config.log_formatter
    config.logger = ActiveSupport::TaggedLogging.new(logger)
  end

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Inserts middleware to perform automatic connection switching.
  # The `database_selector` hash is used to pass options to the DatabaseSelector
  # middleware. The `delay` is used to determine how long to wait after a write
  # to send a subsequent read to the primary.
  #
  # The `database_resolver` class is used by the middleware to determine which
  # database is appropriate to use based on the time delay.
  #
  # The `database_resolver_context` class is used by the middleware to set
  # timestamps for the last write to the primary. The resolver uses the context
  # class timestamps to determine how long to wait before reading from the
  # replica.
  #
  # By default Rails will store a last write timestamp in the session. The
  # DatabaseSelector middleware is designed as such you can define your own
  # strategy for connection switching and pass that into the middleware through
  # these configuration options.
  # config.active_record.database_selector = { delay: 2.seconds }
  # config.active_record.database_resolver = ActiveRecord::Middleware::DatabaseSelector::Resolver
  # config.active_record.database_resolver_context = ActiveRecord::Middleware::DatabaseSelector::Resolver::Session
end
