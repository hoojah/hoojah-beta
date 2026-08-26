require "rails_helper"

# `users/_user_row` is the row in the followers, following and blocked-users lists
# (docs/design-system/components/social/UserRow.prompt.md).
#
# The load-bearing example here is the SEPARATOR COLOUR, and it guards a defect that
# actually shipped. The row said `border-b` with no colour class. Tailwind's reset
# leaves `border-color` at `currentColor`, and Task 1.1's base layer paints every
# `<a>` with `--fg-link` — so the 1px rule between followers rendered in brand indigo
# rather than the design system's `#f3f4f6` hairline. Nothing failed; it simply looked
# wrong, on a screen no spec asserted colour on.
#
# That is a one-token regression away at all times: deleting `border-gray-100` from
# the class string leaves valid markup, a green suite, and an indigo rule. Hence an
# assertion rather than a comment. `spec/views/ui/divider_spec.rb` pins the same
# hairline for the same reason, one level down.
#
# `build`, not `create` — the row needs no persisted row and `profile_path` only wants
# the username, so this stays off the shared test database.
RSpec.describe "users/_user_row", type: :view do
  let(:user) { build(:user, full_name: "Nurul Izzah", username: "nurul") }

  def row
    Capybara.string(render(partial: "users/user_row", locals: {user: user}).strip)
  end

  it "separates rows with the design system's hairline, never the inherited link colour" do
    expect(row).to have_css("a.border-b.border-gray-100")
  end

  # The complement of the example above: a `border-b` that carries no colour class is
  # the exact shape of the original defect, so assert that no such element exists
  # rather than only that a correct one does.
  it "leaves no bottom border to fall back on `currentColor`" do
    expect(row).to have_no_css("a.border-b:not(.border-gray-100)")
  end

  it "hovers to the design system's gray-50, not Tailwind's own neutral ramp" do
    expect(row).to have_css("a.hover\\:bg-gray-50")
  end

  # Rows sit directly on white with a hairline between them — the list wrapper owns
  # the single `shadow`. A shadow per row would make each one its own card, which is
  # what UserRow.prompt.md rules out.
  it "is not a card" do
    expect(row).to have_no_css("a.shadow")
  end

  # Slice B: the row's profile link is now a `ui/_user_link`, so it resolves to
  # `profile_path` AND carries the hovercard trigger. The Remove-follower form (Slice C)
  # is a sibling, never nested inside the anchor.
  it "links to the profile with the hovercard trigger" do
    doc = Nokogiri::HTML(render(partial: "users/user_row", locals: {user: user}))
    link = doc.at_css('a[href="/u/nurul"]')
    expect(link).to be_present
    expect(link["data-controller"]).to eq("hovercard")
    expect(link["data-hovercard-url-value"]).to eq("/u/nurul/card")
    expect(doc.css("a a")).to be_empty
  end
end
