require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Hoojah
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.

    # Don't generate system test files.
    config.generators.system_tests = nil

    # Slice 3: attr_readonly on Hujah's stance-label columns is a TAMPER guard, not a
    # validation — an update that tries to rewrite a locked label must be a silent no-op,
    # not a 500. `load_defaults 8.1` sets raise_on_assign_to_attr_readonly to true (which
    # would raise ActiveRecord::ReadonlyAttributeError on such an assignment); we opt back
    # into the drop-silently behaviour the immutability contract depends on. Hujah's
    # stance labels are the ONLY attr_readonly attributes in the app, so this has no other
    # blast radius.
    config.active_record.raise_on_assign_to_attr_readonly = false

    # Rate limiting / throttling (login, signup, password reset, votes).
    config.middleware.use Rack::Attack
  end
end
