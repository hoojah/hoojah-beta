# Cuprite pointer-hold helper for the conviction (hold-to-charge) vote.
#
# The conviction controller listens for pointerdown/pointerup. A Capybara `.click`
# fires them back-to-back (a tap → normal vote); to exercise the HOLD path we need to
# hold the pointer down past the charge duration, then release. We dispatch the pointer
# events directly on the element (Cuprite passes the resolved DOM node as arguments[0])
# and sleep between them — the one sanctioned sleep in the suite, since the behaviour
# under test is explicitly time-based.
module PointerHelpers
  def hold(selector, seconds)
    el = find(selector)
    page.execute_script(
      "arguments[0].dispatchEvent(new PointerEvent('pointerdown', {bubbles: true}))", el
    )
    sleep seconds
    # By release time the charge may have completed and committed the vote, which
    # submits the form and lets Turbo replace the hero — so the held node can already
    # be gone. A vanished node means the hold succeeded; swallow the lookup failure.
    begin
      page.execute_script(
        "arguments[0].dispatchEvent(new PointerEvent('pointerup', {bubbles: true}))", el
      )
    rescue Ferrum::NodeNotFoundError
      # node replaced by the post-conviction Turbo Stream — nothing left to release
    end
  end
end

RSpec.configure do |config|
  config.include PointerHelpers, type: :system
end
