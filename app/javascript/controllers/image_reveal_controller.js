import { Controller } from "@hotwired/stimulus"

// Per-viewer reveal of a soft-held hujah image. The image is served to everyone
// (the hold is a display choice, not an access gate), so "Show anyway" only flips
// two elements locally — nothing persists, and a refresh re-hides it.
export default class extends Controller {
  static targets = ["veil", "image"]

  show() {
    this.veilTarget.hidden = true
    this.imageTarget.hidden = false
  }
}
