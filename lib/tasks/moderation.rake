namespace :moderation do
  desc "Promote a user to moderator: bin/rails 'moderation:promote[username]'"
  task :promote, [:username] => :environment do |_t, args|
    user = User.find_by!(username: args.fetch(:username))
    user.update!(role: :moderator)
    puts "#{user.username} is now a moderator"
  end

  desc "Demote a user to member: bin/rails 'moderation:demote[username]'"
  task :demote, [:username] => :environment do |_t, args|
    user = User.find_by!(username: args.fetch(:username))
    user.update!(role: :member)
    puts "#{user.username} is now a member"
  end
end
