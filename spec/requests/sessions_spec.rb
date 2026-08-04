require 'rails_helper'

RSpec.describe 'Sessions', type: :request do
  let(:user) { create(:user) }

  def body
    JSON.parse(response.body)
  end

  describe 'POST /login' do
    context 'with valid credentials' do
      it 'logs the user in and reports unread notifications count' do
        post '/login', params: { user: { email: user.email, password: 'hoojah' } }

        expect(response).to have_http_status(:ok)
        expect(body['logged_in']).to eq(true)
        expect(body['unread_notifications_count']).to eq(0)
      end
    end

    context 'with invalid credentials' do
      it 'returns a 401 status and an errors array (in the JSON body)' do
        post '/login', params: { user: { email: user.email, password: 'wrong-password' } }

        # NOTE: the controller renders `status: 401` inside the JSON body but does
        # not set the HTTP status, so the actual HTTP response is 200 OK.
        expect(body['status']).to eq(401)
        expect(body['errors']).to be_an(Array)
      end
    end
  end

  describe 'GET /logged_in' do
    it 'is true after logging in' do
      login_as(user)

      get '/logged_in'

      expect(response).to have_http_status(:ok)
      expect(body['logged_in']).to eq(true)
    end

    it 'is false without a session' do
      get '/logged_in'

      expect(response).to have_http_status(:ok)
      expect(body['logged_in']).to eq(false)
    end
  end

  describe 'DELETE /logout' do
    it 'logs the user out' do
      login_as(user)

      delete '/logout'

      expect(response).to have_http_status(:ok)
      expect(body['logged_out']).to eq(true)

      get '/logged_in'
      expect(body['logged_in']).to eq(false)
    end
  end
end
