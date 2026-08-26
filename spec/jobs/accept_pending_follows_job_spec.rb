require "rails_helper"

RSpec.describe AcceptPendingFollowsJob, type: :job do
  # The account being flipped private->public. Starts private so passive follows
  # of it land pending.
  let(:target) { create(:user, username: "target", private: true) }

  # The drift tripwire, mirrored from spec/models/follow_counter_cache_spec.rb:
  # every counter column must equal its live accepted-only scope.
  def expect_counts_in_sync(*users)
    users.each do |user|
      user.reload
      expect(user.followers_count).to eq(user.followers.count),
        "followers_count drift for #{user.username}: column=#{user.followers_count} live=#{user.followers.count}"
      expect(user.following_count).to eq(user.following.count),
        "following_count drift for #{user.username}: column=#{user.following_count} live=#{user.following.count}"
    end
  end

  it "accepts every pending passive follow and fires all accept side effects" do
    requesters = Array.new(3) { |i| create(:user, username: "req#{i}") }
    pendings = requesters.map { |r| r.active_follows.create!(followed: target, status: :pending) }
    # An already-accepted passive follow must be left alone (no dup notifications).
    accepted_prior = create(:user, username: "prioracc")
      .active_follows.create!(followed: target, status: :accepted)

    # The job fires exactly one new_follower per newly-accepted row (3), not for the
    # already-accepted one (whose own new_follower fired at creation, before the job).
    expect {
      AcceptPendingFollowsJob.perform_now(target)
    }.to change { Notification.where(user: target, category: "new_follower").count }.by(3)

    # All pending became accepted; the pre-accepted row is untouched.
    expect(pendings.map { |f| f.reload.status }).to all(eq("accepted"))
    expect(accepted_prior.reload).to be_accepted

    # Each requester was told their request went through.
    requesters.each do |r|
      expect(Notification.where(user: r, category: "follow_accepted", subject_user: target).count).to eq(1)
    end

    # first_follower badge awarded exactly once (idempotent UserBadge.award).
    expect(target.user_badges.where(badge_key: "first_follower").count).to eq(1)
  end

  it "destroys the follow_request notification for each accepted row" do
    requesters = Array.new(2) { |i| create(:user, username: "dreq#{i}") }
    requesters.each { |r| r.active_follows.create!(followed: target, status: :pending) }
    # Each pending create fired a follow_request notification to the target.
    expect(Notification.where(user: target, category: "follow_request").count).to eq(2)

    AcceptPendingFollowsJob.perform_now(target)

    expect(Notification.where(user: target, category: "follow_request").count).to eq(0)
  end

  it "leaves counter columns in sync with the accepted-only scopes after the flip" do
    requesters = Array.new(3) { |i| create(:user, username: "creq#{i}") }
    requesters.each { |r| r.active_follows.create!(followed: target, status: :pending) }

    # While pending, nothing has moved.
    expect(target.reload.followers_count).to eq(0)

    AcceptPendingFollowsJob.perform_now(target)

    expect(target.reload.followers_count).to eq(3)
    requesters.each { |r| expect(r.reload.following_count).to eq(1) }
    expect_counts_in_sync(target, *requesters)
  end

  it "logs and skips a row that raises, processing the rest" do
    good = create(:user, username: "goodreq")
    bad = create(:user, username: "badreq")
    good_follow = good.active_follows.create!(followed: target, status: :pending)
    bad_follow = bad.active_follows.create!(followed: target, status: :pending)

    # Blow up only the bad row's accept; the good row must still be processed.
    allow_any_instance_of(Follow).to receive(:update!).and_wrap_original do |original, *args|
      raise "boom" if original.receiver.id == bad_follow.id
      original.call(*args)
    end
    expect(Rails.logger).to receive(:error).with(/failed to accept follow #{bad_follow.id}/)

    AcceptPendingFollowsJob.perform_now(target)

    expect(good_follow.reload).to be_accepted
    expect(bad_follow.reload).to be_pending
    expect_counts_in_sync(target, good)
  end
end
