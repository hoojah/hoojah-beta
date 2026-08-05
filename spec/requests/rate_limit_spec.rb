require 'rails_helper'

RSpec.describe 'Rate limiting', type: :request do
  before { Rack::Attack.enabled = true; Rack::Attack.reset! }
  after  { Rack::Attack.enabled = false }

  it 'throttles repeated failed logins from one IP' do
    11.times { post '/login', params: { user: { email: 'x@x.com', password: 'nope' } } }
    expect(response).to have_http_status(:too_many_requests)
  end
end
