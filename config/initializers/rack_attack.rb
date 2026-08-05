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

  throttle('login/ip', limit: 10, period: 1.minute) do |req|
    req.ip if req.path == '/login' && req.post?
  end
  throttle('login/email', limit: 5, period: 1.minute) do |req|
    if req.path == '/login' && req.post?
      req.params.dig('user', 'email').to_s.downcase.presence
    end
  end
  throttle('signup/ip', limit: 5, period: 1.minute) do |req|
    req.ip if req.path == '/signup' && req.post?
  end
  throttle('password/ip', limit: 5, period: 1.minute) do |req|
    req.ip if req.path == '/password' && req.post?
  end
  throttle('votes/user', limit: 30, period: 1.minute) do |req|
    req.env['warden']&.user&.id if req.path == '/api/v1/votes/create' && req.post?
  end
end
