# Wrap every example in a prosopite scan. Findings go to log/prosopite.log; nothing
# here can fail an example. See config/initializers/prosopite.rb for the why.
#
# Why example hooks and not prosopite's Rack middleware: scan state is stored in
# Thread.current, and request specs run the app inline on the example's own thread,
# so wrapping the example covers controllers *and* the model/job specs a request
# middleware would never see.
#
# What this does NOT cover: `js: true` system specs. Those drive the app on a Puma
# thread, which the example thread's scan does not reach. That is an accepted gap —
# system specs exercise the same controller actions the request specs do, and adding
# the middleware in test would collide with these hooks (see the initializer).
RSpec.configure do |config|
  config.before(:each) { Prosopite.scan }

  config.after(:each) do
    # `finish` fingerprints each candidate query through PgQuery, which can raise on
    # SQL it cannot parse. Prosopite's own internal rescue re-raises in that case, and
    # an exception from an `after` hook fails the example — which is exactly the
    # "detector turns the suite red" outcome this wiring exists to prevent. Swallow it.
    # (`finish` clears the scan flag before it does any of that, so state stays sane.)
    Prosopite.finish
  rescue => e
    Rails.logger.warn("Prosopite.finish raised #{e.class}: #{e.message} — ignored")
  end
end
