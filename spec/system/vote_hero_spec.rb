require "rails_helper"

RSpec.describe "Vote hero", type: :system, js: true do
  # Shrink the conviction timing (default 2000ms arm + 5000ms countdown) so the
  # hold-based specs stay fast. The controller reads these values live from the
  # wrapper's data-* attributes, so setting them after load takes effect on the next
  # pointerdown. arm=80ms, countdown=200ms (total 280ms lock), tap=40ms threshold.
  def shrink_conviction_timing!
    page.execute_script(<<~JS)
      const el = document.querySelector("[data-controller='conviction']")
      el.setAttribute('data-conviction-arm-delay-value', '80')
      el.setAttribute('data-conviction-countdown-value', '200')
      el.setAttribute('data-conviction-tap-value', '40')
    JS
  end

  it "taps to cast a normal vote" do
    login_as_system(create(:user))
    h = create(:hujah)
    visit hujah_path(h.slug)

    find('[data-stance="agree"]').click # instant tap, well under the 200ms default tap threshold
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

    hold('[data-stance="disagree"]', 0.5) # 500ms > 280ms lock
    expect(page).to have_content("1 vote")
    expect(h.reload.disagree_count).to eq 1
    expect(h.conviction_count).to eq 1
    expect(h.votes.last.conviction).to be true
  end

  it "releasing mid-hold cancels with no vote" do
    login_as_system(create(:user))
    h = create(:hujah)
    visit hujah_path(h.slug)
    find('[data-stance="agree"]') # ensure the hero rendered
    shrink_conviction_timing!

    # 150ms: past the 40ms tap threshold and the 80ms arm (into the countdown), but
    # released before the 280ms lock -> cancel, nothing recorded.
    hold('[data-stance="agree"]', 0.15)
    expect(page).to have_content("No votes yet")
    expect(h.reload.agree_count).to eq 0
    expect(h.neutral_count).to eq 0
    expect(h.disagree_count).to eq 0
    expect(h.votes.count).to eq 0
  end
end
