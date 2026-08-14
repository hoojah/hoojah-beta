One notification row — same 8px-left-border shape as a compact hoojah card, but the border encodes read state instead of stance.

```jsx
<NotificationCard category="new_hoojah_response">@tomkurus posted a new argument on your hoojah</NotificationCard>
<NotificationCard category="follow_request" action={<><NotificationAction>Accept</NotificationAction><NotificationAction tone="muted">Decline</NotificationAction></>}>@mayaz requested to follow you</NotificationCard>
<NotificationCard category="badge_earned" read action={<NotificationAction>Mark as read</NotificationAction>}>You earned the <strong>First Debate</strong> badge</NotificationCard>
```

Copy is always third-person-about-them / second-person-about-you: "@handle started following you", "You have a new vote on your hoojah". Unread is pink (`--notif-unread`) — inferred, since the source's `border-unread` class has no colour definition.
