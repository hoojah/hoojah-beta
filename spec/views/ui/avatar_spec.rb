require "rails_helper"

# `ui/_avatar` is a bug fix wearing a design-system hat (Slice 9, Task 2.2).
#
# Eleven views currently call `image_tag user.photo` directly. `photo` is nullable —
# `assign_random_photo` only backfills it on create — and `image_tag nil` raises,
# taking down a whole page for one missing avatar. The design system
# (`docs/design-system/components/core/Avatar.jsx`) answers that with initials on
# primary, and this partial is where that lands. So the load-bearing example here is
# the *absence* of an `<img>` when there is no photo.
RSpec.describe "ui/_avatar", type: :view do
  let(:photo) { "https://res.cloudinary.com/hoojah/image/upload/v1586909321/user_photo_2.gif" }

  # `build`, not `create`: `User#assign_random_photo` is an `after_create` that
  # backfills a Cloudinary URL, so a *created* user can never have a blank photo and
  # the branch under test would be unreachable.
  let(:user) { build(:user, full_name: "Maya Zaharudin", username: "maya", photo: nil) }
  let(:photo_user) { build(:user, full_name: "Maya Zaharudin", username: "maya", photo: photo) }

  # `render`'s return value, not `rendered` — the latter accumulates across every
  # render in an example, so the two comparison examples below would each be diffing
  # one avatar against two concatenated ones.
  def html(**locals)
    render(partial: "ui/avatar", locals: {user: user}.merge(locals)).strip
  end

  def avatar(**locals)
    Capybara.string(html(**locals))
  end

  describe "without a photo" do
    it "renders no <img> at all — `image_tag nil` is the 500 this partial exists to stop" do
      expect(avatar).to have_no_css("img")
    end

    # `role="img"` is what makes the label count: ARIA prohibits an author-supplied
    # name on `role=generic`, which a bare `<span>` is, so without the role a screen
    # reader may drop "Maya Zaharudin" and announce the letters "MZ" instead.
    it "shows the initials, labelled with the full name so a screen reader hears a person" do
      expect(avatar).to have_css("span[role='img'][aria-label='Maya Zaharudin']", text: "MZ")
    end

    it "is white on primary, per the design system" do
      expect(avatar).to have_css("span.bg-primary.text-white")
    end

    it "falls back to ? rather than an empty circle when the name is unusable" do
      user.full_name = " "

      expect(avatar).to have_css("span", text: "?")
    end
  end

  describe "with a photo" do
    let(:user) { photo_user }

    it "renders the photo, named after the person rather than the handle" do
      expect(avatar).to have_css("img[src='#{photo}'][alt='Maya Zaharudin']")
    end

    it "renders no initials fallback alongside it" do
      expect(avatar).to have_no_css("span")
    end

    it "crops rather than squashes a non-square photo into the circle" do
      expect(avatar).to have_css("img.object-cover")
    end
  end

  # The two branches must be interchangeable in a layout: a feed row cannot reflow
  # depending on whether that particular user happens to have uploaded a photo.
  describe "the circle, on either branch" do
    it "is round and never shrinks in a flex row" do
      expect(avatar).to have_css("span.rounded-full.shrink-0")
      expect(avatar(user: photo_user)).to have_css("img.rounded-full.shrink-0")
    end

    # `inline-flex` here would be two bugs at once. An inline box sits on a line box and
    # collects descender leading the `block` img does not, so in a non-flex parent — the
    # `<a>` wrapper in hujahs/_hujah_header — the row shifts a few px for photoless users
    # only. And `.inline-flex` follows `.hidden` in the compiled bundle, so a caller's
    # `class: "hidden lg:block"` would hide the photo branch and leave the initials up.
    it "is block-level on both branches, never inline" do
      expect(avatar).to have_css("span.flex")
      expect(avatar).to have_no_css("span.inline-flex")
      expect(avatar(user: photo_user)).to have_css("img.block")
    end

    it "centres the initials in the circle" do
      expect(avatar).to have_css("span.items-center.justify-center")
    end

    # One person, one name. Announcing the handle for a photo and the full name for the
    # fallback would make the same user sound like two, and Avatar.jsx uses the name for
    # both. The handle is not always adjacent to lean on, either — see shared/_navbar.
    it "announces the same person whichever branch renders" do
      expect(avatar(user: photo_user)).to have_css("img[alt='Maya Zaharudin']")
      expect(avatar).to have_css("span[aria-label='Maya Zaharudin']")
    end

    it "gives the photo and the fallback the same box at every size" do
      DesignSystemHelper::AVATAR_SIZES.each do |size, classes|
        box = classes.split.grep(/\A[wh]-/).join(".")

        expect(avatar(size: size)).to have_css("span.#{box}")
        expect(avatar(user: photo_user, size: size)).to have_css("img.#{box}")
      end
    end
  end

  describe "size" do
    it "defaults to the 44px hujah-header avatar" do
      expect(avatar).to have_css("span.w-11.h-11")
    end

    it "treats a nil size as unset and takes that default" do
      unset = html(size: nil)

      expect(unset).to eq(html)
    end

    it "accepts a string as readily as a symbol" do
      string = html(size: "lg")

      expect(string).to eq(html(size: :lg))
    end

    # The five boxes the product actually uses — see Avatar.prompt.md. A view asking
    # for `:lg` and getting 44px would be a silent layout regression, so pin them.
    {lg: "w-24", md: "w-11", row: "w-10", nav: "w-9", sm: "w-8"}.each do |size, width|
      it "renders #{size} at #{width}" do
        expect(avatar(size: size)).to have_css("span.#{width}")
      end
    end

    # Avatar.jsx sets the fallback font size to `Math.round(size * 0.38)`, so the
    # initials grow with the circle. One shared font size would put the same letters
    # in a 96px header circle and a 32px stub — legible in neither.
    it "scales the initials type with the circle" do
      expect(avatar(size: :lg)).to have_css("span.text-4xl")
      expect(avatar(size: :sm)).to have_css("span.text-xs")
    end

    # Action View wraps anything a template raises in `Template::Error`; that it is an
    # ArgumentError underneath is pinned in the helper spec. What matters here is that
    # a typo is loud at the call site and the message names the sizes that do work.
    # The expectation is derived from the constant so reordering it stays green.
    it "raises on a misspelled size rather than silently rendering the wrong box" do
      permitted = Regexp.escape(DesignSystemHelper::AVATAR_SIZES.keys.join(", "))

      expect { avatar(size: :massive) }
        .to raise_error(ActionView::Template::Error, /massive.*#{permitted}/m)
    end
  end

  # Every one of the eleven call sites this replaces carries its own margin, so the
  # passthrough is what the Phase 4 refactor leans on hardest — and it has to work on
  # whichever branch that particular user happens to render.
  it "appends caller classes on both branches, for the margins that vary by call site" do
    expect(avatar(class: "mr-3")).to have_css("span.mr-3.w-11")
    expect(avatar(user: photo_user, class: "mr-3")).to have_css("img.mr-3.w-11")
  end
end
