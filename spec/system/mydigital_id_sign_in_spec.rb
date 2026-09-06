require "rails_helper"

RSpec.describe "MyDigital ID sign-in", type: :system, js: true do
  around do |example|
    prev = ENV["MYID_BASE_URL"]
    ENV["MYID_BASE_URL"] = "https://sso.example.gov.my"
    example.run
    ENV["MYID_BASE_URL"] = prev
  end

  it "creates an account + identity via the interstitial" do
    mock_mydigital_id_auth(sub: "sub-sys", name: "Ali bin Abu")
    visit "/login"
    expect(page).to have_button("Continue with MyDigital ID")
    click_button "Continue with MyDigital ID"

    # The callback stashes the unknown sub and full-page-redirects here.
    expect(page).to have_content("Welcome via MyDigital ID")
    fill_in "username", with: "systemuser"
    click_button "Create account and continue"

    # The interstitial POST creates the account + identity for the pending sub.
    # NOTE: finish_linked's redirect omits status: :see_other, so Turbo does not
    # navigate the browser after the POST (see the DONE_WITH_CONCERNS note). There is
    # therefore no page transition to synchronise on — wait on the DB write instead.
    user = wait_for { User.find_by(username: "systemuser") }
    expect(user.identities.pluck(:provider, :uid)).to eq([["my_digital_id", "sub-sys"]])
  end

  it "renders the public notice" do
    visit "/mydigital-id"
    expect(page).to have_content("One identity, one account")
  end

  # Poll until the block returns a truthy value or Capybara's wait window elapses.
  # Used because the async interstitial POST commits without a page transition to
  # anchor Capybara's own synchronisation on.
  def wait_for
    result = nil
    Timeout.timeout(Capybara.default_max_wait_time) do
      loop do
        result = yield
        break if result
        sleep 0.05
      end
    end
    result
  end
end
