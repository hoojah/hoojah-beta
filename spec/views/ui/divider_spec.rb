require "rails_helper"

# `ui/_divider` is the hairline that separates sections INSIDE a card
# (docs/design-system/components/core/Card.jsx `Divider`). It has no logic, but it
# does carry a design token: the design system is explicit that internal sections are
# divided by a `#f3f4f6` rule and never by a second shadow or a nested card, so the
# colour is the whole component and swapping it for `border-gray-200` — the field
# border, one step darker — would be invisible in review and wrong on every card.
RSpec.describe "ui/_divider", type: :view do
  def html(**locals)
    render(partial: "ui/divider", locals: locals).strip
  end

  def divider(**locals)
    Capybara.string(html(**locals))
  end

  it "is a top hairline in the design system's `--border-hairline` grey" do
    expect(divider).to have_css("div.border-t.border-gray-100")
  end

  it "carries no colour but that one — a divider is not a card edge" do
    expect(html).not_to include("shadow")
    expect(divider).to have_no_css("div.border-gray-200")
  end

  it "appends caller classes, since the vertical rhythm varies by call site" do
    expect(divider(class: "my-2")).to have_css("div.border-t.border-gray-100.my-2")
  end
end
