require "rails_helper"

# Slice 1: editing a body notifies ONLY newly-added @mentions (diff old-vs-new). The
# create-time notify_mentions stays create-only; this is its update-time counterpart.
RSpec.describe "Hujah edit mentions", type: :model do
  let(:author) { create(:user) }
  let!(:alice) { create(:user, username: "alice") }
  let!(:bob) { create(:user, username: "bob") }

  it "notifies a newly-added mention on a body edit, not the pre-existing one" do
    hujah = author.hujahs.create!(body: "hello @alice what do you think")
    expect(Notification.where(user: alice, category: "mention", hujah_id: hujah.id).count).to eq(1)

    expect {
      hujah.update!(body: "hello @alice and also @bob now")
    }.to change { Notification.where(user: bob, category: "mention", hujah_id: hujah.id).count }.by(1)

    # alice already mentioned at create → NOT re-notified.
    expect(Notification.where(user: alice, category: "mention", hujah_id: hujah.id).count).to eq(1)
  end

  it "does not fire mention notifications when a vote touches the record (no body change)" do
    hujah = author.hujahs.create!(body: "hello @alice friend")
    voter = create(:user)
    expect {
      hujah.cast_vote(by: voter, choice: 1)
    }.not_to change { Notification.where(category: "mention").count }
  end

  it "does not fire when a body edit adds no new mentions" do
    hujah = author.hujahs.create!(body: "hello @alice friend")
    expect {
      hujah.update!(body: "hello @alice friend, revised wording here")
    }.not_to change { Notification.where(category: "mention").count }
  end
end
