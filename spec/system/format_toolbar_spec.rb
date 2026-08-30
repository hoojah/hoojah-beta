require "rails_helper"

# Issue #11: the format toolbar wraps the current textarea selection with markdown
# tokens (**/ */ _) and dispatches an `input` event so the co-resident composer
# controller's char-counter / send-button state stays in sync. The tokens are parsed
# server-side at render time by HujahsHelper#format_body.
RSpec.describe "Format toolbar", :js do
  let(:user) { create(:user) }

  it "wraps the selection in bold tokens and renders <strong> on the show page" do
    sign_in user
    visit new_hujah_path

    fill_in "hujah[body]", with: "make this bold please"

    # Select the word "bold" (chars 10..14) inside the textarea, then click Bold.
    page.execute_script(<<~JS)
      const ta = document.querySelector("textarea[name='hujah[body]']");
      ta.focus();
      ta.setSelectionRange(10, 14);
    JS
    find("button[data-action='format-toolbar#bold']").click

    value = page.evaluate_script("document.querySelector(\"textarea[name='hujah[body]']\").value")
    expect(value).to include("**bold**")

    click_button "Post"

    expect(page).to have_css("strong", text: "bold")
  end
end
