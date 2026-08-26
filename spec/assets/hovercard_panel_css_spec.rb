require "rails_helper"

# Slice B hovercard panel chrome is assembled as a class string in
# hovercard_controller.js, not written literally in any scanned template, so the
# utilities are forced into the build via an `@source inline(...)` safelist entry in
# `app/assets/tailwind/application.css`. If that entry is dropped, the panel would
# render unstyled (transparent, un-elevated, unsized) with no failing view — so pin
# the compiled rules here.
#
# `TailwindBuild` builds the gitignored bundle once per suite and answers "is there a
# rule for this class?" with the same token-boundary regex the button/avatar/card
# specs use.
RSpec.describe "hovercard panel Tailwind safelist" do
  before(:all) { TailwindBuild.once! }

  %w[z-50 w-72 transition-opacity opacity-100].each do |klass|
    it "emits the panel utility .#{klass}" do
      expect(TailwindBuild.emitted?(klass)).to be(true)
    end
  end
end
