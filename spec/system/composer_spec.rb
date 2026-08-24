require "rails_helper"

RSpec.describe "New hoojah composer", :js do
  it "keeps Post disabled under 8 chars and enables past it" do
    sign_in create(:user)
    visit new_hujah_path
    expect(page).to have_button("Post", disabled: true)
    fill_in "hujah[body]", with: "Public transport should be free"
    expect(page).to have_button("Post", disabled: false)
  end

  it "sets visibility via the dropdown and posts it" do
    sign_in create(:user)
    visit new_hujah_path
    fill_in "hujah[body]", with: "A claim long enough to submit here"
    # Visibility is now a native <select> (JS-off safe), the canonical hujah[visibility].
    select "Private", from: "hujah[visibility]"
    click_on "Post"
    expect(Hujah.order(:created_at).last.visibility).to eq "private_only"
  end
end
