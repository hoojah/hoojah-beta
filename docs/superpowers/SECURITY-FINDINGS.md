# Security Findings — Hoojah (post Rails 6.0→8.1 upgrade)

Source: `rails-security-auditor` + Brakeman 8.0.5 + bundler-audit 0.9, run 2026-08-04 on Rails 8.1.3.1 / Ruby 3.4.9.

**Brakeman: 0 warnings.** **bundler-audit: 1 (shakapacker — see below).**

> **Scope note.** This was a *Rails upgrade* (Project 1). The audit surfaced many
> **pre-existing application-logic vulnerabilities** that existed in the original Rails 6.0
> app — they are NOT upgrade regressions. Fixing them changes the JSON API contract the
> React SPA depends on and would require rewriting the characterization specs (which
> deliberately capture current behavior). Those are **product/security decisions for the
> owner** and are best done as a dedicated security pass or folded into Project 2 (where the
> front-end + auth flow are reworked for Hotwire). They were **not** changed here.

---

## ✅ Fixed in this pass (safe, convention-level, no API-behavior change)

- **Security tooling added** (audit H5): `brakeman` + `bundler-audit` in `:development, :test`.
- **`config.force_ssl = true` + `config.assume_ssl = true`** in production (audit H2) — HSTS + Secure session cookie; TLS terminated at Kamal/Thruster proxy.
- **`config.log_level` → `info`** (was `:debug`) + `config.hosts` allowlist via `ENV["APP_HOST"]` (audit M2, M3).
- **Expanded `filter_parameters`** to cover email/secret/token/_key/crypt/salt/etc. (audit M3).

All above are production/tooling only; test+dev suite stays green (24/0/2).

---

## ⚠️ Deferred — owner decision required (pre-existing app-logic vulns, change API contract)

Ranked from the auditor. Each would alter behavior the React SPA currently relies on and/or the characterization specs.

| ID | Severity | Issue | File | Recommended fix |
|----|----------|-------|------|-----------------|
| C1 | Critical | `render json: @user` leaks `password_digest` + `email` on every login/`is_logged_in?`/signup | `sessions_controller.rb:9,24`, `users_controller.rb:37` | Route all user responses through `UserSerializer`/`as_json(only:[…])` |
| C2 | Critical | `Api::V1::VotesController` has no auth; trusts `params[:user_id]` — vote as anyone | `api/v1/votes_controller.rb` | `before_action :require_login`; use `current_user.id` |
| C3 | Critical | Notifications `update`/`destroy` IDOR (no auth, `find(params[:id])`) | `api/v1/notifications_controller.rb:36-38` | Scope to `current_user.notifications`; require login |
| C4 | Critical | `hujahs#destroy` unauthenticated + no ownership check | `api/v1/hujahs_controller.rb:31-34` | Require login + `hujah.user_id == current_user.id` |
| C5 | Critical | Legacy non-namespaced `VotesController` + `resources :votes` — unauth CRUD (dead scaffold) | `votes_controller.rb`, `routes.rb:2` | Delete controller + route |
| H1 | High | CSRF disabled app-wide (`skip_before_action :verify_authenticity_token`) | `application_controller.rb:3` | `protect_from_forgery with: :null_session` + explicit `same_site` |
| H4 | High | No shared auth enforcement; `current_user` truthiness by accident (500 not 401) | API controllers | Shared `require_login` + Pundit/CanCanCan |
| H6 | High | `:id` permitted in `user_params` (PK mass-assignment) | `api/v1/users_controller.rb:19` | Drop `:id`, `:user` from permit |
| M1 | Med | CORS origin hardcoded `localhost:3000` with `credentials:true` | `initializers/cors.rb:3` | Drive from `ENV["FRONTEND_ORIGIN"]` |
| M4 | Med | No CSP (app serves SPA shell) | `content_security_policy.rb` | Define policy — **do in Project 2** (front-end rework) |
| M6 | Med | No min password length | `models/user.rb` | `validates :password, length: {minimum: 8}, allow_nil: true` |
| M7 | Med | `link` field unsanitized (stored-XSS risk if rendered as href) | `users_controller.rb`, `user.rb` | `validates :link, format: {with: %r{\Ahttps?://}}, allow_blank: true` |
| L1 | Low | create actions use `.create` + `if record` (always truthy) → failures reported as success | `hujahs`/`flags` controllers | `.create!` + rescue, or check `persisted?` |
| L3 | Low | Invalid login returns HTTP 200 w/ `{status:401}` in body | `sessions_controller.rb:13-16` | Return real `status: :unauthorized` |
| L4 | Low | `config.require_master_key` commented in production | `production.rb:19` | Enable once the deploy provides `RAILS_MASTER_KEY` |

---

## Dependency CVE (bundler-audit)

- **GHSA-96qw-h329-v5rg — shakapacker 6.6.0 (High):** EnvironmentPlugin can leak ENV secrets into client bundles. Fix = shakapacker ≥ 9.5.0.
  - **Accepted for now, tracked in `.bundler-audit.yml`.** Rationale: the webpack/React JS build is not active during the upgrade and **shakapacker is removed entirely in Project 2** (React → Hotwire on importmap+Propshaft). Bumping to 9.x means the exact webpack-rename churn the upgrade deliberately avoided, on code about to be deleted. Re-audit after Project 2; the ignore entry should be removed then.
