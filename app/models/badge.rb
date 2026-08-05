# Badge definitions live in code, not a table — only *awards* (UserBadge rows)
# persist. `Badge::REGISTRY` is the single source of truth for a badge's display
# name/description/Lucide icon; `UserBadge` validates its `badge_key` against
# these keys and `User#badges` maps awards back through it (dropping any award
# whose key no longer exists, so a future registry edit can't 500 a profile).
class Badge
  REGISTRY = {
    "first_hoojah" => {
      name: "First Hoojah",
      description: "Posted your first top-level hoojah",
      icon: "award"
    },
    "first_argument" => {
      name: "First Argument",
      description: "Posted your first argument on someone's hoojah",
      icon: "message-circle"
    },
    "first_follower" => {
      name: "First Follower",
      description: "Gained your first follower",
      icon: "users"
    },
    "first_debate" => {
      name: "First Debate",
      description: "Concluded your first debate",
      icon: "swords"
    }
  }.freeze
end
