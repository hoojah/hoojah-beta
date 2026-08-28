// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import { application } from "controllers/application"
import "controllers"

// Relative timestamps (<time data-local="time-ago" ...>). LocalTime.start() also
// re-processes elements inserted by Turbo Streams (its PageObserver watches the DOM).
import LocalTime from "local-time"
LocalTime.start()

// Before Turbo caches a page (bfcache-style snapshot), let every controller undo
// transient DOM state — chiefly close any open native <dialog> so a restored page
// never comes back with a stuck-open modal. Registered ONCE.
document.addEventListener("turbo:before-cache", () => {
  application.controllers.forEach((c) => c.teardown?.())
})

// Custom Turbo Stream action so a server response can close a modal remotely:
//   <turbo-stream action="close_dialog" target="<dom_id>"></turbo-stream>
// Registered ONCE. `this.targetElements` are the <dialog> elements matched by the
// stream's target/targets.
Turbo.StreamActions.close_dialog = function () {
  this.targetElements.forEach((el) => el.close())
}

// Navigate the browser from a server response:
//   <turbo-stream action="visit" url="/"></turbo-stream>
// Used by hujahs#destroy — it deletes the very record you are viewing, so the show
// page must leave itself. This app's write actions always answer with a Turbo Stream
// (the feed/moderation streams stay on the page); a plain `redirect_to` from a Stream-
// accepting submission is fetched but never rendered, so we navigate explicitly and
// keep it a SPA visit. Registered ONCE.
Turbo.StreamActions.visit = function () {
  // Same-origin relative paths only. Today the sole caller passes a server-set
  // `root_path`, but this is a global primitive — reject absolute or protocol-relative
  // (`//host`) URLs so a future call site can't turn it into an open redirect.
  const url = this.getAttribute("url")
  if (url && url.startsWith("/") && !url.startsWith("//")) Turbo.visit(url)
}

// Animate notification rows OUT before Turbo removes them. Marking a notification
// read responds with `<turbo-stream action="remove" target="notification_<id>">`
// (notifications/destroy.turbo_stream.erb), which otherwise deletes the node in the
// same frame. We wrap the stream's own `render` so the node fades + slides 8px right,
// THEN removes — scoped to `remove` actions on `notification_*` ids only, so no other
// stream is delayed. Reduced-motion opts straight out (the global CSS guard cannot
// help here — the delay is JS timing, not a CSS transition). Registered ONCE.
document.addEventListener("turbo:before-stream-render", (event) => {
  const stream = event.target
  if (stream.getAttribute("action") !== "remove") return
  const el = document.getElementById(stream.getAttribute("target"))
  if (!el || !el.id.startsWith("notification_")) return
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return
  const original = event.detail.render
  event.detail.render = (streamElement) => {
    el.style.transition = "opacity 160ms var(--ease-out), transform 160ms var(--ease-out)"
    el.style.opacity = "0"
    el.style.transform = "translateX(8px)"
    setTimeout(() => original(streamElement), 160)
  }
})
