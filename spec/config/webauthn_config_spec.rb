require "rails_helper"

RSpec.describe "WebAuthn configuration" do
  it "uses the localhost origin in the test environment" do
    expect(WebAuthn.configuration.origin).to eq("http://localhost:3000")
  end

  it "sets the relying-party name to Hoojah" do
    expect(WebAuthn.configuration.rp_name).to eq("Hoojah")
  end
end
