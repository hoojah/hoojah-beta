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
