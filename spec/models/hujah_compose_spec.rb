require "rails_helper"

RSpec.describe "Hujah response notification", type: :model do
  it "notifies the parent owner on a reply, once" do
    owner = create(:user)
    replier = create(:user)
    parent = create(:hujah, user: owner)
    expect {
      replier.hujahs.create!(body: "reply", parent_id: parent.id, vote: 1)
    }.to change { Notification.where(user: owner, category: "new_hoojah_response").count }.by(1)
  end

  it "does not notify for a top-level hoojah" do
    expect { create(:hujah, parent_id: nil) }
      .not_to change { Notification.where(category: "new_hoojah_response").count }
  end
end
