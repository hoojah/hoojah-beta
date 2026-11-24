# Email notification fixes (review follow-up)

Source: the email-notification review of 2026-11-23. Items 1, 2, 3, 5, 6, 8, 9 are in scope.
Items 4 (per-turn email throttling) and 7 (`discard_on DeserializationError`) are NOT in scope.

## Global Constraints

- Rails 8.1 / Ruby 3.4.9. Run Ruby through `RBENV_VERSION=3.4.9 /opt/rbenv/bin/rbenv exec <cmd>` in this container.
- Specs: `RAILS_ENV=test RUBYOPT='-W0' bundle exec rspec <files>`. Run targeted specs only, never the full suite
  (one shared Postgres test DB). Run `bundle exec standardrb` on touched Ruby files and `bundle exec brakeman -q`.
- Every non-Devise controller action must call `authorize` or `skip_authorization` exactly once (Pundit `verify_authorized`).
- `config/routes.rb` is hand-written paths only (no `resources`), and every route carries a comment explaining its shape.
- Email views are Tailwind-scanned ERB: **no utility class names anywhere in mailer views or their ERB comments**;
  inline `style=` only. App (non-mail) views use the design system (`ui/_card` is a layout partial:
  `render layout: "ui/card", locals: {...} do … end`), stance colours as tokens only.
- Secret-ballot / moderator anonymity: moderation emails never name the moderator; no email may name a voter.
- Comments in this codebase carry the *why*; when changing commented code, update the reasoning, don't delete it.
- Commits: one short summary line, plain imperative, author `Rudzainy <tek@rudzainy.com>`
  (`git -c user.name=Rudzainy -c user.email=tek@rudzainy.com commit ...`). **No Co-Authored-By, no Claude/Anthropic
  branding, no session links.** Never amend.

## Task 1: Mailer correctness, sender, preference recheck, subjects, mention visibility

Review items 1, 3, 6, 8, 9.

1. **Debate deep link (item 1).** `NotificationMailer#deep_link` (`app/mailers/notification_mailer.rb`) must prefer
   `@notification.debate` over `@notification.hujah`. Every `Debate#notify` row (`app/models/debate.rb` `notify`) carries
   BOTH `hujah_id` (the debated claim) and `debate_id`, so the current hujah-first order sends all debate emails to the
   claim. Order: debate → hujah → `notifications_url`. Update the method comment to say why debate comes first.
   Fix the existing spec "deep-links to the debate for debate_your_turn" in `spec/mailers/notification_mailer_spec.rb`
   so the row carries the debate's `hujah` too (as real rows do), and assert the body includes `/debates/<slug>` and
   does NOT include `/hujahs/`-style claim link for that hujah (check the real claim URL helper path in
   `config/routes.rb`). Add one spec that a real row produced via the debate model (e.g. a challenge → `notify_challenge`,
   or `Notification.where(category: :debate_challenge).last` after creating a debate through its factory/flow) links to the debate.
2. **Devise sender (item 3).** `config/initializers/devise.rb` `config.mailer_sender` is the generated placeholder.
   Set it to `ENV.fetch("MAILER_FROM", "Hoojah <no-reply@hoojah.rudzainy.com>")` — the exact same default as
   `ApplicationMailer`. Do not duplicate the literal in two places if a small shared constant is clean (e.g. define it
   once and reference it); either is acceptable, but the two must not be able to drift silently. Add a short why-comment.
3. **Preference recheck at send time (item 6).** In `NotificationMailer#notification_email`, also return (no mail)
   when `recipient.email_notifications?` is false — the job may run after the user switched email off. Keep the existing
   `Notification#deliver_email_later` enqueue-time guard (it avoids pointless jobs). Spec: a notification whose recipient
   flips `email_notifications` to false before the mailer runs yields a blank `mail.to`.
4. **Subjects use the @handle (item 9).** `full_name` is free text and lets anyone put "Hoojah Support: verify your
   account" in another user's inbox subject. Subjects must interpolate `@username` instead (e.g.
   "@aisha mentioned you on Hoojah"). Fallback when there is no subject user stays "Someone". Update the
   `subject_user_name` comment and the existing mention spec (it currently asserts the full name appears).
   Add a spec that a full_name like "Hoojah Support" does not appear in the subject.
