# Hoojah Upgrade Log — Rails 6.0 → 8.1

| Hop | Ruby | Rails | Green examples | Notes | Commit |
|-----|------|-------|----------------|-------|--------|
| Baseline | 2.7.8 | 6.0.6.1 | 24 | Bumped within 6.0 to 6.0.6.1 (drop yanked mimemagic); compat pins concurrent-ruby 1.3.4, ffi ~>1.16.3; clang shim for arm64 | 651a23d |
| P1: 6.0→6.1 | 2.7.8 | 6.1.7.10 | 24 | Detection clean (no where.not multi-key / form_with / config_for / legacy errors API / server forms). load_defaults 6.1. No code changes needed. | 7544343 |
| P2: 6.1→7.0 | 2.7.8 | 7.0.10 | 24 | **Fable-architected.** webpacker→shakapacker ~>6.6 (keeps Webpacker constant → 1-line churn); rspec-rails ~>5.1; dropped Spring (Rails 7 removed it); listen ~>3.3. resolved_paths→additional_paths. load_defaults 7.0. | 63f5528 |
| P3: 7.0→7.1 | **3.3.12** | 7.1.6 | 24 | **Off Ruby 2.7.** Bumped Ruby 2.7.8→3.3.12 (spans 7.1–8.0). Removed concurrent-ruby & ffi compat pins (now transitive latest). Full re-resolve: pg 1.2.3→1.6.3, puma 4.3.5→6.6.1, nokogiri→1.19.4, bootsnap→1.24.6. Fixed show_exceptions=false→:none. load_defaults 7.1. lib/ has no autoloadable files. | f8a377e |
| P4: 7.1→7.2 | 3.3.12 | 7.2.3 | 24 | Detection clean. rspec-rails 5.1→7.1.1 (5.x calls fixture_path= which 7.2 removed) + rails_helper fixture_path→fixture_paths. load_defaults 7.2. | 115989d |
| P5: 7.2→8.0 | 3.3.12 | 8.0.5.1 | 24 | Pinned ~>8.0.0 (~>8.0 would've jumped to 8.1). **App fix:** enum keyword form removed in 8.0 → `enum :category,{…}` / `enum :subject,{…}` in Notification & Flag. load_defaults 8.0. sprockets kept (Propshaft in Phase 8). | 46eba9c |
| **P6: 8.0→8.1** | **3.4.9** | **8.1.3.1** | 24 | **TARGET REACHED.** Ruby 3.3.12→3.4.9 (final). rails ~>8.1. Detection clean. load_defaults 8.1. | 4ab803a |
| Phase 8 | 3.4.9 | 8.1.3.1 | 24 | Modernization: fast_jsonapi→jsonapi-serializer (e7a3ff8); Solid Queue/Cache/Cable + Kamal + multi-DB prod + Zeitwerk verified (8e1f92b); security hardening + brakeman/bundler-audit + puma→7.2.1 CVE fix (e97a615); simplifier (404ea21). | multiple |

**Final state: Rails 8.1.3.1 on Ruby 3.4.9. Suite 24 examples / 0 failures / 2 pending. Boots dev + test; production config parses.**

## Deferred to Project 2 (Hotwire) — do NOT do during the upgrade
- **React/Webpacker JS build is intentionally not migrated** (no webpack 4→5, no `shakapacker` npm pkg, package.json untouched). `bin/shakapacker`/local SPA dev is out of service until Project 2 replaces the front-end with Hotwire. The RSpec API suite + Rails boot are the green gate and do not compile JS.
- **Deploy caveat:** shakapacker hooks `assets:precompile`; do not deploy a hop standalone through a pipeline that precompiles. Escape hatch if unavoidable: `SHAKAPACKER_PRECOMPILE=false`.
- **One-time logout:** 7.0's key-generator SHA1→SHA256 default invalidates existing session cookies on the deploy that ships it (accepted; beta app).
- sprockets/sass-rails kept (inert) → replaced by Propshaft in Phase 8/Project 2.
