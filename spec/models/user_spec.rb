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
end
