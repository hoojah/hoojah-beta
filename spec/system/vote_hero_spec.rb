require "rails_helper"

RSpec.describe "Vote hero", type: :system, js: true do
  # Shrink the conviction timing so the hold specs stay fast. The controller reads these
  # live from the wrapper's data-* attributes, so setting them after load takes effect on
  # the next pointerdown. arm=100ms, countdown=400ms (500ms lock), tap=40ms threshold.
  def shrink_conviction_timing!
    page.execute_script(<<~JS)
      const el = document.querySelector("[data-controller='conviction']")
      el.setAttribute('data-conviction-arm-delay-value', '100')
      el.setAttribute('data-conviction-countdown-value', '400')
      el.setAttribute('data-conviction-tap-value', '40')
    JS
  end

  it "taps to cast a normal vote" do
    login_as_system(create(:user))
    h = create(:hujah)
    visit hujah_path(h.slug)

    find('[data-stance="agree"]').click # trusted tap, well under the 200ms default tap threshold
    expect(page).to have_content("1 vote")
    expect(h.reload.agree_count).to eq 1
    expect(h.conviction_count).to eq 0
  end

  it "holds to the end to cast a conviction vote" do
    login_as_system(create(:user))
    h = create(:hujah)
    visit hujah_path(h.slug)
    find('[data-stance="disagree"]') # ensure the hero rendered
    shrink_conviction_timing!

    press_hold_release('[data-stance="disagree"]', 0.8) # 800ms > 500ms lock
    expect(page).to have_content("1 vote")
    expect(h.reload.disagree_count).to eq 1
    expect(h.conviction_count).to eq 1
    expect(h.votes.last.conviction).to be true
  end

  it "releasing mid-hold casts no vote (not even a normal one)" do
    login_as_system(create(:user))
    h = create(:hujah)
    visit hujah_path(h.slug)
    find('[data-stance="agree"]') # ensure the hero rendered
    shrink_conviction_timing!

    # 250ms: past the 40ms tap threshold and the 100ms arm (into the countdown), released
    # before the 500ms lock -> cancel. The trusted release also fires a native click, which
    # must NOT submit a normal vote.
    press_hold_release('[data-stance="agree"]', 0.25)
    expect(page).to have_content("No votes yet")
    expect(page).to have_no_content("1 vote")
    expect(h.reload.agree_count).to eq 0
    expect(h.neutral_count).to eq 0
    expect(h.disagree_count).to eq 0
    expect(h.votes.count).to eq 0
  end
end
