# Prosopite — N+1 query detection, LOG ONLY.
#
# The N+1 audit has been deferred since Slice 2. Slice 10 closed it by making
# detection *ambient* rather than a slice of its own: prosopite watches every
# development request and every test example, writes what it finds to
# log/prosopite.log, and never — under any configuration reachable from here —
# raises or fails a build. A detector that can turn a green suite red is a
# detector someone eventually deletes.
#
# Every knob is set explicitly rather than left to its default. `raise` in
# particular already defaults to false; it is stated anyway because that one
# default is the whole safety property, and defaults drift between versions.
#
# The gem lives in `group :development, :test`, so the constant does not exist in
# production. Guard first, configure second.
unless Rails.env.production?
  Prosopite.enabled = true

  # Never raise. Not in test, not in development, not behind a flag.
  Prosopite.raise = false

  # 2 is prosopite's own default. Restated so a future reader knows the threshold
  # was considered and kept, not merely inherited.
  Prosopite.min_n_queries = 2

  # A dedicated log file (log/ is gitignored) in both environments. N+1 reports are
  # long, multi-line and stack-trace-heavy; in a shared log they are unreadable and
  # in a suite run they scroll past. `grep -c 'N+1 queries detected' log/prosopite.log`
  # after a run is the intended workflow.
  Prosopite.prosopite_logger = true

  # Development additionally mirrors into the server log, because that is where a
  # developer is already looking while clicking through a page. Test deliberately
  # does not: prosopite colour-codes its warnings red, and red multi-line output
  # interleaved with RSpec's progress dots reads as a failure when it is not one.
  Prosopite.rails_logger = Rails.env.development?
  Prosopite.stderr_logger = false
  Prosopite.custom_logger = false

  if Rails.env.test?
    # Noise floor for the suite. `allow_stack_paths` matches *any* frame of the
    # query's call stack, which makes these safe to list: a SELECT issued by a
    # controller under test has no factory_bot frame on its stack, so real findings
    # survive while fixture setup is filtered out. Without this the log describes
    # the factories rather than the application.
    #
    # (Prosopite already ignores non-SELECT statements and uniqueness-validation
    # lookups by default, which removes most of the rest of the fixture noise.)
    Prosopite.allow_stack_paths = ["factory_bot", "spec/factories", "spec/support"]
  end

  if Rails.env.development?
    # Per-request scanning in development only. The test environment does NOT use
    # this middleware: prosopite's scan state lives in Thread.current, the RSpec
    # hooks in spec/support/prosopite.rb already wrap each example on that same
    # thread, and the middleware's `ensure Prosopite.finish` would close the
    # example's scan at the end of the first request it served.
    require "prosopite/middleware/rack"
    Rails.application.config.middleware.use(Prosopite::Middleware::Rack)
  end
end
