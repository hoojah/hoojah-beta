require 'rails_helper'

RSpec.describe 'HTML voting', type: :request do
  let(:user) { create(:user) }
  let(:hujah) { create(:hujah, user: create(:user)) }

  it 'requires login' do
    post "/hoojah/#{hujah.slug}/votes", params: { vote: 1 }
    expect(response).to redirect_to(new_user_session_path)
  end

  it 'casts a vote and returns a turbo_stream replacing the vote bars' do
    sign_in user
    post "/hoojah/#{hujah.slug}/votes", params: { vote: 1 },
         headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
    expect(response.media_type).to eq('text/vnd.turbo-stream.html')
    expect(response.body).to include("turbo-stream action=\"replace\" target=\"#{dom_id(hujah, :vote_bars)}\"")
    expect(hujah.reload.agree_count).to eq(1)
  end
end
