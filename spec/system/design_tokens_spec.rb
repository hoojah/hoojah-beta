require "rails_helper"

# Guards the design-system token port (Slice 9, Task 1.1).
#
# `app/views/notifications/_notification_card.html.erb` builds its 8px left border
# class by interpolating the read state — `border-read` / `border-unread`. Neither
# colour existed in the app's `@theme` before this slice, and neither class name is
# visible to Tailwind's source scanner (it only ever sees the interpolation), so the
# borders rendered as *nothing*. This spec pins both halves of the fix: the tokens
# exist in `@theme`, and `@source inline` forces the interpolated utilities into the
# build. It asserts the *computed* colour in a real browser, so a missing token or a
# missing safelist entry both fail it.
RSpec.describe "Notification card read-state tokens", type: :system, js: true do
  # The assertions below read the compiled bundle, which is gitignored and not
  # rebuilt anywhere in the boot path — see spec/support/tailwind_build.rb.
  before(:all) { TailwindBuild.once! }

  let(:me) { create(:user) }

  def border_left_color(dom_id)
    page.evaluate_script(
      "getComputedStyle(document.querySelector('##{dom_id}')).borderLeftColor"
    )
  end

  it "colours the notification card's left border by read state" do
    hujah = create(:hujah, user: me)
    unread = create(:notification, user: me, hujah: hujah, subject_user: create(:user),
      category: :new_hoojah_response, read: false)
    read = create(:notification, user: me, hujah: hujah, subject_user: create(:user),
      category: :new_hoojah_response, read: true)

    login_as_system(me)
    visit notifications_path

    unread_id = ActionView::RecordIdentifier.dom_id(unread)
    read_id = ActionView::RecordIdentifier.dom_id(read)

    # Assert the class first, then the colour it resolves to. Separating the two
    # tells a later reader which half broke: a missing class means the view stopped
    # emitting it, while the right class with the wrong colour means the token or
    # the `@source inline` safelist regressed.
    expect(page).to have_css("##{unread_id}.border-unread")
    expect(page).to have_css("##{read_id}.border-read")

    # 2026: --color-unread chains to var(--unread) → var(--neutral), so the unread
    # border follows the active scheme's neutral. Default = Spectrum, whose neutral is
    # #e8930c (amber). (Was the old fixed pink #e1306c before the rebrand.)
    expect(border_left_color(unread_id)).to eq("rgb(232, 147, 12)")
    # --color-read: #bac2ca (light-grey)
    expect(border_left_color(read_id)).to eq("rgb(186, 194, 202)")
  end
end
