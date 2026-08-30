require "rails_helper"

RSpec.describe HujahsHelper, type: :helper do
  it "linkifies URLs and escapes script tags" do
    out = helper.format_body("See https://hoojah.my now <script>alert(1)</script>")
    expect(out).to include('href="https://hoojah.my"')
    expect(out).to include('rel="noopener"')
    expect(out).not_to include("<script>")
  end

  it "preserves newlines as paragraphs" do
    expect(helper.format_body("a\n\nb")).to include("</p>")
  end

  it "links a real @handle to the profile" do
    expect(helper.format_body("hi @rudz")).to include('href="/u/rudz"')
  end

  it "does NOT break an email or @-URL (no spliced quote, no truncated href)" do
    out = helper.format_body("ping foo@bar.com and https://medium.com/@who")
    expect(out).to include("mailto:foo@bar.com") # email anchor intact
    expect(out).to include("https://medium.com/@who") # URL intact
    expect(out).not_to include('href="/u/bar"') # email @ not mentioned
    expect(out).not_to include('href="/u/who"') # URL @ not mentioned
  end

  it "escapes hostile handles (no live tag)" do
    expect(helper.format_body('@evil"><script>')).not_to include("<script>")
  end

  it "linkifies #hashtags to the tag feed and preserves @mentions" do
    html = helper.format_body("hey @nurul about #KlangValley transit")
    expect(html).to include('href="/u/nurul"')
    expect(html).to include('href="/t/klangvalley"')
    expect(html).to include(">#KlangValley</a>")
  end

  it "does not linkify a # inside a URL" do
    html = helper.format_body("see https://x.com/page#frag now")
    expect(html).not_to include('href="/t/frag"')
  end

  it "escapes a hostile hashtag (no live tag)" do
    expect(helper.format_body('#evil"><script>')).not_to include("<script>")
  end

  # Issue #11: markdown-style inline emphasis, tokenized on RAW text BEFORE
  # simple_format/auto_link (same private-use-marker technique as mentions/hashtags),
  # so no gsub ever runs over rendered HTML and the sanitizer allowlist is untouched.
  describe "inline emphasis (**bold** / *italic* / _underline_)" do
    it "renders **bold** as <strong> with no literal asterisks left" do
      out = helper.format_body("this is **bold** text")
      expect(out).to include("<strong>bold</strong>")
      expect(out).not_to include("**")
    end

    it "renders *italic* as <em> and _underline_ as <u>" do
      expect(helper.format_body("this is *italic* text")).to include("<em>italic</em>")
      expect(helper.format_body("this is _underline_ text")).to include("<u>underline</u>")
    end

    it "does not also match **bold** with the italic rule" do
      out = helper.format_body("this is **bold** text")
      expect(out).not_to include("<em>")
      expect(out).not_to include("*")
    end

    it "leaves underscores inside URLs and @handles untouched (boundary rule)" do
      out = helper.format_body("see https://en.wikipedia.org/wiki/Foo_bar_baz from @user_name")
      expect(out).not_to include("<u>")
      expect(out).to include("https://en.wikipedia.org/wiki/Foo_bar_baz")
      expect(out).to include('href="/u/user_name"')
    end

    it "escapes hostile content inside a bold span (no live tag)" do
      out = helper.format_body("**<script>alert(1)</script>**")
      expect(out).to include("<strong>")
      expect(out).not_to include("<script>")
    end

    it "wraps a rendered mention anchor inside a bold span" do
      out = helper.format_body("**hi @rudz**")
      expect(out).to include("<strong>")
      expect(out).to include('href="/u/rudz"')
      expect(out).to match(%r{<strong>hi <a[^>]*href="/u/rudz"[^>]*>@rudz</a></strong>})
    end

    it "renders an unclosed marker literally with no leaked private-use char" do
      out = helper.format_body("**dangling")
      expect(out).not_to include("<strong>")
      expect(out).to include("**dangling")
      expect(out).not_to include([0xE004].pack("U")) # STRONG_OPEN never leaks
    end

    it "does not format a span that straddles a newline (single-line rule)" do
      out = helper.format_body("**a\nb**")
      expect(out).not_to include("<strong>")
    end
  end
end
