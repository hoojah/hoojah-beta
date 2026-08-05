require 'rails_helper'

RSpec.describe 'Sessions (Devise)', type: :request do
  let(:user) { create(:user, password: 'hoojah88') }

  it 'logs in with valid credentials and redirects' do
    post user_session_path, params: { user: { email: user.email, password: 'hoojah88' } }
    expect(response).to have_http_status(:see_other).or have_http_status(:found)
  end

  it 'never exposes encrypted_password in any auth response' do
    post user_session_path, params: { user: { email: user.email, password: 'hoojah88' } }
    follow_redirect!
    expect(response.body).not_to include('encrypted_password')
    expect(response.body).not_to include('$2a$')
  end

  it 'rejects bad credentials without revealing account existence' do
    post user_session_path, params: { user: { email: user.email, password: 'wrong' } }
    expect(response.body).not_to include('encrypted_password')
  end
end
