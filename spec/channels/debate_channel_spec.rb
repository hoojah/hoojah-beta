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

  # 2026 (Task 3.5): the spectator view keeps a LIVE transcript, so an active debate's
  # Cable stream now mirrors DebatePolicy#show? exactly — a visible spectator (or a
  # logged-out visitor) can subscribe, same as they already could once concluded. A
  # participant is hidden (blocked/private) is the one thing that still rejects.
  context "an ACTIVE debate with both participants visible" do
    let(:debate) { create(:debate, challenger:, opponent:, status: :active) }

    it "confirms the subscription for a participant" do
      stub_connection current_user: challenger
      subscribe_to(debate)
      expect(subscription).to be_confirmed
    end

    it "confirms for a non-participant spectator" do
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

  context "an ACTIVE debate with a private participant" do
    let(:debate) do
      challenger.update!(private: true)
      create(:debate, challenger:, opponent:, status: :active)
    end

    it "rejects a non-participant who cannot see the private participant" do
      stub_connection current_user: outsider
      subscribe_to(debate)
      expect(subscription).to be_rejected
    end

    it "still confirms for a participant" do
      stub_connection current_user: challenger
      subscribe_to(debate)
      expect(subscription).to be_confirmed
    end
  end

  context "a PENDING debate" do
    let(:debate) { create(:debate, challenger:, opponent:, status: :pending) }

    it "rejects a non-participant — no spectator layout exists for a pending challenge" do
      stub_connection current_user: outsider
      subscribe_to(debate)
      expect(subscription).to be_rejected
    end

    it "confirms for a participant" do
      stub_connection current_user: challenger
      subscribe_to(debate)
      expect(subscription).to be_confirmed
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
