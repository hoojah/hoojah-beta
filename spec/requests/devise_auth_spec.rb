# Hoojah 2026 redesign, Phase 1.1 — the Devise auth screens (log in / sign up)
# restyled to the 2026 visual language. This spec pins the FROZEN contracts that
# must survive the restyle untouched: Warden's field names, the invisible_captcha
# honeypot, and the fact that "Continue with Google" is decorative only (no
# OmniAuth is wired up, so it must never be a real link).
require "rails_helper"

RSpec.describe "Devise auth screens (Hoojah 2026 restyle)", type: :request do
  describe "GET /login" do
    before { get "/login" }

    it "renders the field names Warden authenticates on, unchanged by the restyle" do
      doc = Nokogiri::HTML.parse(response.body)
      expect(doc.at_css("input[name='user[email]']")).to be_present
      expect(doc.at_css("input[name='user[password]']")).to be_present
      expect(doc.at_css("input[name='user[remember_me]']")).to be_present
    end

    it "renders the 2026 hero headline" do
      doc = Nokogiri::HTML.parse(response.body)
      expect(doc.text).to include("Where Malaysia's brilliant minds debate.")
    end

    it "renders 'Continue with Google' as an inert button, never a link" do
      doc = Nokogiri::HTML.parse(response.body)

      anchors_with_google = doc.css("a").select { |a| a.text.include?("Continue with Google") }
      expect(anchors_with_google).to be_empty

      google_button = doc.css("button").find { |b| b.text.include?("Continue with Google") }
      expect(google_button).to be_present
      expect(google_button["type"]).to eq("button")
      expect(google_button["href"]).to be_nil
    end
  end

  describe "GET /signup" do
    before { get "/signup" }

    it "still renders the invisible_captcha honeypot field" do
      doc = Nokogiri::HTML.parse(response.body)
      expect(doc.at_css("input[name='subtitle']")).to be_present
    end

    it "still renders the password_confirmation field" do
      doc = Nokogiri::HTML.parse(response.body)
      expect(doc.at_css("input[name='user[password_confirmation]']")).to be_present
    end
  end
end
