require "rails_helper"

RSpec.describe "Email notification preference", type: :request do
  let(:owner) { create(:user, username: "owner", email_notifications: true) }

  # (h) The owner can turn the preference off through the profile-edit PATCH.
  it "persists email_notifications = false for the owner" do
    sign_in owner
    patch "/u/owner", params: {user: {email_notifications: "0"}}

    expect(owner.reload.email_notifications).to be(false)
  end

  it "persists email_notifications = true when re-enabled" do
    owner.update!(email_notifications: false)
    sign_in owner
    patch "/u/owner", params: {user: {email_notifications: "1"}}

    expect(owner.reload.email_notifications).to be(true)
  end

  # A different signed-in user cannot flip the owner's preference — UserPolicy#update?
  # gates it and Pundit redirects.
  it "forbids a different user from changing the preference" do
    owner # ensure the target exists before the stranger PATCHes it
    stranger = create(:user, username: "stranger")
    sign_in stranger
    patch "/u/owner", params: {user: {email_notifications: "0"}}

    expect(response).to have_http_status(:found).or have_http_status(:see_other)
    expect(owner.reload.email_notifications).to be(true)
  end

  # The edit dialog renders the checkbox so the owner can reach the toggle.
  it "renders the email-notifications checkbox in the edit dialog" do
    sign_in owner
    get "/u/owner/edit"

    expect(response.body).to include("user[email_notifications]")
  end
end
