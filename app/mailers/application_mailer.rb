class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_FROM", "Hoojah <no-reply@hoojah.rudzainy.com>")
  layout "mailer"
end
