import { Controller } from "@hotwired/stimulus"

// Per-viewer reveal of a soft-held hujah image. The image is served to everyone
// (the hold is a display choice, not an access gate), so "Show anyway" only flips
// two elements locally — nothing persists, and a refresh re-hides it.
export default class extends Controller {
  static targets = ["veil", "image"]
  static values = { src: String }

  show() {
    // Inject the src on reveal so held images are never fetched until the viewer
    // opts in. Idempotent — set once, then a no-op on any repeat click.
    if (!this.imageTarget.getAttribute("src")) {
      this.imageTarget.src = this.srcValue
    }
    this.veilTarget.hidden = true
    this.imageTarget.hidden = false
  }
}
