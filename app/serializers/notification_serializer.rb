class NotificationSerializer
  include JSONAPI::Serializer

  attributes :body, :category, :read

  # Slice 7b (Gate 9, N-1): mirror the notification-card guard. Notifications are
  # always the recipient's own (policy_scoped), so `notification.user` IS the viewer —
  # only expose the hoojah when it is visible to them (a private author's body must not
  # leak to a non-follower through the API).
  attribute :hujah do |notification|
    if notification.hujah_id
      hujah = Hujah.find(notification.hujah_id)
      if hujah.visible_to?(notification.user)
        {
          slug: hujah.slug,
          body: hujah.body
        }
      end
    end
  end

  attribute :subject_user do |notification|
    if notification.subject_user_id
      subject_user = User.find(notification.subject_user_id)
      {
        username: subject_user.username
      }
    end
  end

  # Badge parity for API/native clients: a badge_earned notification's `body` is
  # the registry key; expose the resolved {key,name,icon} (nil for other
  # categories, and nil-safe if the key was later removed from the registry).
  attribute :badge do |notification|
    if notification.category == "badge_earned" && (badge = Badge::REGISTRY[notification.body])
      {key: notification.body, name: badge[:name], icon: badge[:icon]}
    end
  end
end
