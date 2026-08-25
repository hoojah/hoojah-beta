require "rails_helper"

RSpec.describe "Feed empty states", type: :request do
  it "prompts an anonymous visitor to sign up when there are no hoojahs" do
    get root_path
    # The distinctive empty-state sentence — NOT the navbar's "Sign up" link, which
    # renders for anonymous visitors regardless and would pass trivially.
    expect(response.body).to include("sign up to start the conversation")
    # The signed-in owner CTA must never appear for an anonymous visitor.
    expect(response.body).not_to include("Post the first hoojah")
  end

  it "prompts a signed-in user to post the first hoojah when the feed is empty" do
    user = create(:user)
    sign_in user
    get root_path
    expect(response.body).to include("No hoojahs yet")
    # The empty-state CTA label. The navbar's compose entry reads "New Claim", not
    # this, so asserting the label actually pins the CTA branch.
    expect(response.body).to include("Post the first hoojah")
    expect(response.body).not_to include("sign up to start the conversation")
  end

  it "shows the reworded Following-empty copy without misdirection" do
    user = create(:user)
    sign_in user
    get root_path(filter: "following")
    expect(response.body).to include("When people you follow post")
    # Following-empty is a paragraph, not the global-feed CTA.
    expect(response.body).not_to include("Post the first hoojah")
  end
end