5. **Mention visibility (item 8).** `Hujah#notify_mention_handles` (`app/models/hujah.rb`) notifies mentioned users
   without checking they can see the hoojah, so a private / followers-only author (or a reply under one) can mention a
   non-follower, who gets a notification + email naming the author with a link they cannot open. Skip any mentioned user
   for whom `visible_to?(u)` is false (`Hujah#visible_to?` already handles parent chain, author privacy, visibility
   enum and moderation removal). Handles are capped at 10 so a per-user check is acceptable. Update the method comment.
   Specs (in the existing hujah/notification mention specs — find them): a followers-only hoojah mentioning a
   non-follower creates no mention notification; mentioning an accepted follower still does; a public hoojah still notifies.

## Task 2: Production SMTP delivery + one-click unsubscribe

Review items 2 and 5. Production is deployed with Coolify from the `Dockerfile` (no Kamal); config comes from env vars.

1. **SMTP from env (item 2).** In `config/environments/production.rb`, next to the existing mailer block:
   - When `ENV["SMTP_ADDRESS"]` is present: `delivery_method = :smtp`, `smtp_settings` = address `SMTP_ADDRESS`,
     port `ENV.fetch("SMTP_PORT", 587).to_i`, user_name `SMTP_USERNAME`, password `SMTP_PASSWORD`,
     domain `ENV.fetch("SMTP_DOMAIN", <APP_HOST default>)`, `authentication: :plain`, `enable_starttls_auto: true`;
     `raise_delivery_errors = true` (a real failure must show as a failed Solid Queue job, not vanish).
   - When absent: `perform_deliveries = false`, so mail jobs no-op instead of failing against localhost:25. Add a
     comment saying exactly that and naming the env vars. (Do not log from the environment file at boot.)
   - Provider-agnostic: no provider gem.
   - Update the `Dockerfile` header's "Run:" comment / env documentation (if it lists env vars) to mention the SMTP vars
     and `MAILER_FROM`.
2. **One-click unsubscribe (item 5).** Recipients must be able to turn email notifications off without logging in, and
   mail providers' one-click unsubscribe (RFC 8058) must work.
   - `User`: `generates_token_for :email_unsubscribe do email end` — no expiry (emails sit in inboxes for months);
     embedding the email invalidates old links if the address changes.
   - Routes (hand-written, each with a why-comment): `GET /unsubscribe/:token` → confirmation page;
     `POST /unsubscribe/:token` → sets `email_notifications = false`. Names e.g. `email_unsubscribe` (GET) and
     reuse the same path for POST. Controller e.g. `EmailUnsubscribesController` with `show` and `create`.
   - Both actions `skip_authorization` (the token is the credential; no login required — `skip_before_action` any
     `authenticate_user!` if the base controller enforces one). `create` must `skip_forgery_protection only: :create`
     because RFC 8058 one-click POSTs come from the mail provider with no CSRF token; the signed token authenticates the
     request. Put that reasoning in a comment — CLAUDE.md says HTML writes keep CSRF, this is the deliberate exception.
   - Invalid/stale token: render a friendly "this link is invalid or has expired" page with status 404 for both verbs; never reveal
     whether an account exists.
   - `show`: a small page (design-system card) saying "Stop email notifications for @username?" with a POST button
     (`button_to`, `ds_button_classes`). If already off, say so. `create` (HTML): flips the flag and renders/redirects to
     a confirmation "You won't get email notifications any more. You can turn them back on in your profile settings."
     `create` called with body `List-Unsubscribe=One-Click` (any non-HTML request) must return 200 with no redirect.
     Idempotent.
   - Rate-limit: add a `rack_attack` throttle on `/unsubscribe/` by IP (e.g. 20/min) in `config/initializers/rack_attack.rb`,
     following that file's style.
   - `NotificationMailer#notification_email`: set headers `List-Unsubscribe: <ABSOLUTE_UNSUBSCRIBE_URL>` and
     `List-Unsubscribe-Post: List-Unsubscribe=One-Click`. Both email bodies (html + text): replace "turn them off any time
     from your profile settings" with a direct unsubscribe link (keep mentioning profile settings as the way back on).
     Remember: no Tailwind class names in mailer views.
   - Specs: request spec for GET valid/invalid, POST valid (flag false, idempotent), POST with one-click body without
     CSRF token (use `ActionController::Base.allow_forgery_protection = true` around it, restoring afterwards), POST invalid
     token (404, nothing changes), token invalid after email change; mailer spec asserting both headers and that the
     body link matches the header URL.
   - Add one line to `docs/FEATURES.md` where notifications/email preferences are described.
