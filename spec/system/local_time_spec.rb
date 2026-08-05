require "rails_helper"

# local-time (JS) rewrites `<time data-local="time-ago">` elements into relative
# timestamps and adds a `title` with the absolute time. Its PageObserver must also
# process elements injected by a Turbo Stream append (the "Load more" flow), not
# just those present on first paint.
RSpec.describe "Local time after Turbo Stream", type: :system, js: true do
  it "localizes <time> elements inserted by a Turbo Stream append" do
    user = create(:user)
    create_list(:hujah, 20, user: user, parent_id: nil)

    visit "/"
    expect(page).to have_css('[data-testid="hujah-card"]', count: 15)

    click_link "Load more"
    expect(page).to have_css('[data-testid="hujah-card"]', count: 20)

    # A processed relative-time element gained a `title` (absolute time) attribute —
    # proof local-time re-ran over the stream-appended cards, not raw ISO/strftime.
    expect(page).to have_css('time[data-local="time-ago"][title]')
  end
end
