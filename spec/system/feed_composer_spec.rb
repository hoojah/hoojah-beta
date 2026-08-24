require "rails_helper"

RSpec.describe "Inline feed composer", :js do
  it "restyles the collapsed pill and expanded card as rounded-2xl surfaces" do
    sign_in create(:user)
    visit root_path
    expect(page).to have_css('[data-composer-target="collapsed"].rounded-2xl')
    find('[data-composer-target="collapsed"]').click
    expect(page).to have_css('[data-composer-target="expanded"].rounded-2xl')
  end

  it "plays the hrise expand animation while keeping JS-off safety intact" do
    sign_in create(:user)
    visit root_path
    find('[data-composer-target="collapsed"]').click
    expect(page).to have_css('[data-composer-target="expanded"].hrise')
    # The visibility control stays a real, always-submitted native <select>.
    expect(page).to have_css('[data-composer-target="expanded"] select[name="hujah[visibility]"]')
    expect(page).to have_content("Min 8 characters to post")
    expect(page).to have_css("a[href='#{new_hujah_path}']")
  end

  it "keeps Post disabled under 8 chars and enables past it" do
    sign_in create(:user)
    visit root_path
    find('[data-composer-target="collapsed"]').click
    within('[data-composer-target="expanded"]') do
      expect(page).to have_button("Post", disabled: true)
      fill_in "hujah[body]", with: "Long enough claim to pass the gate"
      expect(page).to have_button("Post", disabled: false)
    end
  end

  it "expands the pill and posts a hoojah" do
    sign_in create(:user)
    visit root_path
    find('[data-composer-target="collapsed"]').click
    fill_in "hujah[body]", with: "Inline composed claim about buses"
    within('[data-composer-target="expanded"]') { click_on "Post" }
    expect(page).to have_content("Inline composed claim about buses")
  end
end
