require "rails_helper"

RSpec.describe "Profile empty states", type: :request do
  it "offers the owner a first-run CTA on an empty Hoojahs tab" do
    user = create(:user)
    sign_in user
    get profile_path(user.username)
    expect(response.body).to include("No hoojahs yet")
    expect(response.body).to include("Post your first hoojah")
    expect(response.body).to include(new_hujah_path)
  end

  it "does not show the CTA to a visitor viewing an empty profile" do
    owner = create(:user)
    sign_in create(:user)
    get profile_path(owner.username)
    expect(response.body).to include("No hoojahs yet")
    expect(response.body).not_to include("Post your first hoojah")
  end
end
