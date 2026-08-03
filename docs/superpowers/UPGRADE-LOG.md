# Hoojah Upgrade Log — Rails 6.0 → 8.1

| Hop | Ruby | Rails | Green examples | Notes | Commit |
|-----|------|-------|----------------|-------|--------|
| Baseline | 2.7.8 | 6.0.6.1 | 24 | Bumped within 6.0 to 6.0.6.1 (drop yanked mimemagic); compat pins concurrent-ruby 1.3.4, ffi ~>1.16.3; clang shim for arm64 | 651a23d |
| P1: 6.0→6.1 | 2.7.8 | 6.1.7.10 | 24 | Detection clean (no where.not multi-key / form_with / config_for / legacy errors API / server forms). load_defaults 6.1. No code changes needed. | (this commit) |
