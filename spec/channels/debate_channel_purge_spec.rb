require "rails_helper"

RSpec.describe DebateChannel, type: :channel do
  let(:owner) { create(:user, username: "owner") }
  let(:spectator) { create(:user, username: "spectator") }
  let(:foe) { create(:user, username: "foe") }

  def subscribe_to(debate)
    subscribe(signed_stream_name: Turbo::StreamsChannel.signed_stream_name(debate))
  end

  it "stops streaming an active debate to a spectator purged by a visibility tighten" do
    hujah = create(:hujah, user: owner, visibility: :visible_public)
    debate = create(:debate, hujah: hujah, challenger: owner, opponent: foe, status: :active)

    hujah.cast_vote(by: spectator, choice: 1)
    stub_connection current_user: spectator
    subscribe_to(debate)
    expect(subscription).to be_confirmed

    VisibilityChange.new(hujah, to: "private_only").apply!
    stub_connection current_user: User.find(spectator.id)
    subscribe_to(debate)
    expect(subscription).to be_rejected
  end
end
