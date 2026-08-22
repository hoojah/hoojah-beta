# Production image for Coolify (Slice 10b).
#
# Coolify can build from a Dockerfile or guess with Nixpacks. This file exists so it
# never guesses, for one specific reason: the build MUST run `assets:precompile`.
# `app/assets/builds/tailwind.css` is gitignored and nothing regenerates it at boot, so
# an image built without that step starts cleanly, serves every page, and renders them
# with NO CSS AT ALL — a deploy that reports success and is visibly broken.
# `tailwindcss-rails` hooks `tailwindcss:build` into `assets:precompile`, so the one
# command below covers both Propshaft digests and the Tailwind bundle.
#
# Build:  docker build --platform linux/amd64 -t hoojah .
# Run:    docker run -p 3000:3000 -e RAILS_MASTER_KEY=... -e DATABASE_URL=... -e APP_HOST=... hoojah
#
# PLATFORM: build for linux/amd64. Gemfile.lock's PLATFORMS section lists
# `arm64-darwin-25`, `ruby` and `x86_64-linux` — there is no `aarch64-linux`, so a
# native ARM64 Linux build fails to resolve the platform-specific gems (thruster ships
# a Go binary per platform). If Coolify ever runs on an ARM host, the fix is
# `bundle lock --add-platform aarch64-linux`, committed — not a change here.

ARG RUBY_VERSION=3.4.9
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

# Set once, inherited by BOTH stages. BUNDLE_WITHOUT is why the runtime image has no
# strong_migrations — which is exactly the condition that used to crash production boot
# before config/initializers/strong_migrations.rb was guarded. Read the comment there
# before changing this line.
ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test \
    RAILS_SERVE_STATIC_FILES=true \
    RAILS_LOG_TO_STDOUT=true

# The two RAILS_* lines above are baked into the image on purpose, not left to the
# operator. Both were measured in the container, not assumed:
#
#   RAILS_SERVE_STATIC_FILES — production.rb reads it for
#     `config.public_file_server.enabled`. WITHOUT it, GET /assets/tailwind-<digest>.css
#     returns 404 and every page renders unstyled. Thruster does NOT cover this: it
#     proxies and then caches/compresses what the backend served, so if Rails 404s, so
#     does Thruster. Verified both ways against this image.
#   RAILS_LOG_TO_STDOUT — otherwise Rails logs to log/production.log inside the
#     container, where Coolify's log viewer cannot see it, and the volume of a
#     forgotten logfile is the container's disk.
#
# Both remain overridable at runtime (`docker run -e RAILS_SERVE_STATIC_FILES=`), which
# is the escape hatch if a CDN or the platform proxy ever takes over asset serving.

# ---------------------------------------------------------------------------
# Build stage — compilers, headers and the full source tree. None of it ships.
# ---------------------------------------------------------------------------
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev pkg-config && \
    rm -rf /var/lib/apt/lists/*

# Gems first, in their own layer: Gemfile.lock changes far less often than app code, so
# this layer is reused across most rebuilds.
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

COPY . .

# Bootsnap compile caches for app + lib. Saves ~1s of boot on every container start and,
# more usefully, keeps boot time steady — Coolify's health check has a deadline.
RUN bundle exec bootsnap precompile app/ lib/

# SECRET_KEY_BASE_DUMMY makes Rails synthesize a throwaway secret for the duration of
# this command. It exists precisely so that building an image does not require the real
# RAILS_MASTER_KEY: the key is a runtime secret injected by Coolify, and baking it into
# a build argument would leak it into the image history.
RUN SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile

# ---------------------------------------------------------------------------
# Runtime stage — no compilers, no source-control history, no dev/test gems.
# ---------------------------------------------------------------------------
FROM base

# libpq5 is the pg runtime (libpq-dev was build-only). postgresql-client provides psql
# for the one-time database bootstrap documented in README; curl serves the HEALTHCHECK.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libpq5 postgresql-client && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# Non-root. `tmp` is required (config/puma.rb writes tmp/pids/server.pid and Rails uses
# tmp/cache), `log` for the fallback file logger when RAILS_LOG_TO_STDOUT is unset,
# `storage` for Active Storage's :local service and for Thruster's own state directory.
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p tmp/pids storage log && \
    chown -R 1000:1000 db log storage tmp
USER 1000:1000

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# The port Puma binds behind Thruster. Thruster's own listener is set by the entrypoint
# (HTTP_PORT, defaulting to PORT, defaulting to 3000) rather than baked in here, so that
# a platform-injected PORT can win over the default without also overriding an operator
# who set HTTP_PORT deliberately. Note Thruster's built-in default listener is 80, which
# this non-root process could not bind — the entrypoint always sets it.
ENV TARGET_PORT=3001
EXPOSE 3000

# Exercises the same path Coolify's probe uses, and deliberately with the "wrong" Host
# (localhost, never APP_HOST) — so if the /up host-authorization exclusion in
# config/environments/production.rb is ever removed, `docker inspect` shows unhealthy
# instead of the failure only appearing on the platform.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS "http://localhost:${HTTP_PORT:-${PORT:-3000}}/up" || exit 1

# Thruster wraps Puma rather than replacing it. Why it is here even though Coolify's
# proxy already terminates TLS and is the edge:
#
#   * Compression and an HTTP cache in front of Puma. Measured on this image: a request
#     for the Tailwind bundle comes back `Content-Encoding: gzip` with `X-Cache: miss`
#     then `hit`. Without Thruster those bytes are uncompressed and every repeat request
#     occupies one of Puma's 5 threads — this app runs single-mode, no workers.
#   * X-Sendfile support, so Active Storage downloads do not stream through Ruby.
#   * It is a process supervisor, so one CMD gives one container with no init system.
#   * It is already in the Gemfile (require: false) and is the Rails 8 default, so this
#     is the least surprising shape for the next person.
#
# What Thruster is explicitly NOT doing here: serving public/ in place of Rails. That
# was the initial assumption and it is wrong — Thruster proxies first and caches the
# response, so with `config.public_file_server.enabled` false it faithfully caches a
# 404. Hence RAILS_SERVE_STATIC_FILES in the base stage above.
#
# The TLS half of Thruster is simply not used: TLS_DOMAIN is left unset, so it runs
# HTTP-only and Coolify stays the TLS terminator.
#
# To run the Solid Queue worker, deploy a SECOND Coolify service from this same image
# overriding the command with `bundle exec bin/jobs` (see README) — otherwise
# config/recurring.yml's ConcludeStaleDebatesJob never fires.
CMD ["bundle", "exec", "thrust", "bundle", "exec", "puma", "-C", "config/puma.rb"]
