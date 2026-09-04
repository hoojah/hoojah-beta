# Trusted pointer-hold helper for the conviction (hold-to-charge) vote.
#
# We must use REAL CDP mouse input (not synthetic PointerEvents): only trusted input fires
# the native `click` on release, which is the exact path a mid-hold release must NOT let
# submit a normal vote. We move to the element centre, press, sleep (the one sanctioned
# sleep in the suite — the behaviour under test is explicitly time-based), then release.
# The release is coordinate-based, so it is safe even if a conviction commit has already
# submitted the form and let Turbo replace the held node.
module PointerHelpers
  def press_hold_release(selector, hold_seconds)
    el = find(selector)
    # DOMRect's x/y/width/height are prototype getters, not own enumerable properties, so
    # returning the DOMRect itself serializes to `{}` over CDP — build a plain object.
    rect = page.evaluate_script(<<~JS, el)
      (function (node) {
        const r = node.getBoundingClientRect()
        return {x: r.x, y: r.y, width: r.width, height: r.height}
      })(arguments[0])
    JS
    mouse = page.driver.browser.mouse
    mouse.move(x: rect["x"] + rect["width"] / 2, y: rect["y"] + rect["height"] / 2)
    mouse.down
    sleep hold_seconds
    mouse.up
  end
end

RSpec.configure do |config|
  config.include PointerHelpers, type: :system
end
