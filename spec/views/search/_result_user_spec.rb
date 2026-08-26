require "rails_helper"

# Slice B (hovercard): the search person result's avatar+name link swapped from a plain
# `link_to profile_path` to `ui/_user_link`, so it still resolves to the profile AND
# carries the hovercard trigger. The follow control stays a sibling <form>, never nested.
RSpec.describe "search/_result_user", type: :view do
  let(:user) { create(:user, full_name: "Nurul Izzah", username: "nurul") }

  before do
    assign(:query, "nurul")
    allow(view).to receive_messages(user_signed_in?: false, current_user: nil)
  end

  def doc
    Nokogiri::HTML(render(partial: "search/result_user", locals: {user: user}))
  end

  it "links the avatar+name to the profile with the hovercard trigger" do
    link = doc.at_css('a[href="/u/nurul"]')
    expect(link).to be_present
    expect(link["data-controller"]).to eq("hovercard")
    expect(link["data-hovercard-url-value"]).to eq("/u/nurul/card")
    expect(doc.css("a a")).to be_empty
  end

  it "keeps the literal @handle substring intact for the visibility-leak checks" do
    expect(render(partial: "search/result_user", locals: {user: user})).to include("@nurul")
  end
end
