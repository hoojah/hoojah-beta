require "rails_helper"

# `ui/_user_link` (Slice B) is the reusable anchor wrapped around every user render
# point — avatar, full name, or @handle. It is a genuine <a> to the profile so click,
# middle-click, keyboard focus and JS-off all navigate, AND it carries the hovercard
# Stimulus triggers so a fine-pointer hover shows the floating card.
#
# It is a LAYOUT partial (one of its locals is `class`, which cannot be a strict-locals
# param), so every example goes through `render layout:` — the only call form that
# passes the block through. See `ui/_card` / `ui/_menu` for the same shape.
RSpec.describe "ui/_user_link", type: :view do
  let(:user) { create(:user, username: "aisyah") }

  def html(body = "@aisyah", **locals)
    render(layout: "ui/user_link", locals: {user: user}.merge(locals)) { body }.strip
  end

  def link(body = "@aisyah", **locals)
    Capybara.string(html(body, **locals))
  end

  it "is a real anchor to the user's profile" do
    expect(link).to have_css("a[href='/u/aisyah']")
  end

  it "carries the hovercard controller and its value attributes" do
    expect(link).to have_css(
      "a[data-controller='hovercard']" \
      "[data-hovercard-username-value='aisyah']" \
      "[data-hovercard-url-value='/u/aisyah/card']"
    )
  end

  it "wires the four show/hide actions on hover and focus" do
    action = link.find("a")["data-action"]

    expect(action).to include("mouseenter->hovercard#scheduleShow")
    expect(action).to include("mouseleave->hovercard#scheduleHide")
    expect(action).to include("focusin->hovercard#scheduleShow")
    expect(action).to include("focusout->hovercard#scheduleHide")
  end

  it "yields the block content INSIDE the anchor" do
    expect(link("@aisyah")).to have_css("a", text: "@aisyah")
  end

  it "keeps the link underline-free and appends caller classes" do
    expect(link(class: "text-ink font-bold")).to have_css("a.no-underline.text-ink.font-bold")
  end

  it "carries only `no-underline` when no class local is given" do
    expect(link.find("a")["class"]).to eq("no-underline")
  end
end
