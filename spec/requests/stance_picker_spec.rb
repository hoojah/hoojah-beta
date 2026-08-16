require "rails_helper"

# The composer's stance picker (Slice 9, Task 4.2 —
# docs/design-system/components/voting/StancePicker.prompt.md).
#
# The design system's whole "which stance am I posting as" signal is the inversion:
# the picked circle FILLS with the stance colour and its glyph turns white. Before
# Task 4.2 the partial built that fill as `peer-checked:bg-#{stance}`, which Tailwind
# never emitted — see the sibling describe below — so the glyph turned white against
# a white circle and the picked stance read as blank. Markup and CSS each have to
# hold up their end, so both are asserted.
RSpec.describe "Stance picker", type: :request do
  let(:replier) { create(:user) }
  let(:parent) { create(:hujah, user: create(:user)) }

  def picker
    get "/hoojah/#{parent.slug}/respond"
    expect(response).to have_http_status(:ok)
    response.body
  end

  before { sign_in replier }

  it "offers all three stances, each with its own checked fill" do
    body = picker

    %w[agree neutral disagree].each do |stance|
      expect(body).to include("peer-checked:bg-#{stance}"),
        "the #{stance} circle has no checked fill, so picking it renders a blank button"
      expect(body).to include("border-#{stance}")
    end
  end

  # StancePicker.prompt.md: "defaults to the replier's existing vote on that parent."
  it "pre-selects the stance the replier already voted on the parent" do
    Vote.create!(user: replier, hujah: parent, vote: [3])

    doc = Capybara.string(picker)

    expect(doc).to have_field(type: "radio", with: "3", checked: true)
    expect(doc).to have_field(type: "radio", with: "1", checked: false)
  end

  it "pre-selects nothing when the replier has not voted on the parent" do
    doc = Capybara.string(picker)

    expect(doc).to have_no_field(type: "radio", checked: true)
  end
end

# The CSS half of the same guarantee. `@source inline(...)` in
# app/assets/tailwind/application.css safelists the BARE colour utilities; a safelist
# entry does not generate the `peer-checked:` (or any other) variant of them, and the
# scanner cannot see a class ERB assembles at render time. So the three checked fills
# reach the bundle only because `hujahs/_stance_picker` spells them out as literals —
# which is invisible-looking code that a well-meaning tidy-up would collapse straight
# back into an interpolation. This is what would go red if it did.
RSpec.describe "Stance picker checked fills reach the compiled bundle" do
  before(:all) { TailwindBuild.once! }

  it "emits a rule for every stance's checked fill" do
    missing = %w[agree neutral disagree].reject { |stance| TailwindBuild.emitted?("peer-checked:bg-#{stance}") }

    expect(missing).to be_empty,
      "no rule for peer-checked:bg-#{missing.join(", peer-checked:bg-")} in " \
      "app/assets/builds/tailwind.css — the picked stance will render as an empty " \
      "circle. Spell the class out literally in hujahs/_stance_picker, or safelist it."
  end
end
