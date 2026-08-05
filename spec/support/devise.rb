module SystemAuthHelpers
  # Warden-backed login for cuprite system specs (no real POST — the request
  # spec `login_as` override only applies to type: :request).
  def login_as_system(user)
    login_as(user, scope: :user)
  end
end

RSpec.configure do |config|
  config.include Warden::Test::Helpers
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include Devise::Test::IntegrationHelpers, type: :system
  config.include SystemAuthHelpers, type: :system
  config.after(:each) { Warden.test_reset! }
end
