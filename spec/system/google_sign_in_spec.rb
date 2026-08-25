require "rails_helper"

RSpec.describe "Sign in with Google", type: :system, js: true do
  it "shows the button on login and signs the user in" do
    mock_google_auth(email: "sys.oauth@gmail.com", uid: "sys1", name: "Sys Oauth")
    OmniAuth.config.test_mode = true

    visit "/login"
    expect(page).to have_button("Continue with Google").or have_link("Continue with Google")
    click_on "Continue with Google"

    expect(page).to have_current_path(root_path).or have_current_path(dashboard_path)
    expect(User.find_by(uid: "sys1")).to be_present
  end

  it "shows the button on signup" do
    visit "/signup"
    expect(page).to have_button("Continue with Google").or have_link("Continue with Google")
  end
end
