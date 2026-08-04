require 'rails_helper'

RSpec.describe 'Api::V1::Votes', type: :request do
  let(:user) { create(:user) }
  let(:hujah) { create(:hujah) }

  describe 'POST /api/v1/votes/create' do
    it 'records a new vote and increments the agree counter' do
      expect {
        post '/api/v1/votes/create',
             params: { vote: 1, hujah_id: hujah.id, user_id: user.id },
             as: :json
      }.to change(Vote, :count).by(1)

      expect(hujah.reload.agree_count).to eq(1)
    end

    it 'appends a subsequent vote to the same vote record' do
      post '/api/v1/votes/create',
           params: { vote: 1, hujah_id: hujah.id, user_id: user.id },
           as: :json

      post '/api/v1/votes/create',
           params: { vote: 3, hujah_id: hujah.id, user_id: user.id },
           as: :json

      vote = Vote.find_by(user_id: user.id, hujah_id: hujah.id)
      expect(vote.vote.last).to eq(3)
    end
  end
end
