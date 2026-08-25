require "rails_helper"

RSpec.describe "Notifications filtered-empty copy", type: :request do
  it "says no mentions when the Mentions filter is empty" do
    sign_in create(:user)
    get notifications_path(filter: "mentions")
    expect(response.body).to include("No mentions yet")
  end

  it "says no debate activity when the Debates filter is empty" do
    sign_in create(:user)
    get notifications_path(filter: "debates")
    expect(response.body).to include("No debate activity yet")
  end

  it "says you have no notifications on the unfiltered empty list" do
    sign_in create(:user)
    get notifications_path
    expect(response.body).to include("You have no notifications")
  end
end
