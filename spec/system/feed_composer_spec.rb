require "rails_helper"

RSpec.describe "Inline feed composer", :js do
  it "expands the pill and posts a hoojah" do
    sign_in create(:user)
    visit root_path
    find('[data-composer-target="collapsed"]').click
    fill_in "hujah[body]", with: "Inline composed claim about buses"
    within('[data-composer-target="expanded"]') { click_on "Post" }
    expect(page).to have_content("Inline composed claim about buses")
  end
end
