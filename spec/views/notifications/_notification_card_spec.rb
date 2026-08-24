require "rails_helper"

# Hoojah 2026 redesign (Phase 4, Task 4.2): the notification card restyle — rounded-2xl
# surface, read/unread accent (unchanged mechanism from Slice 9), a 36px soft-tint icon
# tile or an actor avatar tile, bolded actor copy, a trailing unread dot, inline
# debate_challenge accept/decline, and the trash control moved into an overflow menu.
RSpec.describe "notifications/_notification_card", type: :view do
  include ActionView::RecordIdentifier

  let(:me) { create(:user, username: "me") }

  before do
    allow(view).to receive_messages(current_user: me, user_signed_in?: true)
  end

  def html(notification)
    render(partial: "notifications/notification_card", locals: {notification: notification}).strip
  end

  def card(notification)
    Capybara.string(html(notification))
  end

  describe "the row surface" do
    it "is a rounded-2xl card carrying the unread accent while unread" do
      n = create(:notification, user: me, read: false)
      expect(card(n)).to have_css("div.rounded-2xl.border-l-8.border-unread##{dom_id(n)}")
    end

    it "carries the read accent instead once marked read" do
      n = create(:notification, user: me, read: true)
      expect(card(n)).to have_css("div.border-l-8.border-read##{dom_id(n)}")
      expect(card(n)).to have_no_css("div.border-unread")
    end
  end

  describe "the icon tile" do
    it "tints a debate_challenge tile disagree" do
      rival = create(:user, username: "rival")
      debate = create(:debate, opponent: me, challenger: rival, status: :pending)
      n = create(:notification, user: me, category: :debate_challenge,
        debate: debate, hujah: debate.hujah, subject_user: rival)
      expect(card(n)).to have_css("span.w-9.h-9.rounded-xl.bg-disagree-soft.text-disagree")
    end

    it "tints a badge_earned tile agree" do
      n = create(:notification, user: me, category: :badge_earned, hujah: nil, subject_user: nil, body: "sharp_tongue")
      expect(card(n)).to have_css("span.bg-agree-soft.text-agree")
    end

    it "tints a new_follower tile primary" do
      follower = create(:user, username: "follower1")
      n = create(:notification, user: me, category: :new_follower, hujah: nil, subject_user: follower)
      expect(card(n)).to have_css("span.bg-primary-soft.text-primary")
    end

    it "tints a new_vote tile primary, with no avatar tile" do
      hujah = create(:hujah, user: me)
      n = create(:notification, user: me, category: :new_vote, hujah: hujah, subject_user: nil)
      c = card(n)
      expect(c).to have_css("span.bg-primary-soft.text-primary")
      expect(c).to have_no_css("[role='img'].avatar-tile")
    end
  end

  describe "the avatar tile" do
    it "renders the actor's gradient-initials tile for a new_hoojah_response" do
      replier = create(:user, username: "replier", full_name: "Ravi Kumar")
      hujah = create(:hujah, user: me)
      n = create(:notification, user: me, category: :new_hoojah_response,
        hujah: hujah, subject_user: replier)
      expect(card(n)).to have_css("span[role='img'].avatar-tile", text: "RK")
    end
  end

  describe "the copy" do
    it "bolds the actor's handle" do
      rival = create(:user, username: "rival")
      n = create(:notification, user: me, category: :new_follower, hujah: nil, subject_user: rival)
      expect(card(n)).to have_css("strong", text: "@rival")
    end
  end

  describe "the unread dot" do
    it "shows a bg-neutral dot on an unread row" do
      n = create(:notification, user: me, read: false)
      expect(card(n)).to have_css("span[aria-hidden='true'].bg-neutral.rounded-full")
    end

    it "shows no dot once the row is read" do
      n = create(:notification, user: me, read: true)
      expect(card(n)).to have_no_css("span[aria-hidden='true'].bg-neutral.rounded-full")
    end
  end

  describe "debate_challenge inline accept/decline" do
    it "offers Accept/Decline posting to the existing debate paths while pending" do
      rival = create(:user, username: "rival")
      debate = create(:debate, opponent: me, challenger: rival, status: :pending)
      n = create(:notification, user: me, category: :debate_challenge,
        debate: debate, hujah: debate.hujah, subject_user: rival)
      markup = html(n)
      expect(markup).to include(%(action="#{accept_debate_path(debate.slug)}"))
      expect(markup).to include(%(action="#{decline_debate_path(debate.slug)}"))
      expect(card(n)).to have_button("Accept")
      expect(card(n)).to have_button("Decline")
    end

    it "drops the buttons once the challenge is no longer pending" do
      rival = create(:user, username: "rival")
      debate = create(:debate, opponent: me, challenger: rival, status: :declined)
      n = create(:notification, user: me, category: :debate_challenge,
        debate: debate, hujah: debate.hujah, subject_user: rival)
      expect(html(n)).not_to include(%(action="#{accept_debate_path(debate.slug)}"))
    end
  end

  describe "the follow_request inline accept/decline" do
    it "is preserved unchanged" do
      requester = create(:user, username: "requester")
      create(:follow, follower: requester, followed: me, status: :pending)
      n = create(:notification, user: me, category: :follow_request, hujah: nil, subject_user: requester)
      c = card(n)
      expect(c).to have_button("Accept")
      expect(c).to have_button("Decline")
    end
  end

  describe "the overflow menu" do
    it "moves the trash control behind a More options trigger rather than an always-visible button" do
      n = create(:notification, user: me)
      c = card(n)
      expect(c).to have_css("summary[aria-label='More options']")
      # `visible: :all`: Capybara's static-HTML matcher applies real `<details>`
      # semantics — content is invisible until `open`, same as a real browser — so
      # this proves the delete control is present, structurally inside the closed
      # menu, and NOT the always-visible per-row button it used to be.
      expect(c).to have_css(
        "details form[action='#{notification_path(n)}'] button[aria-label='Delete notification']",
        visible: :all
      )
      expect(c).to have_no_css("button[aria-label='Delete notification']")
    end
  end

  describe "secret ballot — new_vote" do
    it "renders no voter identity anywhere on the row" do
      hujah = create(:hujah, user: me)
      n = create(:notification, user: me, category: :new_vote, hujah: hujah, subject_user: nil)
      expect(n.subject_user_id).to be_nil
      c = card(n)
      expect(c).to have_no_css("strong")
      expect(c).to have_no_css("[role='img'].avatar-tile")
      expect(c).to have_content("You have a new vote on your hoojah")
    end
  end
end
