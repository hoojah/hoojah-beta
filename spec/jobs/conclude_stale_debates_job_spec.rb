require "rails_helper"

RSpec.describe ConcludeStaleDebatesJob, type: :job do
  let(:challenger) { create(:user) }
  let(:opponent) { create(:user) }

  def active_debate
    d = create(:debate, challenger: challenger, opponent: opponent, status: :pending)
    d.accept!(by: opponent)
    d
  end

  it "concludes an active debate idle for more than 7 days and notifies both" do
    d = active_debate
    d.update_column(:updated_at, 8.days.ago)
    expect { ConcludeStaleDebatesJob.perform_now }
      .to change { Notification.where(category: "debate_concluded").count }.by(2)
    expect(d.reload).to be_concluded
  end

  it "leaves a recently active debate untouched" do
    d = active_debate # updated_at is now
    ConcludeStaleDebatesJob.perform_now
    expect(d.reload).to be_active
  end

  it "skips debates that are not active (concluded / declined)" do
    concluded = create(:debate, status: :concluded)
    concluded.update_column(:updated_at, 10.days.ago)
    declined = create(:debate, status: :declined)
    declined.update_column(:updated_at, 10.days.ago)

    expect { ConcludeStaleDebatesJob.perform_now }.not_to change { Notification.count }
    expect(concluded.reload).to be_concluded
    expect(declined.reload).to be_declined
  end
end
