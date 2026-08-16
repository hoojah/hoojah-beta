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

  throttle("login/ip", limit: 10, period: 1.minute) do |req|
    req.ip if req.path == "/login" && req.post?
  end
  throttle("login/email", limit: 5, period: 1.minute) do |req|
    if req.path == "/login" && req.post?
      req.params.dig("user", "email").to_s.downcase.presence
    end
  end
  throttle("signup/ip", limit: 5, period: 1.minute) do |req|
    req.ip if req.path == "/signup" && req.post?
  end
  throttle("password/ip", limit: 5, period: 1.minute) do |req|
    req.ip if req.path == "/password" && req.post?
  end
  throttle("votes/user", limit: 30, period: 1.minute) do |req|
    req.env["warden"]&.user&.id if req.path == "/api/v1/votes/create" && req.post?
  end
  throttle("compose/user", limit: 20, period: 1.minute) do |req|
    req.env["warden"]&.user&.id if req.path == "/hoojah" && req.post?
  end
  throttle("flags/user", limit: 15, period: 1.minute) do |req|
    if req.post? && req.path.match?(%r{\A/hoojah/[^/]+/flags\z})
      req.env["warden"]&.user&.id
    end
  end
  # Cap follow/unfollow churn per user — without it, cycling follow↔unfollow would
  # spam the target with `new_follower` notifications.
  throttle("follow/user", limit: 20, period: 1.minute) do |req|
    if req.path.match?(%r{\A/u/[^/]+/follow\z}) && (req.post? || req.delete?)
      req.env["warden"]&.user&.id
    end
  end
  # Cap block/unblock churn per user (Slice 7).
  throttle("block/user", limit: 20, period: 1.minute) do |req|
    if req.path.match?(%r{\A/u/[^/]+/block\z}) && (req.post? || req.delete?)
      req.env["warden"]&.user&.id
    end
  end
  # Cap challenge bursts per user — bounds cross-hoojah challenge spam (Slice 4).
  throttle("debates/challenge/user", limit: 10, period: 1.minute) do |req|
    if req.post? && req.path.match?(%r{\A/hoojah/[^/]+/debates\z})
      req.env["warden"]&.user&.id
    end
  end
  # Cap turn-posting bursts per user.
  throttle("debates/turns/user", limit: 20, period: 1.minute) do |req|
    if req.post? && req.path.match?(%r{\A/debates/[^/]+/turns\z})
      req.env["warden"]&.user&.id
    end
  end
  # Cap spectator verdict bursts per user (Slice 8).
  throttle("debate_verdicts/user", limit: 10, period: 1.minute) do |req|
    if req.post? && req.path.match?(%r{\A/debates/[^/]+/verdicts\z})
      req.env["warden"]&.user&.id
    end
  end
  # Cap round-extension bursts per user (Slice 9). extendable_by? already makes
  # every extend past the first at a given boundary a no-op 422, so this bounds
  # the cost of hammering the endpoint (each attempt takes a row lock), not the
  # rounds_limit itself.
  throttle("debate_extend/user", limit: 10, period: 1.minute) do |req|
    if req.post? && req.path.match?(%r{\A/debates/[^/]+/extend\z})
      req.env["warden"]&.user&.id
    end
  end
end
