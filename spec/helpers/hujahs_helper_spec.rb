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
end
