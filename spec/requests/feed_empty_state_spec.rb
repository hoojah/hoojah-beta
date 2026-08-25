require "rails_helper"

RSpec.describe "Feed empty states", type: :request do
  it "prompts an anonymous visitor to sign up when there are no hoojahs" do
    get root_path
    expect(response.body).to include("No hoojahs yet")
    expect(response.body).to include(new_user_registration_path)
  end

  it "prompts a signed-in user to post the first hoojah when the feed is empty" do
    user = create(:user)
    sign_in user
    get root_path
    expect(response.body).to include("No hoojahs yet")
    expect(response.body).to include(new_hujah_path)
  end

  it "shows the reworded Following-empty copy without misdirection" do
    user = create(:user)
    sign_in user
    get root_path(filter: "following")
    expect(response.body).to include("When people you follow post")
  end
end
