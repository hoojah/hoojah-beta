class Rack::Attack
  # Use the app cache as the throttle store. In production Rails.cache is the
  # Solid Cache store (see config/environments/production.rb); in test the app
  # cache is :null_store (which cannot count), so use an in-process MemoryStore
  # there so throttles actually accumulate.
  cache.store =
    if Rails.env.test?
      ActiveSupport::Cache::MemoryStore.new
    else
      Rails.cache
    end

  # --- Path matching ---------------------------------------------------------
  #
  # Rails appends an optional `(.:format)` to EVERY route it draws, and
  # Rack::Request#path returns the raw request path with that suffix still
  # attached. A matcher anchored on the bare path therefore does NOT match
  # `POST /login.json` or `POST /debates/x/extend.turbo_stream` — both of which
  # route to the very same controller action — so the request was served in full
  # with no throttle applied. That held for all twelve throttles below, including
  # the auth ones: 11 × `POST /login.json` each returned 401, i.e. eleven real
  # credential checks, no 429.
  #
  # Build EVERY matcher through this helper so a newly added throttle cannot
  # reintroduce the gap. Literal segments are passed as strings (and escaped, so
  # a segment is never reinterpreted as a pattern); dynamic route segments
  # (`:slug`, `:username`) are passed as ANY_SEGMENT.
  #
  # The suffix group is `[^/]+` rather than `\w+` deliberately: over-matching a
  # path Rails would not actually route costs nothing (throttling a 404 is fine),
  # whereas under-matching is the bug being fixed.
  ANY_SEGMENT = Object.new

  def self.throttled_path(*segments)
    body = segments.map { |s| s.equal?(ANY_SEGMENT) ? "[^/]+" : Regexp.escape(s) }.join("/")
    %r{\A/#{body}(\.[^/]+)?\z}
  end

  LOGIN_PATH = throttled_path("login")
  # `devise_for path: ""` puts registrations#create at the ROOT: `POST /`.
  # `/signup` is only the GET form, so the previous `req.path == "/signup" &&
  # req.post?` matcher could never fire and account creation was entirely
  # unthrottled — a separate defect from the format suffix, and a worse one.
  SIGNUP_PATH = throttled_path
  PASSWORD_PATH = throttled_path("password")
  VOTES_PATH = throttled_path("api", "v1", "votes", "create")
  COMPOSE_PATH = throttled_path("hoojah")
  FLAGS_PATH = throttled_path("hoojah", ANY_SEGMENT, "flags")
  FOLLOW_PATH = throttled_path("u", ANY_SEGMENT, "follow")
  BLOCK_PATH = throttled_path("u", ANY_SEGMENT, "block")
  CHALLENGE_PATH = throttled_path("hoojah", ANY_SEGMENT, "debates")
  TURNS_PATH = throttled_path("debates", ANY_SEGMENT, "turns")
  VERDICTS_PATH = throttled_path("debates", ANY_SEGMENT, "verdicts")
  EXTEND_PATH = throttled_path("debates", ANY_SEGMENT, "extend")

  # --- Throttles -------------------------------------------------------------

  throttle("login/ip", limit: 10, period: 1.minute) do |req|
    req.ip if req.post? && req.path.match?(LOGIN_PATH)
  end
  throttle("login/email", limit: 5, period: 1.minute) do |req|
    if req.post? && req.path.match?(LOGIN_PATH)
      req.params.dig("user", "email").to_s.downcase.presence
    end
  end
  throttle("signup/ip", limit: 5, period: 1.minute) do |req|
    req.ip if req.post? && req.path.match?(SIGNUP_PATH)
  end
  throttle("password/ip", limit: 5, period: 1.minute) do |req|
    req.ip if req.post? && req.path.match?(PASSWORD_PATH)
  end
  throttle("votes/user", limit: 30, period: 1.minute) do |req|
    req.env["warden"]&.user&.id if req.post? && req.path.match?(VOTES_PATH)
  end
  throttle("compose/user", limit: 20, period: 1.minute) do |req|
    req.env["warden"]&.user&.id if req.post? && req.path.match?(COMPOSE_PATH)
  end
  throttle("flags/user", limit: 15, period: 1.minute) do |req|
    req.env["warden"]&.user&.id if req.post? && req.path.match?(FLAGS_PATH)
  end
  # Cap follow/unfollow churn per user — without it, cycling follow↔unfollow would
  # spam the target with `new_follower` notifications.
  throttle("follow/user", limit: 20, period: 1.minute) do |req|
    if (req.post? || req.delete?) && req.path.match?(FOLLOW_PATH)
      req.env["warden"]&.user&.id
    end
  end
  # Cap block/unblock churn per user (Slice 7).
  throttle("block/user", limit: 20, period: 1.minute) do |req|
    if (req.post? || req.delete?) && req.path.match?(BLOCK_PATH)
      req.env["warden"]&.user&.id
    end
  end
  # Cap challenge bursts per user — bounds cross-hoojah challenge spam (Slice 4).
  throttle("debates/challenge/user", limit: 10, period: 1.minute) do |req|
    req.env["warden"]&.user&.id if req.post? && req.path.match?(CHALLENGE_PATH)
  end
  # Cap turn-posting bursts per user.
  throttle("debates/turns/user", limit: 20, period: 1.minute) do |req|
    req.env["warden"]&.user&.id if req.post? && req.path.match?(TURNS_PATH)
  end
  # Cap spectator verdict bursts per user (Slice 8).
  throttle("debate_verdicts/user", limit: 10, period: 1.minute) do |req|
    req.env["warden"]&.user&.id if req.post? && req.path.match?(VERDICTS_PATH)
  end
  # Cap round-extension bursts per user (Slice 9). extendable_by? already makes
  # every extend past the first at a given boundary a no-op 422, so this bounds
  # the cost of hammering the endpoint (each attempt takes a row lock), not the
  # rounds_limit itself.
  throttle("debate_extend/user", limit: 10, period: 1.minute) do |req|
    req.env["warden"]&.user&.id if req.post? && req.path.match?(EXTEND_PATH)
  end
end
