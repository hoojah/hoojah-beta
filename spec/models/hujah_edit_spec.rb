require "rails_helper"

RSpec.describe "Hujah body edit rules", type: :model do
  let(:owner) { create(:user) }

  it "is editable for a fresh, active, conviction-free hoojah" do
    hujah = create(:hujah, user: owner)
    expect(hujah.body_editable?).to be(true)
  end

  it "is not editable once the 15-minute window has passed" do
    hujah = create(:hujah, user: owner, created_at: 16.minutes.ago)
    expect(hujah.body_editable?).to be(false)
  end

  it "is not editable once any conviction has been cast" do
    hujah = create(:hujah, user: owner, conviction_count: 1)
    expect(hujah.body_editable?).to be(false)
  end

  it "is not editable when the hoojah has been moderator-removed" do
    hujah = create(:hujah, user: owner, moderation_status: :removed)
    expect(hujah.body_editable?).to be(false)
  end

  it "is editable for a reply (child) within the window" do
    parent = create(:hujah)
    reply = create(:hujah, user: owner, parent: parent, body: "Agreed with this")
    expect(reply.body_editable?).to be(true)
  end

  it "stamps body_edited_at only when the body text changes" do
    hujah = create(:hujah, user: owner)
    expect(hujah.body_edited_at).to be_nil
    expect(hujah.body_edited?).to be(false)

    hujah.update!(body: "A materially different claim body here")

    expect(hujah.body_edited_at).to be_present
    expect(hujah.body_edited?).to be(true)
  end

  it "does not stamp body_edited_at when a vote touches the record" do
    hujah = create(:hujah, user: owner)
    voter = create(:user)
    expect {
      hujah.cast_vote(by: voter, choice: 1)
    }.not_to change { hujah.reload.body_edited_at }
  end
end
