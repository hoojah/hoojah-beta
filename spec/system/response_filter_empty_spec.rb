require "rails_helper"

# Selecting a stance filter that matches zero responses used to hide every child
# card and leave a blank void under the tab row (no server round-trip — the
# filter is pure client-side show/hide). Guards the placeholder that now fills
# that gap, and the itemTargetConnected fix that keeps a live-appended reply
# correctly filtered without re-clicking the tab.
RSpec.describe "Response filter empty state", type: :system, js: true do
  it "shows a placeholder when a stance filter matches no responses" do
    author = create(:user)
    hujah = create(:hujah, user: author)
    create(:hujah, parent: hujah, user: create(:user), vote: 1)

    login_as_system(author)
    visit hujah_path(hujah.slug)
    within('[data-controller="response-filter"] [role="group"]') { click_button "Disagree" }

    expect(page).to have_text("No responses match this filter yet")
  end

  it "keeps a filter correct when a reply is appended live while the filter is active" do
    author = create(:user)
    hujah = create(:hujah, user: author)
    create(:hujah, parent: hujah, user: create(:user), vote: 1)
    # The composer only renders for a signed-in NON-author viewer (show.html.erb), and
    # HujahPolicy#create? requires that viewer to have already voted on the claim.
    replier = create(:user)
    hujah.cast_vote(by: replier, choice: 3)

    login_as_system(replier)
    visit hujah_path(hujah.slug)
    within('[data-controller="response-filter"] [role="group"]') { click_button "Disagree" }
    expect(page).to have_text("No responses match this filter yet")

    # Post a DISAGREEING reply via the on-page argument composer (Turbo Stream append).
    within('[data-controller="argument-composer"]') do
      click_button "Make your argument"
      click_button "Disagree"
      find("[data-argument-composer-target='body']").set("A disagreeing reply from the composer")
      click_button "Send"
    end

    # After the append, the placeholder must disappear WITHOUT re-clicking Disagree.
    expect(page).to have_content("A disagreeing reply from the composer")
    expect(page).not_to have_text("No responses match this filter yet")
  end
end
