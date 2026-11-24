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
    # Re-check the preference at send time: Notification#deliver_email_later checks it
    # at enqueue time, but the job can run later, after the user switched email off.
    return unless recipient.email_notifications?

    @name = subject_user_name
    @link = deep_link
    @heading = subject_line

    # One-click unsubscribe (RFC 8058): providers show their own "Unsubscribe" button and
    # POST to this URL. The same URL is the body link, so the two cannot drift.
    @unsubscribe_url = email_unsubscribe_url(recipient.generate_token_for(:email_unsubscribe))
    headers["List-Unsubscribe"] = "<#{@unsubscribe_url}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"

    mail(to: recipient.email, subject: @heading)
  end

  private

  # Only categories with a subject_user (mention, debate_challenge, follow_request)
  # interpolate a name; the rest ignore the %{name} slot. Always the @handle, never
  # full_name: full_name is free text, so using it in a subject would let anyone put
  # "Hoojah Support: verify your account" into another user's inbox. A username is
  # constrained and unique, so it cannot impersonate us.
  def subject_user_name
    su = @notification.subject_user
    return nil unless su
    "@#{su.username}"
  end

  def subject_line
    template = SUBJECTS.fetch(@notification.category, "You have a new notification on Hoojah")
    format(template, name: @name || "Someone")
  end

  # Deep-link to the surface the notification is about, falling back to the
  # notifications index when the row carries neither a debate nor a hoojah.
  # Debate comes first: every Debate#notify row carries BOTH hujah_id (the debated
  # claim) and debate_id, so checking the hoojah first sent every debate email to
  # the claim instead of the debate.
  def deep_link
    if @notification.debate
      debate_url(@notification.debate.slug)
    elsif @notification.hujah
      hujah_url(@notification.hujah.slug)
    else
      notifications_url
    end
  end
end
