require "rails_helper"

# Accepted-only counter caches (gap 8). Every example ends with the drift check:
# the columns must equal the live accepted-only scopes for the users involved. Any
# silently-broken mutation path fails loudly here.
RSpec.describe "Follow counter caches", type: :model do
  let(:actor) { create(:user) }
  let(:public_target) { create(:user, private: false) }
  let(:private_target) { create(:user, private: true) }

  # The tripwire: columns vs live accepted-only scopes, per user.
  def expect_counts_in_sync(*users)
    users.each do |user|
      user.reload
      expect(user.followers_count).to eq(user.followers.count),
        "followers_count drift for #{user.username}: column=#{user.followers_count} live=#{user.followers.count}"
      expect(user.following_count).to eq(user.following.count),
        "following_count drift for #{user.username}: column=#{user.following_count} live=#{user.following.count}"
    end
  end

  it "increments both columns on an accepted create (public target)" do
    actor.active_follows.create!(followed: public_target, status: :accepted)

    expect(public_target.reload.followers_count).to eq(1)
    expect(actor.reload.following_count).to eq(1)
    expect_counts_in_sync(actor, public_target)
  end

  it "moves nothing on a pending create (private target)" do
    actor.active_follows.create!(followed: private_target, status: :pending)

    expect(private_target.reload.followers_count).to eq(0)
    expect(actor.reload.following_count).to eq(0)
    expect_counts_in_sync(actor, private_target)
  end

  it "increments both columns when a pending request is accepted" do
    follow = actor.active_follows.create!(followed: private_target, status: :pending)

    follow.update!(status: :accepted)

    expect(private_target.reload.followers_count).to eq(1)
    expect(actor.reload.following_count).to eq(1)
    expect_counts_in_sync(actor, private_target)
  end

  it "moves nothing when a pending follow is destroyed (decline/cancel)" do
    follow = actor.active_follows.create!(followed: private_target, status: :pending)

    follow.destroy

    expect(private_target.reload.followers_count).to eq(0)
    expect(actor.reload.following_count).to eq(0)
    expect_counts_in_sync(actor, private_target)
  end

  it "decrements both columns when an accepted follow is destroyed (unfollow/remove)" do
    follow = actor.active_follows.create!(followed: public_target, status: :accepted)

    follow.destroy

    expect(public_target.reload.followers_count).to eq(0)
    expect(actor.reload.following_count).to eq(0)
    expect_counts_in_sync(actor, public_target)
  end

  it "decrements both columns on a defensive accepted→pending flip" do
    follow = actor.active_follows.create!(followed: public_target, status: :accepted)

    follow.update!(status: :pending)

    expect(public_target.reload.followers_count).to eq(0)
    expect(actor.reload.following_count).to eq(0)
    expect_counts_in_sync(actor, public_target)
  end

  it "leaves counts unchanged when an accepted create is rolled back" do
    actor && public_target # persist both BEFORE the transaction so only the follow rolls back
    ActiveRecord::Base.transaction do
      actor.active_follows.create!(followed: public_target, status: :accepted)
      raise ActiveRecord::Rollback
    end

    expect(public_target.reload.followers_count).to eq(0)
    expect(actor.reload.following_count).to eq(0)
    expect_counts_in_sync(actor, public_target)
  end

  it "keeps the surviving counterpart's counts correct when a user with follows both ways is destroyed" do
    survivor = create(:user, private: false)
    doomed = create(:user, private: false)
    survivor.active_follows.create!(followed: doomed, status: :accepted)   # survivor follows doomed
    doomed.active_follows.create!(followed: survivor, status: :accepted)   # doomed follows survivor

    doomed.destroy

    # survivor no longer follows anyone (doomed is gone) and has no followers.
    expect(survivor.reload.following_count).to eq(0)
    expect(survivor.reload.followers_count).to eq(0)
    expect_counts_in_sync(survivor)
  end
end
