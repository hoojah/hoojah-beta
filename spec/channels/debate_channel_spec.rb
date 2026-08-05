require "rails_helper"

RSpec.describe DebateChannel, type: :channel do
  let(:challenger) { create(:user) }
  let(:opponent) { create(:user) }
  let(:outsider) { create(:user) }

  # turbo_stream_from @debate signs the debate's to_gid_param; the channel
  # re-derives the Debate from that verified name and re-checks DebatePolicy#show?.
  def subscribe_to(debate)
    subscribe(signed_stream_name: Turbo::StreamsChannel.signed_stream_name(debate))
  end

  context "an ACTIVE debate" do
    let(:debate) { create(:debate, challenger:, opponent:, status: :active) }

    it "confirms the subscription for a participant" do
      stub_connection current_user: challenger
      subscribe_to(debate)
      expect(subscription).to be_confirmed
    end

    it "rejects a non-participant" do
      stub_connection current_user: outsider
      subscribe_to(debate)
      expect(subscription).to be_rejected
    end

    it "rejects a logged-out visitor" do
      stub_connection current_user: nil
      subscribe_to(debate)
      expect(subscription).to be_rejected
    end
  end

  context "a CONCLUDED debate with both participants visible" do
    let(:debate) { create(:debate, challenger:, opponent:, status: :concluded) }

    it "confirms for a non-participant" do
      stub_connection current_user: outsider
      subscribe_to(debate)
      expect(subscription).to be_confirmed
    end

    it "confirms for a logged-out visitor" do
      stub_connection current_user: nil
      subscribe_to(debate)
      expect(subscription).to be_confirmed
    end
  end

  it "rejects a tampered / unsigned stream name" do
    stub_connection current_user: challenger
    subscribe(signed_stream_name: "not-a-signed-name")
    expect(subscription).to be_rejected
  end
end
