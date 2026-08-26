require "rails_helper"

# `ui/_avatar`, `variant: :tile`, and the ActiveStorage avatar (Task 2).
#
# `:tile` is the branded gradient-initials treatment surfaces opt into on purpose
# (navbar, feed cards, the public profile header). Historically it ALWAYS suppressed
# the image, so a user who had uploaded an avatar never saw it on those surfaces.
#
# The fix: `:tile` shows a genuinely UPLOADED avatar (`user.avatar.attached?`) and
# otherwise falls back to the initials tile. The load-bearing distinction is that this
# keys on the ActiveStorage attachment ONLY, never on the legacy `photo` string —
# `User#assign_random_photo` seeds a random Cloudinary URL onto every user, so keying
# on `photo` presence would paint a stranger's stock image on the tile.
RSpec.describe "ui/_avatar", type: :view do
  let(:photo) { "https://res.cloudinary.com/hoojah/image/upload/v1586909321/user_photo_2.gif" }

  # `build`, not `create`: the `after_create` `assign_random_photo` would clobber a
  # blank `photo`, making the "legacy photo present, no attachment" branch unreachable.
  let(:user) { build(:user, full_name: "Maya Zaharudin", username: "maya", photo: photo) }

  # `ds_avatar_url` calls `avatar.url`, which the Disk service cannot sign without a
  # host — request/system specs get one for free, a view spec does not.
  around do |ex|
    old = ActiveStorage::Current.url_options
    ActiveStorage::Current.url_options = {host: "http://test.host"}
    ex.run
    ActiveStorage::Current.url_options = old
  end

  def html(**locals)
    render(partial: "ui/avatar", locals: {user: user}.merge(locals)).strip
  end

  def avatar(**locals)
    Capybara.string(html(**locals))
  end

  it "renders the uploaded photo on a :tile surface when an avatar is attached" do
    # `create` (persisted), not the shared `build`: `ds_avatar_url` now returns a
    # `rails_storage_proxy_path`, which needs a persisted blob to produce a signed_id.
    # Real callers always pass persisted users; only this spec's build-by-default bit.
    saved = create(:user, full_name: "Maya Zaharudin", username: "maya")
    saved.avatar.attach(io: StringIO.new("png-bytes"), filename: "a.png", content_type: "image/png")

    result = avatar(user: saved, variant: :tile)
    expect(result).to have_css("img")
    expect(result).to have_css("img[src^='/rails/active_storage/blobs/proxy/']")
  end

  it "tiles a :tile user who has only the legacy photo string, never the seeded image" do
    result = avatar(variant: :tile)

    expect(result).to have_no_css("img")
    expect(result).to have_css("span[role='img']", text: view.ds_initials(user.full_name))
  end

  it "still renders the legacy photo on the default (non-tile) variant, attachment or not" do
    expect(avatar).to have_css("img[src='#{photo}']")
  end
end
