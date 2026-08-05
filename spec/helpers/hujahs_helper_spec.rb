require 'rails_helper'

RSpec.describe HujahsHelper, type: :helper do
  it 'linkifies URLs and escapes script tags' do
    out = helper.format_body("See https://hoojah.my now <script>alert(1)</script>")
    expect(out).to include('href="https://hoojah.my"')
    expect(out).to include('rel="noopener"')
    expect(out).not_to include('<script>')
  end

  it 'preserves newlines as paragraphs' do
    expect(helper.format_body("a\n\nb")).to include('</p>')
  end
end
