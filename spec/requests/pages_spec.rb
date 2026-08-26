require "rails_helper"

RSpec.describe "Pages", type: :request do
  # Public informational pages (FAQ / Privacy / Terms). These are the same shape as
  # /trending: skip_authorization, reachable while signed out. Two axes matter here —
  # anonymous visitors get 200 (they are the point of these pages), and a signed-in
  # visitor also gets 200 (a regression guard on ApplicationController's
  # after_action :verify_authorized, which would raise if the action forgot to
  # authorize/skip_authorization).
  pages = {
    "/faq" => {heading: "Frequently Asked Questions", marker: "secret ballot"},
    "/privacy" => {heading: "Privacy Policy", marker: "Personal Data Protection Act 2010"},
    "/terms" => {heading: "Terms of Service", marker: "laws of Malaysia"}
  }

  pages.each do |path, expected|
    describe "GET #{path}" do
      it "renders publicly (no user signed in)" do
        get path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(expected[:heading])
        expect(response.body).to include("Last updated:")
        expect(response.body).to include(expected[:marker])
      end

      it "renders for a signed-in user (verify_authorized regression guard)" do
        login_as(create(:user))
        get path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(expected[:heading])
        expect(response.body).to include("Last updated:")
        expect(response.body).to include(expected[:marker])
      end
    end
  end
end
