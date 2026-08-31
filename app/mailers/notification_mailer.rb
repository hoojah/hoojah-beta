class NotificationMailer < ApplicationMailer
  # One parameterized mailer for every high-signal Notification category (see
  # Notification::EMAILED_CATEGORIES). Enqueued from a single choke-point —
  # Notification#after_create_commit — so the ~10 Notification.create! call sites
  # never touch email and a double-send is structurally impossible.
  #
  # Called as: NotificationMailer.with(notification: n).notification_email
  #
  # Per-category subjects. Moderation subjects/bodies deliberately do NOT name the
  # acting moderator: the row itself carries no subject_user_id (the same
  # secret-ballot anonymity the vote notifications enforce), and the email must not
  # re-introduce the leak the row is careful to avoid.
  SUBJECTS = {
    "mention" => "%{name} mentioned you on Hoojah",
    "debate_challenge" => "%{name} challenged you to a debate",
    "debate_your_turn" => "It's your turn in a debate",
    "debate_declined" => "Your debate challenge was declined",
    "debate_concluded" => "A debate you took part in has concluded",
    "moderation_removed" => "A moderator removed your hoojah",
    "moderation_warning" => "A moderator issued you a warning",
    "follow_request" => "%{name} requested to follow you"
  }.freeze

  def notification_email
    @notification = params[:notification]
    recipient = @notification.user
    return if recipient.email.blank?

    @name = subject_user_name
    @link = deep_link
    @heading = subject_line

    mail(to: recipient.email, subject: @heading)
  end

  private

  # Only categories with a subject_user (mention, debate_challenge, follow_request)
  # interpolate a name; the rest ignore the %{name} slot. Falls back to the @handle
  # when a display name is missing, never to nil.
  def subject_user_name
    su = @notification.subject_user
    return nil unless su
    su.full_name.presence || su.username
  end

  def subject_line
    template = SUBJECTS.fetch(@notification.category, "You have a new notification on Hoojah")
    format(template, name: @name || "Someone")
  end

  # Deep-link to the surface the notification is about, falling back to the
  # notifications index when the row carries neither a hoojah nor a debate.
  def deep_link
    if @notification.hujah
      hujah_url(@notification.hujah.slug)
    elsif @notification.debate
      debate_url(@notification.debate.slug)
    else
      notifications_url
    end
  end
end
