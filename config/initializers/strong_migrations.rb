# strong_migrations is `group :development, :test` in the Gemfile, but initializers
# run in EVERY environment. Without this guard, production boot raises
# `NameError: uninitialized constant StrongMigrations` on line 1 of the body — which
# means nothing boots in production: not the server, not `db:migrate`, and not
# `assets:precompile` (so the deploy fails at build time, before it can even fail at
# runtime). This app was upgraded from Rails 6 and had never been booted in
# production, which is why it went unnoticed until Slice 10b.
#
# Do NOT remove the guard as "dead code" — it is only dead in dev/test, which is the
# only place anyone reads it. Removing it breaks every production build.
if defined?(StrongMigrations)
  # Mark existing migrations as safe
  StrongMigrations.start_after = 20260805032149

  # Set timeouts for migrations
  # If you use PgBouncer in transaction mode, delete these lines and set timeouts on the database user
  StrongMigrations.lock_timeout = 10.seconds
  StrongMigrations.statement_timeout = 1.hour

  # Analyze tables after indexes are added
  # Outdated statistics can sometimes hurt performance
  StrongMigrations.auto_analyze = true

  # Set the version of the production database
  # so the right checks are run in development
  # StrongMigrations.target_version = 18

  # Add custom checks
  # StrongMigrations.add_check do |method, args|
  #   if method == :add_index && args[0].to_s == "users"
  #     stop! "No more indexes on the users table"
  #   end
  # end

  # Remove invalid indexes when rerunning migrations
  # StrongMigrations.remove_invalid_indexes = true

  # Make some operations safe by default
  # See https://github.com/ankane/strong_migrations#safe-by-default
  # StrongMigrations.safe_by_default = true
end
