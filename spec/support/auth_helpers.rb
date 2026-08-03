module AuthHelpers
  # Logs a user in via the real session flow. Factory users have password 'hoojah'.
  def login_as(user, password: 'hoojah')
    post '/login', params: { user: { email: user.email, password: password } }
    expect(response).to have_http_status(:ok)
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
end
