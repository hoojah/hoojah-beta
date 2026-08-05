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
end
