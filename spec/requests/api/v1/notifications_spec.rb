require 'rails_helper'

RSpec.describe 'Api::V1::Notifications', type: :request do
  let(:user) { create(:user) }

  def body
    JSON.parse(response.body)
  end

  let!(:notification) do
    Notification.create!(user_id: user.id, category: :announcement, read: false)
  end

  describe 'GET /api/v1/:username/notifications' do
    it 'returns the user notifications' do
      get "/api/v1/#{user.username}/notifications"

      expect(response).to have_http_status(:ok)
      expect(body['data']).to be_an(Array)
      expect(body['data'].size).to eq(1)
    end
  end

  describe 'PUT /api/v1/:username/notifications/:id' do
    it 'marks the notification as read' do
      put "/api/v1/#{user.username}/notifications/#{notification.id}",
          params: { notification: { read: true } }

      expect(response).to have_http_status(200)
      expect(notification.reload.read).to eq(true)
    end
  end

  describe 'DELETE /api/v1/:username/notifications/:id' do
    it 'deletes the notification' do
      expect {
        delete "/api/v1/#{user.username}/notifications/#{notification.id}"
      }.to change(Notification, :count).by(-1)

      expect(response).to have_http_status(200)
    end
  end
end
