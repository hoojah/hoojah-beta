# Hoojah web app — UI kit

A click-through recreation of the only Hoojah surface that exists: the **web app** at
https://beta.hoojah.my. Built by reading `hoojah-beta/app/views/**` (Rails + Hotwire ERB),
not from screenshots. Every screen composes the primitives in `components/` — nothing is
re-implemented here.

## Screens

| File | Source view | What it covers |
| --- | --- | --- |
| `Feed.jsx` | `hujahs/index.html.erb`, `_feed_tabs`, `shared/_pinned`, `trending/_trending` | Everyone / Following tabs, the hoojah feed, "Load more", the 256px trending rail, and the logged-out signup CTA |
| `HujahDetail.jsx` | `hujahs/show.html.erb`, `_response_filter`, `_child_card`, `_flag_dialog`, `_challenge_dialog` | 20px body, vote widget, "Add hoojah", the Debates lens, stance-filtered responses, flag + challenge dialogs |
| `Compose.jsx` | `hujahs/_compose_form`, `_stance_picker`, `_parent_card` | Fixed back/submit bar, the parent stub + stance picker on a reply, the borderless 18px composer |
| `Profile.jsx` | `users/show.html.erb`, `_profile_header`, `_profile_edit` | Indigo header with badges and counts, the owner's hoojahs, the edit-profile dialog |
| `Notifications.jsx` | `notifications/index.html.erb`, `_notification_card` | All eight notification categories, read/unread borders, accept/decline, delete |
| `Debate.jsx` | `debates/show.html.erb`, `_debate_status`, `_debate_turn`, `_turn_composer`, `_verdict` | Transcript, turn-taking composer, conclude, spectator verdict |
| `Dashboard.jsx` | `analytics/show.html.erb`, `_stat`, `_distribution_bar` | The two headline stats and the per-hoojah distributions (with the <5-vote privacy floor) |
| `Login.jsx` | `devise/sessions/new.html.erb` | The rect-button auth screen |

`App.jsx` is the shell: navbar, screen routing and the fake state (votes, replies, debates,
notifications). `data.jsx` holds the sample content.

## Try it

Open `index.html`. Vote on a hoojah; open one; filter its responses by stance; challenge a
response to a debate and post turns; conclude it and cast a verdict; compose a reply; edit
your profile; delete a notification; log out to see the logged-out feed, then log back in.

## Deliberately omitted

No screens exist in the source for search, settings, moderation queues, or a mobile app —
so none are invented here. Avatars use the initials fallback because production photos are
served from Cloudinary and cannot be copied.
