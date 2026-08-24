require "rails_helper"

# `users/_follow_button` restyled for two surfaces (Hoojah 2026, Phase 2.4): `:card`
# (the new default — a card/white background, e.g. a search result row) and
# `:gradient` (the ORIGINAL on_primary/on_primary_outline treatment, reused
# byte-for-byte, for the blue/gradient profile hero). Every existing state
# (Follow/Following/Requested/Unblock/Block) and every `button_to` path+verb must stay
# IDENTICAL across both surfaces — only the CSS class string may differ.
RSpec.describe "users/_follow_button", type: :view do
  let(:viewer) { create(:user) }
  let(:target) { create(:user, username: "target") }

  before do
    allow(view).to receive(:user_signed_in?).and_return(true)
    allow(view).to receive(:current_user).and_return(viewer)
  end

  def html(**locals)
    render(partial: "users/follow_button", locals: {user: target}.merge(locals)).strip
  end

  def button(**locals)
    Capybara.string(html(**locals))
  end

  describe "surface: :card (the default)" do
    it "renders Follow as a thin primary-outline pill on a card background" do
      expect(button).to have_css("form button.border.border-primary.text-primary.bg-card", text: "Follow")
      expect(button).to have_no_css("button.border-2")
    end

    it "renders Following as a solid primary pill" do
      viewer.active_follows.create!(followed: target, status: :accepted)

      expect(button).to have_css("form button.bg-primary.text-white", text: "Following")
    end

    it "renders Requested as the same solid pill (no translucency) when there is a pending request" do
      target.update!(private: true)
      viewer.active_follows.create!(followed: target, status: :pending)

      expect(button).to have_css("form button.bg-primary.text-white", text: "Requested")
      expect(button).to have_no_css("button.opacity-50, button.opacity-70")
    end

    it "renders Unblock as the solid pill when the viewer blocked the target" do
      viewer.blocks_made.create!(blocked: target)

      expect(button).to have_css("form button.bg-primary.text-white", text: "Unblock")
      expect(button).to have_no_css("button", text: "Follow")
    end

    it "offers Block-only, never Follow, when the target blocked the viewer" do
      target.blocks_made.create!(blocked: viewer)

      expect(button).to have_css("form button.border.border-primary.text-primary.bg-card", text: "Block")
      expect(button).to have_no_css("button", text: "Follow")
    end

    it "keeps the secondary Block pill quieter via opacity-80, riding alongside Follow" do
      expect(button).to have_css("form button.opacity-80", text: "Block")
    end

    it "is what an unpassed surface: local renders (nil == :card)" do
      expect(html).to eq(html(surface: :card))
    end
  end

  describe "surface: :gradient" do
    it "renders Follow as the original white-outline-on-primary pill" do
      expect(button(surface: :gradient)).to have_css("form button.border.border-white.text-white", text: "Follow")
    end

    it "renders Following as the original solid white pill" do
      viewer.active_follows.create!(followed: target, status: :accepted)

      expect(button(surface: :gradient)).to have_css("form button.bg-white.text-primary", text: "Following")
    end

    it "matches ds_button_classes(variant: :on_primary_outline) exactly, unchanged by this restyle" do
      expect(button(surface: :gradient)).to have_css("form button.rounded-full.border.border-white.text-white", text: "Follow")
    end
  end

  describe "surface is a pure restyle — behaviour is identical either way" do
    it "posts to the identical button_to path/verb on both surfaces" do
      card_html = button
      gradient_html = button(surface: :gradient)

      expect(card_html).to have_css("form[action='#{follow_user_path(target.username)}'][method='post']")
      expect(gradient_html).to have_css("form[action='#{follow_user_path(target.username)}'][method='post']")
    end

    it "keeps the Following → unfollow DELETE path identical on both surfaces" do
      viewer.active_follows.create!(followed: target, status: :accepted)

      [button, button(surface: :gradient)].each do |rendered|
        expect(rendered).to have_css("form[action='#{unfollow_user_path(target.username)}']")
        expect(rendered).to have_css("form input[name='_method'][value='delete']", visible: :hidden)
      end
    end

    it "raises on an unknown surface rather than silently rendering a default" do
      expect { button(surface: :neon) }.to raise_error(ActionView::Template::Error, /neon/)
    end
  end
end
