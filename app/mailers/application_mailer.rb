class ApplicationMailer < ActionMailer::Base
  # From address lives in config.x.mailer_from (config/application.rb), shared with Devise.
  default from: Rails.configuration.x.mailer_from
  layout "mailer"
end
