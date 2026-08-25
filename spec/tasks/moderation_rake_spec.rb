require "rails_helper"
require "rake"

RSpec.describe "moderation rake tasks" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("moderation:promote")
  end

  def run_task(name, username)
    Rake::Task[name].execute(Rake::TaskArguments.new([:username], [username]))
  end

  describe "moderation:promote" do
    it "flips a member to moderator" do
      user = create(:user)
      expect { run_task("moderation:promote", user.username) }
        .to change { user.reload.moderator? }.from(false).to(true)
    end

    it "raises RecordNotFound for an unknown username" do
      expect { run_task("moderation:promote", "nobody-here") }
        .to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "moderation:demote" do
    it "flips a moderator back to member" do
      user = create(:user, :moderator)
      expect { run_task("moderation:demote", user.username) }
        .to change { user.reload.member? }.from(false).to(true)
    end

    it "raises RecordNotFound for an unknown username" do
      expect { run_task("moderation:demote", "nobody-here") }
        .to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
