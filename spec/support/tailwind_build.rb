require "open3"

# Compiles `app/assets/tailwind/application.css` into `app/assets/builds/tailwind.css`
# once per suite run.
#
# The compiled bundle is gitignored, and nothing in the boot path, `Rakefile`,
# `bin/`, or CI regenerates it before RSpec. That is harmless for specs that only
# assert on markup, but any spec asserting on *rendered* CSS (computed colours,
# whether a utility exists) silently depends on a build artifact that may be
# absent, stale, or predate the current `application.css`. Stale gives a
# misleading red; worse, it can give a false green when the bundle happens to
# still contain a rule the current source no longer emits.
#
# Call `TailwindBuild.once!` from a `before(:all)` in any such spec. It is a no-op
# after the first call, so several CSS-dependent specs in one run cost one build.
module TailwindBuild
  class BuildError < StandardError; end

  class << self
    def once!
      @outcome ||= run
      raise BuildError, "`bin/rails tailwindcss:build` failed:\n\n#{@outcome}" unless @outcome == :ok
      true
    end

    # Is there a rule for this class in the built bundle?
    #
    # Three spec groups ask that question — the button tones, the avatar boxes and the
    # card stances — and each had rewritten the regex, which is fiddly in two ways
    # neither obvious nor testable from the call site. `active:scale-95` is escaped as
    # `.active\:scale-95` in the output, and the trailing lookahead is a token
    # boundary: without it `.rounded` matches `.rounded-full` and a missing utility
    # reads as present. Builds first, so callers cannot read a bundle that was never
    # made.
    def emitted?(klass)
      once!
      bundle.match?(/\.#{Regexp.escape(klass.gsub(":", '\\:'))}(?![\w-])/)
    end

    # One read per suite run. Safe to memoize because `once!` builds exactly once and
    # nothing else in the suite writes the bundle.
    def bundle
      once!
      @bundle ||= Rails.root.join("app/assets/builds/tailwind.css").read
    end

    private

    # Memoized by `once!` — returns :ok, or the combined output on failure so the
    # verdict (including a failure) is stable for every later caller in the run.
    def run
      output, status = Open3.capture2e(
        {"RAILS_ENV" => Rails.env.to_s},
        Rails.root.join("bin/rails").to_s, "tailwindcss:build",
        chdir: Rails.root.to_s
      )
      status.success? ? :ok : output
    end
  end
end
