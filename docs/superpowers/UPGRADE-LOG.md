# Hoojah Upgrade Log — Rails 6.0 → 8.1

| Hop | Ruby | Rails | Green examples | Notes | Commit |
|-----|------|-------|----------------|-------|--------|
| Baseline | 2.7.8 | 6.0.6.1 | 24 | Bumped within 6.0 to 6.0.6.1 (drop yanked mimemagic); compat pins concurrent-ruby 1.3.4, ffi ~>1.16.3; clang shim for arm64 | 651a23d |
| P1: 6.0→6.1 | 2.7.8 | 6.1.7.10 | 24 | Detection clean (no where.not multi-key / form_with / config_for / legacy errors API / server forms). load_defaults 6.1. No code changes needed. | 7544343 |
| P2: 6.1→7.0 | 2.7.8 | 7.0.10 | 24 | **Fable-architected.** webpacker→shakapacker ~>6.6 (keeps Webpacker constant → 1-line churn); rspec-rails ~>5.1; dropped Spring (Rails 7 removed it); listen ~>3.3. resolved_paths→additional_paths. load_defaults 7.0. | (this commit) |

## Deferred to Project 2 (Hotwire) — do NOT do during the upgrade
- **React/Webpacker JS build is intentionally not migrated** (no webpack 4→5, no `shakapacker` npm pkg, package.json untouched). `bin/shakapacker`/local SPA dev is out of service until Project 2 replaces the front-end with Hotwire. The RSpec API suite + Rails boot are the green gate and do not compile JS.
- **Deploy caveat:** shakapacker hooks `assets:precompile`; do not deploy a hop standalone through a pipeline that precompiles. Escape hatch if unavoidable: `SHAKAPACKER_PRECOMPILE=false`.
- **One-time logout:** 7.0's key-generator SHA1→SHA256 default invalidates existing session cookies on the deploy that ships it (accepted; beta app).
- sprockets/sass-rails kept (inert) → replaced by Propshaft in Phase 8/Project 2.
