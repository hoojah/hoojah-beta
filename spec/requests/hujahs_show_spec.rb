require "rails_helper"

RSpec.describe "Hujah show", type: :request do
  it "renders the hujah, its vote bars, and threaded children" do
    user = create(:user)
    parent = create(:hujah, user: user)
    create(:hujah, user: user, parent: parent, body: "a child response")
    get "/hoojah/#{parent.slug}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(dom_id(parent, :vote_hero))
    expect(response.body).to include("a child response")
    expect(response.body).to include('data-controller="response-filter"')
  end

  # Slice B (hovercard byline): the show-page author byline (avatar + full name) must be
  # real anchors to the author's profile carrying the hovercard triggers. The `@username`
  # + time caption below stays plain (wrapping it would put the timestamp in the anchor).
  it "links the show-page byline avatar and name to the author's profile with hovercard triggers" do
    author = create(:user, username: "aisyah")
    hujah = create(:hujah, user: author, body: "a claim on its own page")

    get "/hoojah/#{hujah.slug}"
    expect(response).to have_http_status(:ok)

    doc = Nokogiri::HTML(response.body)
    profile_links = doc.css('a[href="/u/aisyah"][data-controller="hovercard"]')
    # Avatar + name are both converted → at least two hovercard-carrying profile anchors.
    expect(profile_links.size).to be >= 2
  end

  # Slice B (hovercard): `_child_card` is no longer a single anchor. It is a stretched-link
  # container <div> — an inset overlay anchor carries the whole-card click to the response's
  # show page, and the responder's avatar + name are their OWN profile links (hovercard
  # triggers) sitting above the overlay. The two anchors are siblings, never nested.
  it "restructures the child card into a hoojah overlay link + a non-nested profile byline link" do
    author = create(:user, username: "cardauthor")
    parent = create(:hujah)
    child = create(:hujah, user: author, parent: parent, body: "a threaded child response here")

    get "/hoojah/#{parent.slug}"
    expect(response).to have_http_status(:ok)

    doc = Nokogiri::HTML(response.body)
    # (a) the hoojah overlay link to the child's own page is present.
    expect(doc.css(%(a[href="/hoojah/#{child.slug}"])).size).to be >= 1
    # (b) a separate profile link with the hovercard trigger is present.
    expect(doc.css('a[href="/u/cardauthor"][data-controller="hovercard"]').size).to be >= 1
    # (c) NO anchor is nested inside another anchor anywhere on the page.
    expect(doc.css("a a")).to be_empty
    # The response-filter data attributes moved onto the container div verbatim.
    item = doc.at_css('[data-response-filter-target="item"]')
    expect(item).to be_present
    expect(item.name).to eq("div")
    expect(item["data-response-filter-vote"]).to be_present
  end

  # A reply hujah's own show page is the canonical flag surface for replies: the thread's
  # `_child_card` deliberately carries no menu (a nested menu/form inside the card's links
  # would be invalid HTML). So the flag dialog must render here for a signed-in viewer on a
  # child hujah, exactly as it does for a top-level one.
  it "renders the flag dialog and trigger on a reply hujah's own show page for a signed-in member" do
    author = create(:user)
    parent = create(:hujah, user: author)
    reply = create(:hujah, user: author, parent: parent, body: "a reply worth flagging")
    sign_in create(:user)
    get "/hoojah/#{reply.slug}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(dom_id(reply, :flag_dialog))
    expect(response.body).to include("Flag this hoojah")
  end

  # On a reply's show page, "back" targets the PARENT claim (not the feed) and the header
  # carries the parent as a tappable "Replying to @author" context strip.
  it "points back at the parent and shows a parent context strip on a reply" do
    author = create(:user, username: "parentauthor")
    parent = create(:hujah, user: author, body: "the parent claim body here")
    reply = create(:hujah, user: create(:user), parent: parent, body: "a threaded reply")
    get "/hoojah/#{reply.slug}"

    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    # The back arrow links to the parent, and there is a "Replying to @parentauthor" strip.
    expect(doc.css("header a[href='/hoojah/#{parent.slug}']").size).to be >= 1
    expect(response.body).to include("Replying to @parentauthor")
  end

  # A top-level claim's back arrow still goes to the feed (no parent strip).
  it "points back at the feed on a top-level claim" do
    hujah = create(:hujah, user: create(:user), body: "a top-level claim body")
    get "/hoojah/#{hujah.slug}"

    doc = Nokogiri::HTML(response.body)
    expect(doc.css("header a[href='/'][aria-label='Back']").size).to eq(1)
    expect(response.body).not_to include("Replying to @")
  end

  # Once the viewer has voted, the vote hero fades the two stances they did NOT pick
  # (opacity-40) so the chosen one stands out; the picked one is not dimmed.
  it "dims the two unvoted stance buttons in the vote hero after the viewer votes" do
    hujah = create(:hujah, user: create(:user), body: "a claim to stand on")
    voter = create(:user)
    hujah.cast_vote(by: voter, choice: 2) # neutral
    sign_in voter
    get "/hoojah/#{hujah.slug}"

    doc = Nokogiri::HTML(response.body)
    buttons = doc.css("#vote_hero_hujah_#{hujah.id} button[data-stance]")
      .to_h { |b| [b["data-stance"], b["class"]] }
    expect(buttons["neutral"]).not_to include("opacity-40")
    expect(buttons["agree"]).to include("opacity-40")
    expect(buttons["disagree"]).to include("opacity-40")
  end

  it "does not dim any vote hero button before the viewer votes" do
    hujah = create(:hujah, user: create(:user), body: "an unvoted claim")
    sign_in create(:user)
    get "/hoojah/#{hujah.slug}"

    doc = Nokogiri::HTML(response.body)
    classes = doc.css("#vote_hero_hujah_#{hujah.id} button[data-stance]").map { |b| b["class"] }
    expect(classes.join(" ")).not_to include("opacity-40")
  end

  # The argument composer renders for the author on their OWN claim too — an author is
  # allowed to respond to their own hoojah (HujahPolicy#create? already permits it; only
  # the view previously suppressed the composer for the author).
  it "renders the argument composer for the author on their own hujah" do
    author = create(:user)
    hujah = create(:hujah, user: author, body: "a claim its author may respond to")
    sign_in author
    get "/hoojah/#{hujah.slug}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(dom_id(hujah, :argument_composer))
  end
end
