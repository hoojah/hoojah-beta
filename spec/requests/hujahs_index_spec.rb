require 'rails_helper'

RSpec.describe 'Hujahs index', type: :request do
  it 'lists top-level hujahs and paginates via turbo_stream' do
    user = create(:user)
    create_list(:hujah, 20, user: user, parent_id: nil)
    get '/'
    expect(response).to have_http_status(:ok)
    expect(response.body.scan('data-testid="hujah-card"').size).to eq(15)

    get '/', params: { page: 2 }, headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
    expect(response.media_type).to eq('text/vnd.turbo-stream.html')
    expect(response.body).to include('turbo-stream action="append"')
  end
end
