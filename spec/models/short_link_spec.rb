require "rails_helper"

RSpec.describe ShortLink, type: :model do
  describe ".for" do
    it "creates a row with a 7-char code and the hoojah's internal path" do
      hujah = create(:hujah)
      link = ShortLink.for(hujah)

      expect(link).to be_persisted
      expect(link.code.length).to eq(7)
      expect(link.target_path).to eq("/hoojah/#{hujah.slug}")
    end

    it "is idempotent — calling twice returns the SAME record" do
      hujah = create(:hujah)

      first = ShortLink.for(hujah)
      second = ShortLink.for(hujah)

      expect(second.id).to eq(first.id)
      expect(ShortLink.where(target_path: "/hoojah/#{hujah.slug}").count).to eq(1)
    end

    it "maps a Debate to its /debates/<slug> path" do
      debate = create(:debate)
      link = ShortLink.for(debate)

      expect(link.target_path).to eq("/debates/#{debate.slug}")
    end

    it "raises ArgumentError for an unsupported record type" do
      user = create(:user)
      expect { ShortLink.for(user) }.to raise_error(ArgumentError)
    end
  end

  describe "target_path validation (open-redirect guard)" do
    # The format check IS the open-redirect defense: nothing absolute,
    # protocol-relative, path-traversing, or outside the two share surfaces
    # can ever be stored.
    [
      "https://evil.com",
      "//evil.com",
      "/u/someone",
      "/hoojah/../etc",
      "/hoojah/x/y"
    ].each do |bad_path|
      it "rejects #{bad_path.inspect}" do
        link = ShortLink.new(code: SecureRandom.alphanumeric(7), target_path: bad_path)
        expect(link).not_to be_valid
        expect(link.errors[:target_path]).to be_present
      end
    end

    it "accepts a well-formed /hoojah path" do
      link = ShortLink.new(code: SecureRandom.alphanumeric(7), target_path: "/hoojah/some-slug")
      expect(link).to be_valid
    end

    it "accepts a well-formed /debates path" do
      link = ShortLink.new(code: SecureRandom.alphanumeric(7), target_path: "/debates/some-slug")
      expect(link).to be_valid
    end
  end
end
