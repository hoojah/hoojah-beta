require 'rails_helper'

RSpec.describe 'Api::V1::Hujahs', type: :request do
  let(:user) { create(:user) }

  def body
    JSON.parse(response.body)
  end

  describe 'GET /api/v1/hoojah/index' do
    it 'returns all hoojahs in the data array' do
      create_list(:hujah, 2)

      get '/api/v1/hoojah/index'

      expect(response).to have_http_status(:ok)
      expect(body['data']).to be_an(Array)
      # The index returns every Hujah in the database. The test DB carries a
      # small amount of pre-existing (committed) seed data, so we characterize
      # against the true total rather than the two just-created records.
      expect(body['data'].size).to eq(Hujah.count)
      expect(body['data'].size).to be >= 2
    end
  end

  describe 'GET /api/v1/hoojah/:slug' do
    it 'returns the matching hoojah by slug' do
      hujah = create(:hujah)

      get "/api/v1/hoojah/#{hujah.slug}"

      expect(response).to have_http_status(:ok)
      expect(body['data']['attributes']['slug']).to eq(hujah.slug)
    end
  end

  describe 'POST /api/v1/hoojah/create' do
    it 'creates a hoojah owned by the current user' do
      login_as(user)

      expect {
        post '/api/v1/hoojah/create', params: { body: 'A brand new hoojah' }
      }.to change(Hujah, :count).by(1)

      expect(Hujah.last.user).to eq(user)
    end
  end

  describe 'DELETE /api/v1/hoojah/destroy/:slug' do
    it 'deletes the hoojah and returns a confirmation message' do
      hujah = create(:hujah)

      expect {
        delete "/api/v1/hoojah/destroy/#{hujah.slug}"
      }.to change(Hujah, :count).by(-1)

      expect(body['message']).to eq('Hoojah deleted!')
    end
  end
end
