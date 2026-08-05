module AuthHelpers
  # Devise/Warden login for request specs. Factory users have password 'hoojah88'.
  #
  # This method is prepended so the real-POST variant wins for `login_as(user)`.
  # Devise::Test::IntegrationHelpers#sign_in, however, delegates to Warden's
  # `login_as(resource, scope:)`; when called with a :scope keyword we defer to
  # that (super) so `sign_in` keeps working alongside this helper.
  def login_as(user, password: 'hoojah88', **options)
    return super(user, **options) if options.key?(:scope)

    login_params = { user: { email: user.email, password: password } }
    post user_session_path, params: login_params
    expect(response).to have_http_status(:see_other).or have_http_status(:found)
  end
end

RSpec.configure do |config|
  # prepend (not include) so this real-POST login_as wins over
  # Warden::Test::Helpers#login_as, which Devise::Test::IntegrationHelpers mixes in.
  config.prepend AuthHelpers, type: :request
end
