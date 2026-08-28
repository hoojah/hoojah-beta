require "rails_helper"

# Guards Animation #2: cards APPENDED by "Load more" carry `.hujah-card-enter`
# (the rise-and-fade entrance), while cards painted on the initial load do NOT —
# so the feed only animates on pagination, never on first paint or scroll.
#
# The class rides the wrapper `<div class="relative mb-2 …">` in `_hujah_card`,
# gated on the `entering:` local that ONLY `index.turbo_stream.erb` passes.
RSpec.describe "Feed load-more animation", type: :system, js: true do
  it "animates appended cards but not first-paint cards" do
    # Page size is 15 (Pagy::OPTIONS[:limit]); 16 forces a second page.
    create_list(:hujah, 16)

    visit "/"
    expect(page).to have_css('[data-testid="hujah-card"]')
    # Nothing on first paint should carry the entrance class.
    expect(page).to have_no_css(".hujah-card-enter")

    click_link "Load more"

    # The appended page-2 card animates in.
    expect(page).to have_css(".hujah-card-enter")
  end
end
