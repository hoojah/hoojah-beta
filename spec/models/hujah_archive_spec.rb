require "rails_helper"

RSpec.describe HujahArchive, type: :model do
  describe "associations + persistence" do
    it "persists a snapshot and lists its participants" do
      hujah = create(:hujah)
      archive = HujahArchive.create!(
        hujah_id: hujah.id,
        snapshot: {"body" => hujah.body, "arguments" => []},
        visibility_before: Hujah.visibilities[:visible_public],
        token: "abc123"
      )
      purged = create(:user)
      archive.participants.create!(user: purged)

      expect(archive.reload.snapshot["body"]).to eq(hujah.body)
      expect(archive.participants.map(&:user_id)).to eq([purged.id])
    end

    it "survives deletion of the live hoojah (FK-less hujah_id)" do
      hujah = create(:hujah)
      archive = create(:hujah_archive, hujah: hujah, hujah_id: hujah.id)
      hujah.destroy!
      expect(HujahArchive.find(archive.id).hujah_id).to eq(hujah.id)
    end
  end

  describe ".for" do
    it "returns the viewer's LATEST participant row for a hoojah, or nil" do
      hujah = create(:hujah)
      user = create(:user)
      old = create(:hujah_archive, hujah: hujah, hujah_id: hujah.id)
      old.participants.create!(user: user)
      newer = create(:hujah_archive, hujah: hujah, hujah_id: hujah.id)
      newer.participants.create!(user: user)

      found = HujahArchiveParticipant.for(user, hujah).first
      expect(found.archive_id).to eq(newer.id)
      expect(HujahArchiveParticipant.for(create(:user), hujah).first).to be_nil
    end
  end
end
