require "rails_helper"

RSpec.describe User, type: :model do
  it "authenticates a pre-existing bcrypt password via Devise (no re-hash)" do
    user = User.create!(full_name: "A", username: "a_user", email: "A@X.com", password: "hoojah88")
    expect(user.email).to eq("a@x.com")                       # downcased
    expect(user.valid_password?("hoojah88")).to be(true)       # Devise validates
    expect(user).to respond_to(:reset_password_token)
  end

  it "still requires a unique username" do
    User.create!(full_name: "A", username: "dup", email: "a@x.com", password: "hoojah88")
    dup = User.new(full_name: "B", username: "dup", email: "b@x.com", password: "hoojah88")
    expect(dup).not_to be_valid
  end

  it "assigns a random photo after create" do
    user = User.create!(full_name: "A", username: "ph", email: "ph@x.com", password: "hoojah88")
    expect(user.photo).to be_present
  end

  it "rejects a non-http link (M7)" do
    u = build(:user, link: "javascript:alert(1)")
    expect(u).not_to be_valid
    expect(build(:user, link: "https://ok.example")).to be_valid
    expect(build(:user, link: "")).to be_valid
  end

  it "accepts only a hoojah Cloudinary photo host (exact host)" do
    expect(build(:user, photo: "https://res.cloudinary.com/hoojah/image/upload/x.jpg")).to be_valid
    expect(build(:user, photo: "https://res.cloudinary.com.evil.com/hoojah/x.jpg")).not_to be_valid
    expect(build(:user, photo: "https://res.cloudinary.com@evil.com/hoojah/x.jpg")).not_to be_valid
    expect(build(:user, photo: "http://res.cloudinary.com/hoojah/x.jpg")).not_to be_valid
  end

  it "rejects reserved / malformed usernames" do
    expect(build(:user, username: "login")).not_to be_valid
    expect(build(:user, username: "has space")).not_to be_valid
  end

  it "assigns a random photo that passes the Cloudinary validation" do
    User.random_photo # sample
    user = create(:user)
    expect(user).to be_valid
    expect(user.photo).to be_present
  end

  # Canonical SQL visibility scope for LIST surfaces (search, Phase 2). Must match
  # User#visible_to? exactly.
  describe ".visible_to scope" do
    let(:public_user) { create(:user, private: false) }
    let(:private_user) { create(:user, private: true) }
    let(:viewer) { create(:user) }
    let(:follower) { create(:user) }
    let(:stranger) { create(:user) }

    before do
      follower.active_follows.create!(followed: private_user, status: :accepted)
    end

    it "includes a public account" do
      expect(User.visible_to(viewer)).to include(public_user)
    end

    it "excludes a private account not visible to the viewer (non-follower)" do
      expect(User.visible_to(stranger)).not_to include(private_user)
    end

    it "includes a private account for an accepted follower" do
      expect(User.visible_to(follower)).to include(private_user)
    end

    it "includes a private account for itself" do
      expect(User.visible_to(private_user)).to include(private_user)
    end

    it "excludes users in viewer.hidden_user_ids (blocked or blocking)" do
      blocked = create(:user, private: false)
      viewer.blocks_made.create!(blocked: blocked)

      blocker = create(:user, private: false)
      blocker.blocks_made.create!(blocked: viewer)

      expect(User.visible_to(viewer)).not_to include(blocked)
      expect(User.visible_to(viewer)).not_to include(blocker)
    end

    context "anonymous viewer (nil)" do
      it "excludes all private accounts" do
        expect(User.visible_to(nil)).not_to include(private_user)
      end

      it "includes public accounts" do
        expect(User.visible_to(nil)).to include(public_user)
      end
    end

    it "agrees with User#visible_to? on a sample of accounts" do
      samples = [public_user, private_user]
      [viewer, follower, stranger, private_user, nil].each do |v|
        scoped_ids = User.visible_to(v).pluck(:id)
        samples.each do |u|
          expect(scoped_ids.include?(u.id)).to eq(u.visible_to?(v)),
            "mismatch for user=#{u.id} viewer=#{v&.id.inspect} private=#{u.private}"
        end
      end
    end
  end

  # Phase 2.2 search scope — reuses .visible_to (proven above) then filters by
  # username/full_name. Leak coverage lives end-to-end in spec/requests/search_spec.rb.
  describe ".search" do
    let(:viewer) { create(:user) }

    it "matches a case-insensitive substring of the username" do
      u = create(:user, username: "klangvalleyfan")
      expect(User.search("KLANGVALLEY", viewer: viewer)).to include(u)
    end

    it "matches a case-insensitive substring of the full_name" do
      u = create(:user, full_name: "Siti Rahman")
      expect(User.search("rahman", viewer: viewer)).to include(u)
    end

    it "excludes a non-matching account" do
      u = create(:user, username: "nomatchhere", full_name: "Nobody Related")
      expect(User.search("zzz-no-match", viewer: viewer)).not_to include(u)
    end

    it "treats % and _ as literal characters, not SQL wildcards (sanitize_sql_like)" do
      literal = create(:user, username: "has_underscore")
      no_underscore = create(:user, username: "hasXunderscore")
      results = User.search("has_underscore", viewer: viewer)
      expect(results).to include(literal)
      expect(results).not_to include(no_underscore)
    end

    it "caps results at 8" do
      9.times { |n| create(:user, username: "capuser#{n}") }
      expect(User.search("capuser", viewer: viewer).size).to eq(8)
    end
  end

  describe "#visible_hujahs_for" do
    let(:owner) { create(:user) }
    let(:viewer) { create(:user) }

    it "returns only visible_public top-level hoojahs to a stranger/anonymous" do
      pub = create(:hujah, user: owner, visibility: :visible_public)
      create(:hujah, user: owner, visibility: :followers_only)
      create(:hujah, user: owner, visibility: :private_only)
      create(:hujah, user: owner, visibility: :visible_public, parent: create(:hujah)) # a reply
      expect(owner.visible_hujahs_for(nil)).to contain_exactly(pub)
      expect(owner.visible_hujahs_for(viewer)).to contain_exactly(pub)
    end

    it "adds followers_only for an accepted follower" do
      pub = create(:hujah, user: owner, visibility: :visible_public)
      fo = create(:hujah, user: owner, visibility: :followers_only)
      create(:hujah, user: owner, visibility: :private_only)
      owner.passive_follows.create!(follower: viewer, status: :accepted)
      expect(owner.visible_hujahs_for(viewer)).to contain_exactly(pub, fo)
    end

    it "returns all top-level hoojahs to the owner themselves" do
      a = create(:hujah, user: owner, visibility: :visible_public)
      b = create(:hujah, user: owner, visibility: :private_only)
      expect(owner.visible_hujahs_for(owner)).to contain_exactly(a, b)
    end
  end

  describe "avatar attachment" do
    let(:user) { create(:user) }

    it "accepts an image attachment" do
      user.avatar.attach(io: StringIO.new("fakeimg"), filename: "a.png", content_type: "image/png")
      expect(user).to be_valid
      expect(user.avatar).to be_attached
    end

    it "rejects a non-image content type" do
      user.avatar.attach(io: StringIO.new("nope"), filename: "a.txt", content_type: "text/plain")
      expect(user).not_to be_valid
      expect(user.errors[:avatar].join).to match(/PNG|image/i)
    end

    it "rejects an oversized image" do
      user.avatar.attach(io: StringIO.new("x" * (6 * 1024 * 1024)), filename: "big.png", content_type: "image/png")
      expect(user).not_to be_valid
      expect(user.errors[:avatar].join).to match(/5 MB|smaller/i)
    end
  end

  describe ".generate_username" do
    it "slugifies to allowed characters" do
      expect(User.generate_username("Jane.Doe")).to eq("janedoe")
    end

    it "appends a numeric suffix on collision" do
      create(:user, username: "janedoe")
      expect(User.generate_username("jane.doe")).to eq("janedoe2")
    end

    it "avoids reserved usernames" do
      expect(User.generate_username("admin")).not_to eq("admin")
    end
  end

  describe ".from_omniauth" do
    def auth(email:, name: "Jane Doe", uid: "123")
      OmniAuth::AuthHash.new(
        provider: "google_oauth2", uid: uid,
        info: {email: email, name: name}
      )
    end

    it "creates a new user with a generated username and random password" do
      expect {
        @user = User.from_omniauth(auth(email: "new.person@gmail.com"))
      }.to change(User, :count).by(1)
      expect(@user).to be_persisted
      expect(@user.username).to eq("newperson")
      expect(@user.provider).to eq("google_oauth2")
      expect(@user.uid).to eq("123")
    end

    it "auto-links to an existing account by email" do
      existing = create(:user, email: "taken@gmail.com")
      expect {
        found = User.from_omniauth(auth(email: "TAKEN@gmail.com", uid: "999"))
        expect(found.id).to eq(existing.id)
      }.not_to change(User, :count)
      expect(existing.reload.uid).to eq("999")
    end

    it "returns the same user on repeat login by provider+uid" do
      first = User.from_omniauth(auth(email: "again@gmail.com", uid: "555"))
      expect {
        second = User.from_omniauth(auth(email: "again@gmail.com", uid: "555"))
        expect(second.id).to eq(first.id)
      }.not_to change(User, :count)
    end

    it "returns an errored, unpersisted user when Google gives no email" do
      user = User.from_omniauth(OmniAuth::AuthHash.new(provider: "google_oauth2", uid: "nomail", info: {name: "No Email"}))
      expect(user).not_to be_persisted
      expect(user.errors[:base].join).to match(/verified email/i)
    end

    it "refuses to transfer an email already linked to a different Google account" do
      existing = create(:user, email: "linked@gmail.com")
      existing.update_columns(provider: "google_oauth2", uid: "original")
      result = User.from_omniauth(OmniAuth::AuthHash.new(provider: "google_oauth2", uid: "attacker", info: {email: "linked@gmail.com", name: "X"}))
      expect(result.errors[:base].join).to match(/already linked/i)
      expect(existing.reload.uid).to eq("original")
    end
  end
end
