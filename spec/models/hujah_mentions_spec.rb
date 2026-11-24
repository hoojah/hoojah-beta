require "rails_helper"

RSpec.describe "Hujah mentions", type: :model do
  let(:author) { create(:user) }
  let(:m1) { create(:user, username: "mentioned1") }

  it "notifies each existing mentioned user once, skips self + unknown, caps at 10" do
    create(:user, username: "self") # ensure username uniqueness helper if needed
    expect {
      author.hujahs.create!(body: "hey @mentioned1 @mentioned1 @nobody @#{author.username}")
    }.to change { Notification.where(user: m1, category: "mention").count }.by(1)
    expect(Notification.where(category: "mention", subject_user_id: author.id).count).to eq(1)
  end

  describe "visibility of the mentioned user" do
    let(:outsider) { create(:user, username: "outsider") }

    it "does not notify a non-follower mentioned in a followers-only hoojah" do
      expect {
        author.hujahs.create!(body: "hi @outsider", visibility: :followers_only)
      }.not_to change { Notification.where(user: outsider, category: "mention").count }
    end

    it "does not notify a non-follower mentioned by a private author" do
      author.update!(private: true)
      expect {
        author.hujahs.create!(body: "hi @outsider")
      }.not_to change { Notification.where(user: outsider, category: "mention").count }
    end

    it "still notifies an accepted follower mentioned in a followers-only hoojah" do
      create(:follow, follower: outsider, followed: author, status: :accepted)
      expect {
        author.hujahs.create!(body: "hi @outsider", visibility: :followers_only)
      }.to change { Notification.where(user: outsider, category: "mention").count }.by(1)
    end

    it "still notifies a mentioned user in a public hoojah" do
      expect {
        author.hujahs.create!(body: "hi @outsider", visibility: :visible_public)
      }.to change { Notification.where(user: outsider, category: "mention").count }.by(1)
    end
  end
end
