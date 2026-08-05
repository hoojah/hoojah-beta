require "rails_helper"

RSpec.describe ApplicationCable::Connection, type: :channel do
  # rspec-rails 7.1 has no :connection example group, so mix in ActionCable's own
  # connection test behavior (gives us `connect`/`connection`) and name the
  # connection under test.
  include ActionCable::Connection::TestCase::Behavior

  tests ApplicationCable::Connection

  let(:user) { create(:user) }

  it "identifies current_user from the Warden session" do
    warden = instance_double(Warden::Proxy)
    allow(warden).to receive(:user).with(scope: :user).and_return(user)

    connect env: {"warden" => warden}

    expect(connection.current_user).to eq(user)
  end

  it "rejects when Warden has no authenticated user" do
    warden = instance_double(Warden::Proxy)
    allow(warden).to receive(:user).with(scope: :user).and_return(nil)

    expect { connect env: {"warden" => warden} }
      .to raise_error(ActionCable::Connection::Authorization::UnauthorizedError)
  end

  it "rejects when Warden is absent entirely" do
    expect { connect }
      .to raise_error(ActionCable::Connection::Authorization::UnauthorizedError)
  end
end
