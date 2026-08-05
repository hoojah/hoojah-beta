require 'rails_helper'

RSpec.describe User, type: :model do
  it 'authenticates a pre-existing bcrypt password via Devise (no re-hash)' do
    user = User.create!(full_name: 'A', username: 'a_user', email: 'A@X.com', password: 'hoojah88')
    expect(user.email).to eq('a@x.com')                       # downcased
    expect(user.valid_password?('hoojah88')).to be(true)       # Devise validates
    expect(user).to respond_to(:reset_password_token)
  end

  it 'still requires a unique username' do
    User.create!(full_name: 'A', username: 'dup', email: 'a@x.com', password: 'hoojah88')
    dup = User.new(full_name: 'B', username: 'dup', email: 'b@x.com', password: 'hoojah88')
    expect(dup).not_to be_valid
  end

  it 'assigns a random photo after create' do
    user = User.create!(full_name: 'A', username: 'ph', email: 'ph@x.com', password: 'hoojah88')
    expect(user.photo).to be_present
  end
end
