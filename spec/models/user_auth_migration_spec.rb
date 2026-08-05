require 'rails_helper'

RSpec.describe 'users schema (post-Devise migration)', type: :model do
  it 'has encrypted_password and a valid unique email index' do
    cols = User.column_names
    expect(cols).to include('encrypted_password', 'reset_password_token', 'remember_created_at')
    expect(cols).not_to include('password_digest')

    idx = ActiveRecord::Base.connection.execute(<<~SQL).to_a
      SELECT indisvalid FROM pg_index i
      JOIN pg_class c ON c.oid = i.indexrelid
      WHERE c.relname = 'index_users_on_email'
    SQL
    expect(idx.first['indisvalid']).to be(true)
  end
end
