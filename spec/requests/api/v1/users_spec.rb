require 'rails_helper'

RSpec.describe 'Api::V1::Users', type: :request do
  let(:user) { create(:user) }

  def body
    JSON.parse(response.body)
  end

  describe 'GET /api/v1/:username' do
    it 'returns the user profile' do
      get "/api/v1/#{user.username}"

      expect(response).to have_http_status(:ok)
      expect(body['data']['attributes']['username']).to eq(user.username)
    end
  end

  describe 'POST /api/v1/:username/update' do
    it 'updates the current user headline' do
      login_as(user)

      post "/api/v1/#{user.username}/update", params: { headline: 'New headline' }

      expect(response).to have_http_status(:ok)
      expect(user.reload.headline).to eq('New headline')
    end

    # The controller reads flat params (params.permit), not params.require(:user),
    # so an id-reassignment attack injects :id at the top level. This asserts the
    # core invariant: an injected :id cannot reassign the record's primary key.
    it 'ignores an injected :id on update (no mass-assignment)' do
      user = create(:user)
      sign_in user
      other_id = create(:user).id
      post "/api/v1/#{user.username}/update",
           params: { id: other_id, full_name: 'New Name' }, as: :json
      expect(user.reload.id).not_to eq(other_id)
    end
  end
end
