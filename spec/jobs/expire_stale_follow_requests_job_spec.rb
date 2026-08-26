require "rails_helper"

RSpec.describe ExpireStaleFollowRequestsJob, type: :job do
  # The account the requests point at. Private so passive follows of it land pending.
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

  # created_at is set via update_column to bypass validation/callbacks - pending
  # rows are never touched after create, so created_at is the true age signal.
  def pending_follow(follower, age:)
    follow = follower.active_follows.create!(followed: target, status: :pending)
    follow.update_column(:created_at, age)
    follow
  end

  it "destroys a pending request older than 30 days and its follow_request notification" do
    requester = create(:user, username: "stale")
    follow = pending_follow(requester, age: 31.days.ago)
    expect(Notification.where(user: target, category: "follow_request", subject_user: requester).count).to eq(1)

    ExpireStaleFollowRequestsJob.perform_now

    expect(Follow.exists?(follow.id)).to be(false)
    expect(Notification.where(user: target, category: "follow_request", subject_user: requester).count).to eq(0)
  end

  it "leaves a pending request younger than 30 days untouched" do
    requester = create(:user, username: "fresh")
    follow = pending_follow(requester, age: 29.days.ago)

    ExpireStaleFollowRequestsJob.perform_now

    expect(Follow.exists?(follow.id)).to be(true)
    expect(follow.reload).to be_pending
  end

  it "leaves an old accepted follow untouched" do
    follower = create(:user, username: "accfollower")
    followed = create(:user, username: "accfollowed")
    follow = follower.active_follows.create!(followed: followed, status: :accepted)
    follow.update_column(:created_at, 90.days.ago)

    ExpireStaleFollowRequestsJob.perform_now

    expect(Follow.exists?(follow.id)).to be(true)
    expect(follow.reload).to be_accepted
    expect_counts_in_sync(follower, followed)
  end

  it "creates no notification of any category for the requester" do
    requester = create(:user, username: "silent")
    pending_follow(requester, age: 31.days.ago)

    expect {
      ExpireStaleFollowRequestsJob.perform_now
    }.not_to change { Notification.where(user: requester).count }
  end

  it "leaves both users' counter columns unchanged and in sync" do
    requester = create(:user, username: "counters")
    pending_follow(requester, age: 31.days.ago)
    # Pending never moved the counters; expiry must not move them either.
    expect(target.reload.followers_count).to eq(0)
    expect(requester.reload.following_count).to eq(0)

    ExpireStaleFollowRequestsJob.perform_now

    expect(target.reload.followers_count).to eq(0)
    expect(requester.reload.following_count).to eq(0)
    expect_counts_in_sync(target, requester)
  end

  it "logs and skips a row that raises, processing the rest" do
    good = create(:user, username: "goodreq")
    bad = create(:user, username: "badreq")
    good_follow = pending_follow(good, age: 31.days.ago)
    bad_follow = pending_follow(bad, age: 32.days.ago)

    # Blow up only the bad row's destroy; the good row must still be expired.
    allow_any_instance_of(Follow).to receive(:destroy).and_wrap_original do |original, *args|
      raise "boom" if original.receiver.id == bad_follow.id
      original.call(*args)
    end
    expect(Rails.logger).to receive(:error).with(/failed to expire follow #{bad_follow.id}/)

    ExpireStaleFollowRequestsJob.perform_now

    expect(Follow.exists?(good_follow.id)).to be(false)
    expect(Follow.exists?(bad_follow.id)).to be(true)
  end
end
