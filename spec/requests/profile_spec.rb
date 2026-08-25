require "rails_helper"

RSpec.describe "Profile", type: :request do
  # let! (eager): the non-owner test patches /u/rudz before it otherwise touches
  # `user`, so rudz must exist up front or set_user 404s before authorization runs.
  let!(:user) { create(:user, username: "rudz") }

  it "shows a public profile with the user hoojahs" do
    create(:hujah, user: user, body: "hello world")
    get "/u/rudz"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("@rudz").and include("hello world")
  end

  # ── Per-post visibility (2026): profile hoojah list is scoped per viewer ─────────
  it "hides a public user's followers_only and private_only claims from a stranger" do
    create(:hujah, user: user, visibility: :visible_public, body: "PUBLIC profile claim body")
    create(:hujah, user: user, visibility: :followers_only, body: "FOLLOWERS profile secret")
    create(:hujah, user: user, visibility: :private_only, body: "PRIVATE profile secret")
    get "/u/rudz"
    expect(response.body).to include("PUBLIC profile claim body")
    expect(response.body).not_to include("FOLLOWERS profile secret")
    expect(response.body).not_to include("PRIVATE profile secret")
  end

  it "shows followers_only claims to an accepted follower, private_only only to self" do
    create(:hujah, user: user, visibility: :followers_only, body: "FOLLOWERS profile secret")
    create(:hujah, user: user, visibility: :private_only, body: "PRIVATE profile secret")
    fan = create(:user, username: "profilefan")
    fan.active_follows.create!(followed: user, status: :accepted)
    sign_in fan
    get "/u/rudz"
    expect(response.body).to include("FOLLOWERS profile secret")
    expect(response.body).not_to include("PRIVATE profile secret")

    sign_in user
    get "/u/rudz"
    expect(response.body).to include("PRIVATE profile secret")
  end

  it "lets the owner update and rejects a bad link (M7) / bad photo host" do
    sign_in user
    patch "/u/rudz", params: {user: {headline: "hi", link: "javascript:alert(1)"}},
      headers: {"Accept" => "text/vnd.turbo-stream.html"}
    expect(user.reload.headline).not_to eq("hi") # validation blocked the whole update
    patch "/u/rudz", params: {user: {photo: "https://res.cloudinary.com.evil.com/hoojah/x.jpg"}}
    expect(user.reload.photo).not_to include("evil.com")
  end

  it "attaches an uploaded avatar via multipart PATCH" do
    user = create(:user)
    sign_in user
    file = Rack::Test::UploadedFile.new(
      StringIO.new("\x89PNG\r\n\x1a\n".b + ("0".b * 50)), "image/png", original_filename: "me.png"
    )
    patch "/u/#{user.username}", params: {user: {avatar: file}}
    expect(user.reload.avatar).to be_attached
  end

  it "shows the followers list publicly (signed out)" do
    fan = create(:user, username: "fan")
    fan.active_follows.create!(followed: user, status: :accepted)
    get "/u/rudz/followers"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("@fan")
  end

  it "shows the following list publicly (signed out)" do
    idol = create(:user, username: "idol")
    user.active_follows.create!(followed: idol, status: :accepted)
    get "/u/rudz/following"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("@idol")
  end

  it "lets the owner toggle their account private" do
    sign_in user
    patch "/u/rudz", params: {user: {private: "1"}},
      headers: {"Accept" => "text/vnd.turbo-stream.html"}
    expect(user.reload).to be_private
  end

  it "auto-accepts pending follow requests when flipping private -> public" do
    user.update!(private: true)
    requester = create(:user, username: "req")
    pending = requester.active_follows.create!(followed: user, status: :pending)
    sign_in user
    patch "/u/rudz", params: {user: {private: "0"}},
      headers: {"Accept" => "text/vnd.turbo-stream.html"}
    expect(user.reload).not_to be_private
    expect(pending.reload).to be_accepted
  end

  it "forbids editing someone else" do
    sign_in create(:user)
    patch "/u/rudz", params: {user: {headline: "hacked"}},
      headers: {"Accept" => "text/vnd.turbo-stream.html"}
    expect(response).to have_http_status(:forbidden)
    expect(user.reload.headline).not_to eq("hacked")
  end

  # ── Hoojah 2026, Phase 4.4: gradient header + conviction card + live-debate ──────
  describe "the gradient header" do
    it "renders the gradient hero with badge chips and a surface: :gradient follow pill" do
      user.user_badges.create!(badge_key: "first_hoojah")
      other = create(:user, username: "viewer4")
      sign_in other
      get "/u/rudz"
      expect(response.body).to include("profile-hero")
      expect(response.body).to include("First Hoojah") # badge chip
      expect(response.body).to include("Follow") # on_primary variant pill text
    end

    it "surfaces the owner edit dialog behind the settings gear, not a bare pencil" do
      sign_in user
      get "/u/rudz"
      expect(response.body).to include("Edit your profile") # aria-label preserved
      expect(response.body).to include(ActionView::RecordIdentifier.dom_id(user, :edit_dialog))
    end
  end

  describe "the conviction card" do
    it "shows only real vote counts — no level, no percentage-to-next-level, no streak" do
      hujah_a = create(:hujah)
      hujah_b = create(:hujah)
      create(:vote, user: user, hujah: hujah_a, vote: [1])
      create(:vote, user: user, hujah: hujah_b, vote: [3], conviction: true)
      get "/u/rudz"
      expect(response.body).to include('data-testid="conviction-card"')
      expect(response.body).to match(%r{data-testid="conviction-votes-cast">\s*2\s*<})
      expect(response.body).not_to include("Lvl")
      expect(response.body).not_to include("% to")
      expect(response.body).not_to include("streak")
    end
  end

  describe "the live-debate card (LEAK PREVENTION)" do
    let!(:hoojah) { create(:hujah, user: user, body: "public transport should be free") }

    it "renders the card when both debate participants are visible to the viewer" do
      opponent = create(:user, username: "sitir")
      debate = create(:debate, hujah: hoojah, challenger: user, opponent: opponent, status: :active)
      stranger = create(:user, username: "stranger4")
      sign_in stranger
      get "/u/rudz"
      expect(response.body).to include("@sitir")
      expect(response.body).to include(debate_path(debate.slug))
    end

    it "hides the card from a stranger when the OTHER participant is a private non-follower" do
      private_opp = create(:user, username: "privateopp", private: true)
      debate = create(:debate, hujah: hoojah, challenger: user, opponent: private_opp, status: :active)
      stranger = create(:user, username: "stranger5")
      sign_in stranger
      get "/u/rudz"
      expect(response.body).not_to include("@privateopp")
      expect(response.body).not_to include(debate_path(debate.slug))
    end

    it "shows the card to an accepted follower of the private OTHER participant" do
      private_opp = create(:user, username: "privateopp2", private: true)
      debate = create(:debate, hujah: hoojah, challenger: user, opponent: private_opp, status: :active)
      follower = create(:user, username: "follower4")
      follower.active_follows.create!(followed: private_opp, status: :accepted)
      sign_in follower
      get "/u/rudz"
      expect(response.body).to include("@privateopp2")
      expect(response.body).to include(debate_path(debate.slug))
    end

    it "hides the card when the viewer has blocked the OTHER participant" do
      opponent = create(:user, username: "blockedopp")
      debate = create(:debate, hujah: hoojah, challenger: user, opponent: opponent, status: :active)
      blocker = create(:user, username: "blocker1")
      blocker.blocks_made.create!(blocked: opponent)
      sign_in blocker
      get "/u/rudz"
      expect(response.body).not_to include("@blockedopp")
      expect(response.body).not_to include(debate_path(debate.slug))
    end
  end

  describe "the gated header stays whitelist-only" do
    it "shows no conviction card and no live-debate card to a stranger of a private owner" do
      owner = create(:user, username: "privown", private: true)
      hoojah = create(:hujah, user: owner, body: "private owner claim")
      opp = create(:user, username: "privownopp")
      create(:debate, hujah: hoojah, challenger: owner, opponent: opp, status: :active)
      create(:vote, user: owner, hujah: create(:hujah), vote: [1])
      stranger = create(:user, username: "gatestranger")
      sign_in stranger
      get "/u/privown"
      expect(response.body).to include("This account is private")
      expect(response.body).not_to include('data-testid="conviction-card"')
      expect(response.body).not_to include("@privownopp")
    end
  end

  # ── Hoojah 2026, Phase 4.5: profile count tabs ────────────────────────────────
  describe "the profile count tabs" do
    it "shows three tab links with counts, hoojahs active by default" do
      create(:hujah, user: user, body: "top level tab claim")
      parent = create(:hujah)
      create(:hujah, user: user, parent: parent, body: "a reply for tab count")
      debate_hoojah = create(:hujah, user: user, body: "debate tab hoojah")
      create(:debate, hujah: debate_hoojah, challenger: user, opponent: create(:user), status: :concluded)

      get "/u/rudz"
      expect(response.body).to include('id="profile-list"')
      expect(response.body).to include('data-testid="profile-tab-hoojahs"')
      expect(response.body).to include('data-testid="profile-tab-responses"')
      expect(response.body).to include('data-testid="profile-tab-debates"')
      expect(response.body).to include("top level tab claim")
      expect(response.body).not_to include("a reply for tab count")
    end

    it "switches to the responses tab via ?tab=responses" do
      parent = create(:hujah)
      create(:hujah, user: user, parent: parent, body: "visible reply body for tab test")
      get "/u/rudz?tab=responses"
      expect(response.body).to include("visible reply body for tab test")
    end

    it "switches to the debates tab via ?tab=debates" do
      hoojah = create(:hujah, user: user, body: "debate anchor for tab test")
      opponent = create(:user, username: "tabopponent")
      debate = create(:debate, hujah: hoojah, challenger: user, opponent: opponent, status: :concluded)
      get "/u/rudz?tab=debates"
      expect(response.body).to include(debate_path(debate.slug))
    end
  end

  # ── LEAK: a reply's visibility is governed by its PARENT, not by the (visible)
  # profile owner alone. Hujah#visible_to? recurses through parent.visible_to?, so
  # the Responses tab must filter with it in Ruby, not just query the owner's replies.
  describe "the responses tab (LEAK: reply visibility depends on parent)" do
    let!(:hidden_owner) { create(:user, username: "hiddenowner") }
    let!(:followers_only_parent) do
      create(:hujah, user: hidden_owner, visibility: :followers_only, body: "FOLLOWERS parent claim")
    end
    # `HujahPolicy#create?` already requires the replier to see the parent (a
    # non-follower can't write into a thread they can't read), so a realistic
    # reply-author was an accepted follower at write time — and stays one here,
    # which is what lets them see their own reply below.
    let!(:reply) do
      user.active_follows.create!(followed: hidden_owner, status: :accepted)
      create(:hujah, user: user, parent: followers_only_parent, body: "RUDZ REPLY under followers-only parent")
    end

    it "hides the reply from a stranger who cannot see the parent" do
      stranger = create(:user, username: "respstranger")
      sign_in stranger
      get "/u/rudz?tab=responses"
      expect(response.body).not_to include("RUDZ REPLY under followers-only parent")
    end

    it "shows the reply to an accepted follower of the parent's author" do
      follower = create(:user, username: "respfollower")
      follower.active_follows.create!(followed: hidden_owner, status: :accepted)
      sign_in follower
      get "/u/rudz?tab=responses"
      expect(response.body).to include("RUDZ REPLY under followers-only parent")
    end

    it "shows the reply to the profile owner themself" do
      sign_in user
      get "/u/rudz?tab=responses"
      expect(response.body).to include("RUDZ REPLY under followers-only parent")
    end
  end

  # ── LEAK: the Debates tab must use DebatePolicy::Scope, not a raw participant list —
  # a stranger must not learn the identity/existence of a debate whose OTHER
  # participant is private/blocked to them.
  describe "the debates tab (LEAK: policy_scope filters by co-participant visibility)" do
    let!(:hoojah) { create(:hujah, user: user, body: "debate host claim for tabs") }

    it "hides a concluded debate from a stranger when the other participant is private" do
      private_opp = create(:user, username: "debtabopp", private: true)
      debate = create(:debate, hujah: hoojah, challenger: user, opponent: private_opp, status: :concluded)
      stranger = create(:user, username: "debtabstranger")
      sign_in stranger
      get "/u/rudz?tab=debates"
      expect(response.body).not_to include("@debtabopp")
      expect(response.body).not_to include(debate_path(debate.slug))
    end

    it "shows the debate to an accepted follower of the private other participant" do
      private_opp = create(:user, username: "debtabopp2", private: true)
      debate = create(:debate, hujah: hoojah, challenger: user, opponent: private_opp, status: :concluded)
      follower = create(:user, username: "debtabfollower")
      follower.active_follows.create!(followed: private_opp, status: :accepted)
      sign_in follower
      get "/u/rudz?tab=debates"
      expect(response.body).to include("@debtabopp2")
      expect(response.body).to include(debate_path(debate.slug))
    end

    it "shows an active debate to the other participant themself" do
      private_opp = create(:user, username: "debtabopp3", private: true)
      debate = create(:debate, hujah: hoojah, challenger: user, opponent: private_opp, status: :active)
      sign_in private_opp
      get "/u/rudz?tab=debates"
      expect(response.body).to include(debate_path(debate.slug))
    end
  end
end
