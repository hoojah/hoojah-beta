# Hoojah 2026 redesign, Phase 1.1 — the one bit of real interactivity the auth
# restyle adds: an inline password-reveal toggle on the log-in screen, backed by
# the new `password_visibility` Stimulus controller.
require "rails_helper"

RSpec.describe "Auth screens redesign", :js do
  before(:all) { TailwindBuild.once! }

  it "reveals and re-masks the password when the eye toggle is clicked" do
    visit new_user_session_path

    password_field = find_field(name: "user[password]")
    expect(password_field[:type]).to eq("password")

    find("[data-action='password-visibility#toggle']").click
    expect(find_field(name: "user[password]")[:type]).to eq("text")

    find("[data-action='password-visibility#toggle']").click
    expect(find_field(name: "user[password]")[:type]).to eq("password")
  end
end
