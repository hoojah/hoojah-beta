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
