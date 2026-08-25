require "rails_helper"

# `ui/_empty_state` is the product's one-line empty state (Slice 9, Task 2.3):
# EmptyState.prompt.md — "faint grey, one Lucide glyph, one plain sentence. Never an
# illustration, never an emoji." Five views hand-repeat the same flex row today with
# three different paddings and two different tones.
RSpec.describe "ui/_empty_state", type: :view do
  # `render`'s return value, not `rendered` — `rendered` accumulates across renders
  # within an example and would corrupt the comparison examples below.
  def html(message = "No response yet", **locals)
    render(partial: "ui/empty_state", locals: {message: message}.merge(locals)).strip
  end

  def state(*, **locals)
    Capybara.string(html(*, **locals))
  end

  # The real sentences in the product. They are the whole component — there is no
  # heading, no illustration and no CTA to get wrong.
  ["No response yet",
    "You have no notifications",
    "You haven't posted any hoojahs yet",
    "Nothing trending yet.",
    "No debates yet — challenge a response to start one."].each do |message|
    it "renders #{message.inspect} as a plain sentence" do
      expect(state(message)).to have_css("span", text: message)
    end
  end

  describe "the glyph" do
    # `lucide-rails` emits a bare <svg> with no name in any attribute, so the only
    # way to prove *which* glyph rendered is to compare against the helper's own
    # output. Not `ActionController::Base.helpers` — that proxy carries only Action
    # View's modules and would raise NoMethodError on `lucide_icon`.
    def glyph(name)
      ApplicationController.helpers.lucide_icon(name, class: "w-4 h-4")
    end

    it "renders a Lucide svg, defaulting to the speech bubble" do
      expect(state).to have_css("svg")
      expect(html).to include(glyph("message-circle"))
    end

    it "takes whichever icon the surface calls for" do
      notifications = html("You have no notifications", icon: "bell")

      expect(notifications).to include(glyph("bell"))
      expect(notifications).not_to include(glyph("message-circle"))
    end

    # Trending's "Nothing trending yet." is a bare sentence with no glyph, and
    # `lucide_icon(nil)` raises — so nil has to mean "no icon", not "default icon".
    it "renders no svg at all when the icon is explicitly nil" do
      expect(state("Nothing trending yet.", icon: nil)).to have_no_css("svg")
    end

    it "sizes the glyph at the design system's 16px inline icon" do
      expect(state).to have_css("svg.w-4.h-4")
    end
  end

  describe "tone" do
    # Faint (`#bac2ca`) is the default, and one `text-` utility on the wrapper colours
    # BOTH halves: the sentence directly, and the glyph because a Lucide icon is a
    # stroked svg whose `stroke="currentColor"` resolves against the inherited colour.
    # No fill utility is involved or wanted — see the tombstone in
    # app/assets/tailwind/application.css.
    it "is faint light-grey by default, glyph and sentence alike" do
      expect(state).to have_css("div.text-light-grey")
    end

    it "steps up to muted grey on request" do
      muted = state(tone: :muted)

      expect(muted).to have_css("div.text-grey")
      expect(muted).to have_no_css("div.text-light-grey")
    end

    it "accepts a string tone as readily as a symbol" do
      expect(html(tone: "muted")).to eq(html(tone: :muted))
    end

    it "treats a nil tone as unset and stays faint" do
      expect(html(tone: nil)).to eq(html)
    end
  end

  describe "alignment" do
    it "reads left-aligned, like the list it replaces" do
      expect(state).to have_css("div.justify-start")
    end

    it "centres on request, for the debate composer's waiting line" do
      expect(state("Waiting for @mayaz…", align: :center)).to have_css("div.justify-center")
    end
  end

  describe "the row" do
    it "is a small-type flex row on the card surface" do
      expect(state).to have_css("div.flex.items-center.gap-1.text-sm.bg-white")
    end

    it "appends caller classes, since the five call sites pad differently" do
      expect(state(class: "px-4")).to have_css("div.flex.px-4")
    end
  end

  # `message` is the entire component. Defaulting it to nil would render a faint
  # glyph beside an empty span — a broken-looking row that no test and no reviewer
  # would flag — so a caller who forgets it gets a KeyError naming the local.
  it "fails loudly when no message is given, rather than rendering an empty row" do
    expect { render(partial: "ui/empty_state", locals: {icon: "bell"}) }
      .to raise_error(ActionView::Template::Error, /message/)
  end

  # The optional CTA slot: a caller can pair the sentence with a single pill link
  # (e.g. "Post the first hoojah") when both `cta_label` and `cta_href` are given.
  # Either alone is not enough — a label with no href has nowhere to send the
  # visitor, so it renders no link at all rather than a link to nil.
  describe "the CTA slot" do
    it "renders just the sentence and glyph with no CTA by default" do
      render "ui/empty_state", message: "Nothing here"
      expect(rendered).to have_text("Nothing here")
      expect(rendered).not_to have_selector("a")
    end

    it "renders a single pill CTA when cta_label and cta_href are both present" do
      render "ui/empty_state", message: "No hoojahs yet",
        cta_label: "Post the first hoojah", cta_href: "/hoojah/new"
      expect(rendered).to have_link("Post the first hoojah", href: "/hoojah/new")
    end

    it "renders no CTA when only cta_label is given (href missing)" do
      render "ui/empty_state", message: "No hoojahs yet", cta_label: "Post"
      expect(rendered).not_to have_selector("a")
    end
  end
end
