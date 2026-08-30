# Hoojah

![Ruby](https://img.shields.io/badge/Ruby-3.4.9-CC342D?logo=ruby&logoColor=white)
![Rails](https://img.shields.io/badge/Rails-8.1.3.1-D30001?logo=rubyonrails&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-18-4169E1?logo=postgresql&logoColor=white)
![Hotwire](https://img.shields.io/badge/Hotwire-Turbo%20%2B%20Stimulus-5CD8E5?logo=hotwire&logoColor=white)
![Tailwind CSS](https://img.shields.io/badge/Tailwind-CSS-38BDF8?logo=tailwindcss&logoColor=white)
![Devise](https://img.shields.io/badge/Devise-auth-E9573F)
![Pundit](https://img.shields.io/badge/Pundit-authorization-4B7BEC)
![Action Cable](https://img.shields.io/badge/Action%20Cable-Solid%20Cable-9B59B6)
![Tests](https://img.shields.io/badge/tests-785%20passing-brightgreen?logo=rspec&logoColor=white)
![Code style](https://img.shields.io/badge/code_style-standard-brightgreen)
![Deploy](https://img.shields.io/badge/deploy-Coolify%20%2B%20Docker-8b5cf6)

**Hoojah** is where Malaysians come to argue properly. You post a *hujah* (Malay for
your point, your stance, the thing you're ready to defend), people vote **agree**,
**neutral**, or **disagree**, they thread their own hujah underneath, and if it gets
spicy, the two of you take it into a proper one-on-one debate. Live at
**https://hoojah.rudzainy.com**.

I first sketched this thing out years ago (2013, if you must know) and only recently sat
down to build it the way it deserved. So here we are. 🥊

## How it works

1. **You post a hujah.** A claim, a hot take, a "change my mind." Pineapple on nasi lemak,
   whether mee goreng mamak beats everything, your team over theirs. Whatever you'll stand behind.
2. **People vote.** Three buttons, that's the whole menu: agree, neutral, disagree. No twenty
   reactions to agonise over, no decision fatigue. You pick a side or you sit in the middle.
3. **They reply.** Every response carries its stance, so all the *setuju* sit in one column and
   all the *tak setuju* in another. Easy to read the room at a glance.
4. **Someone challenges you.** Any argument can graduate into a one-on-one debate. Challenge,
   accept, then take turns through four named rounds: Opening, Counter, Response, Closing.
5. **The gallery decides.** Spectators watch the whole thing play out live and vote on who
   argued better. Not who's *right*, mind you. Who argued *better*. Big difference, that one.

## What Hoojah believes

- **Three options, on purpose.** Agree, neutral, disagree. Keeping it to three cuts the noise
  and the pile-ons before they start.
- **Your vote is a secret ballot.** Nobody sees how you voted. Not other users, not even the
  person who posted the hujah. Built that way from day one, and it stays that way.
- **Privacy is a setting, not a favour.** Private account, per-post visibility, block. You decide
  who sees what, and you don't have to ask anyone.
- **A debate is a fair fight.** Named phases, strict alternating turns, a crowd verdict at the
  end. No ambushes, no sneaking in the last word.

## Milestones

### Shipped

#### The foundation
Rebuilt from the ground up on a fast, modern base, then the bones of the whole thing went in.
- **The feed and the single-hujah page** where every argument lives.
- **Three-option voting**, tallied and updated on the spot, no page reload.
- **Stance-tagged responses**, so a thread reads like two sides of a table.
- **Profiles** you can make your own, photo and all.
- *Along the way: share a hujah to WhatsApp, Telegram, Twitter and the rest; notifications when
  something happens.*

#### Becoming social
- **Follow people and a Following feed**, so you can watch just the folks whose arguments you rate,
  or the whole crowd. Your call.
- *Along the way: @mentions that actually notify the person.*

#### The debate arrives
- **One-on-one, turn-based debates.** Challenge someone, they accept, you trade turns, it
  concludes, and the whole transcript stays up for anyone to read after.

#### Privacy and trust
- **The secret ballot**, locked in: how you voted is nobody's business but yours.
- **A private dashboard** to see how your own hujah are landing, for your eyes only.
- **Block**, so someone you'd rather not deal with simply disappears from your Hoojah.
- **Private accounts**, where people request to follow and you approve, or you don't.
- *Along the way: flag a hujah that crosses a line, plus quiet guards against spam and bots.*

#### Community heat and live debates
- **Real-time debate turns**, so you watch it unfold as it happens instead of hitting refresh.
- **The spectator verdict**: the crowd calls who argued better once the dust settles.
- **Walk-away auto-conclude**, so ghosting a debate for a week ends it, no dangling arguments.
- **Trending**, surfacing the hujah that everyone's piling into right now.
- **Badges** for the little firsts: your first hujah, your first debate, your first follower.
- *Along the way: named debate phases, room to extend a round, and a consistent look across
  every screen.*

#### The 2026 refresh
- **A full redesign**, brand and all, with proper **dark mode** for the late-night arguers.
- **Per-post visibility**, so you choose the audience for each hujah, one by one.
- **Real hashtags** to gather arguments by topic.
- **Full-text search** across hujah, people, and tags.
- *Along the way: conviction voting (hold to commit), theme switching, and finally being able to
  delete your own hujah.*

### In progress now
- **Landing the 2026 refresh across every last screen**, so the new look is everywhere, not just
  the front page.
- *Along the way: laying the groundwork for native mobile apps.*

### Coming up
- **Native apps** for iPhone and Android, Hoojah in your pocket.
- **Identity verification**, for people who want to argue as their real, verified selves.
- **Analytics over time**: trends, your most divisive hujah, your most agreed-with one.
- *On the list: hiding vote counts until enough people have weighed in (so the early voters stay
  anonymous), live presence and typing while a debate is on, turn timers, bookmarks, mute, and a
  proper inbox for follow requests.*

## Documentation

- **[`docs/FEATURES.md`](docs/FEATURES.md)** walks through Hoojah screen by screen, privacy model included.
- **`docs/design-system/`** is the look and feel, pulled straight from the app itself.

Come argue: **https://hoojah.rudzainy.com**
