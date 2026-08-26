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

  # A reply hujah's own show page is the canonical flag surface for replies: the thread's
  # `_child_card` is a single anchor to this page and deliberately carries no menu (a
  # nested menu inside an <a> is invalid HTML, and that partial is frozen). So the flag
  # dialog must render here for a signed-in viewer on a child hujah, exactly as it does
  # for a top-level one.
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
end
